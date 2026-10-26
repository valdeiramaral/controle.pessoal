import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { SignJWT } from 'jose';
import { criarApp } from '../src/app.js';
import { criarPool, comUsuario } from '../src/db.js';
import { promover } from '../src/admin.js';
import { prepararBanco, removerBanco, configDeTeste } from './ajuda.js';

const SENHA = 'uma-senha-forte-123';
let su;      // conexao de superusuario (ajusta dados fora da API)
let pool;
let app;
let config;

const post = (url, payload, token) => app.inject({
  method: 'POST', url, payload,
  headers: token ? { authorization: `Bearer ${token}` } : {},
});
const get = (url, token) => app.inject({
  method: 'GET', url, headers: token ? { authorization: `Bearer ${token}` } : {},
});
const patch = (url, payload, token) => app.inject({
  method: 'PATCH', url, payload, headers: { authorization: `Bearer ${token}` },
});

// CPF valido e diferente a cada chamada (numero base sequencial + 2 digitos verificadores).
let seqCpf = 100000000;
function cpfNovo() {
  const d = String(++seqCpf).padStart(9, '0').split('').map(Number);
  const dv = (n) => {
    const s = d.slice(0, n).reduce((a, x, i) => a + x * (n + 1 - i), 0);
    const r = (s * 10) % 11;
    return r === 10 ? 0 : r;
  };
  d.push(dv(9)); d.push(dv(10));
  return d.join('');
}
const pessoa = () => ({ cpf: cpfNovo(), telefone: '(11) 98765-4321' });

async function cadastrar(email, extra = {}) {
  const r = await post('/cadastro', { nome: 'Pessoa Teste', email, senha: SENHA, ...pessoa(), ...extra });
  assert.equal(r.statusCode, 201, r.body);
  return r.json().id;
}
async function entrar(email, senha = SENHA) {
  const r = await post('/login', { email, senha });
  assert.equal(r.statusCode, 200, r.body);
  return r.json().token;
}

before(async () => {
  su = await prepararBanco();
  config = configDeTeste();
  pool = criarPool(config.db);
  app = await criarApp({ pool, config });
});

after(async () => {
  await app?.close();
  await pool?.end();
  await su?.end();
  await removerBanco();
});

describe('saude', () => {
  it('responde ok quando o banco esta de pe', async () => {
    const r = await get('/saude');
    assert.equal(r.statusCode, 200);
    assert.deepEqual(r.json(), { ok: true });
  });
});

describe('CORS (app web)', () => {
  it('libera localhost em qualquer porta, inclusive o preflight', async () => {
    const r = await app.inject({
      method: 'OPTIONS', url: '/login',
      headers: { origin: 'http://localhost:8081', 'access-control-request-method': 'POST' },
    });
    assert.equal(r.statusCode, 204);
    assert.equal(r.headers['access-control-allow-origin'], 'http://localhost:8081');
    assert.match(r.headers['access-control-allow-headers'], /authorization/);
    const g = await app.inject({ method: 'GET', url: '/saude', headers: { origin: 'http://127.0.0.1:5000' } });
    assert.equal(g.headers['access-control-allow-origin'], 'http://127.0.0.1:5000');
  });

  it('nao libera outros sites', async () => {
    const r = await app.inject({ method: 'GET', url: '/saude', headers: { origin: 'https://site-mal-intencionado.com' } });
    assert.equal(r.statusCode, 200);
    assert.equal(r.headers['access-control-allow-origin'], undefined);
    const p = await app.inject({ method: 'OPTIONS', url: '/login', headers: { origin: 'http://localhost.evil.com' } });
    assert.equal(p.headers['access-control-allow-origin'], undefined);
  });
});

describe('cadastro', () => {
  it('cria o usuario e guarda so o hash argon2id da senha', async () => {
    const id = await cadastrar('ana@exemplo.com');
    const { rows } = await su.query('SELECT senha_hash, email FROM controle.usuario WHERE id = $1', [id]);
    assert.match(rows[0].senha_hash, /^\$argon2id\$/);
    assert.ok(!rows[0].senha_hash.includes(SENHA));
  });

  it('guarda o e-mail em minusculas e sem espacos', async () => {
    await cadastrar('  Bia@Exemplo.COM ');
    const { rows } = await su.query("SELECT count(*)::int AS n FROM controle.usuario WHERE email = 'bia@exemplo.com'");
    assert.equal(rows[0].n, 1);
  });

  it('recusa e-mail repetido (mesmo com maiusculas) com 409', async () => {
    const r = await post('/cadastro', { nome: 'X', email: 'ANA@exemplo.com', senha: SENHA, ...pessoa() });
    assert.equal(r.statusCode, 409);
    assert.equal(r.json().erro, 'email_ja_cadastrado');
  });

  it('recusa e-mail invalido, senha curta, nome vazio e campo desconhecido', async () => {
    const base = { nome: 'X', email: 'x@exemplo.com', senha: SENHA, ...pessoa() };
    assert.equal((await post('/cadastro', { ...base, email: 'sem-arroba' })).json().erro, 'email_invalido');
    assert.equal((await post('/cadastro', { ...base, senha: '1234567' })).statusCode, 400);
    assert.equal((await post('/cadastro', { ...base, nome: '   ' })).statusCode, 400);
    assert.equal((await post('/cadastro', { ...base, admin: true })).statusCode, 400);
  });

  it('recusa pais inexistente', async () => {
    const r = await post('/cadastro', { nome: 'X', email: 'pais@exemplo.com', senha: SENHA, pais: 'ZZ', ...pessoa() });
    assert.equal(r.statusCode, 400);
  });

  it('o pais define idioma, moeda e fuso padrao', async () => {
    await cadastrar('lisboa@exemplo.com', { pais: 'PT' });
    const me = (await get('/me', await entrar('lisboa@exemplo.com'))).json();
    assert.equal(me.usuario.idioma, 'pt-PT');
    assert.equal(me.usuario.moeda_padrao, 'EUR');
    assert.equal(me.usuario.fuso_horario, 'Europe/Lisbon');
  });
});

describe('cadastro: dados da pessoa', () => {
  const base = () => ({ nome: 'Cida', email: `cida${Math.random().toString(36).slice(2)}@exemplo.com`, senha: SENHA });

  it('CPF e telefone sao obrigatorios', async () => {
    const semCpf = await post('/cadastro', { ...base(), telefone: '11987654321' });
    assert.equal(semCpf.statusCode, 400);
    const semTel = await post('/cadastro', { ...base(), cpf: cpfNovo() });
    assert.equal(semTel.statusCode, 400);
  });

  it('CPF invalido e recusado com o campo no erro', async () => {
    const r = await post('/cadastro', { ...base(), cpf: '529.982.247-24', telefone: '11987654321' });
    assert.equal(r.statusCode, 400);
    assert.equal(r.json().campo, 'cpf');
    const igual = await post('/cadastro', { ...base(), cpf: '111.111.111-11', telefone: '11987654321' });
    assert.equal(igual.json().campo, 'cpf');
  });

  it('telefone fora do formato e recusado', async () => {
    const r = await post('/cadastro', { ...base(), cpf: cpfNovo(), telefone: '1234' });
    assert.equal(r.statusCode, 400);
    assert.equal(r.json().campo, 'telefone');
  });

  it('aceita CPF e telefone com mascara, guarda so os digitos, e CPF repetido da 409', async () => {
    const r = await post('/cadastro', { ...base(), cpf: '529.982.247-25', telefone: '(11) 98765-4321' });
    assert.equal(r.statusCode, 201, r.body);
    const { rows } = await su.query('SELECT cpf, telefone FROM controle.usuario WHERE id = $1', [r.json().id]);
    assert.deepEqual(rows[0], { cpf: '52998224725', telefone: '11987654321' });

    const dup = await post('/cadastro', { ...base(), cpf: '52998224725', telefone: '11987654321' });
    assert.equal(dup.statusCode, 409);
    assert.equal(dup.json().erro, 'cpf_ja_cadastrado');
  });

  it('guarda nascimento e endereco completo e devolve em /me', async () => {
    const email = 'endereco@exemplo.com';
    await cadastrar(email, {
      nascimento: '1990-05-17',
      endereco: { cep: '01310-100', logradouro: 'Av. Paulista', numero: '1000', complemento: 'Sala 2',
        bairro: 'Bela Vista', cidade: 'Sao Paulo', uf: 'sp' },
    });
    const me = (await get('/me', await entrar(email))).json().usuario;
    assert.equal(me.nascimento, '1990-05-17');
    assert.deepEqual(me.endereco, { cep: '01310100', logradouro: 'Av. Paulista', numero: '1000',
      complemento: 'Sala 2', bairro: 'Bela Vista', cidade: 'Sao Paulo', uf: 'SP' });
    assert.equal(me.telefone, '11987654321');
    assert.equal(me.cpf.length, 11);
  });

  it('recusa nascimento no futuro, CEP e UF invalidos', async () => {
    const f = await post('/cadastro', { ...base(), ...pessoa(), nascimento: '2999-01-01' });
    assert.equal(f.json().campo, 'nascimento');
    const cep = await post('/cadastro', { ...base(), ...pessoa(), endereco: { cep: '123' } });
    assert.equal(cep.json().campo, 'cep');
    const uf = await post('/cadastro', { ...base(), ...pessoa(), endereco: { uf: 'XX' } });
    assert.equal(uf.json().campo, 'uf');
  });
});

describe('PATCH /me (o proprio usuario)', () => {
  it('atualiza telefone e endereco, mas nao CPF nem e-mail', async () => {
    const email = 'perfil@exemplo.com';
    await cadastrar(email);
    const token = await entrar(email);
    const ok = await app.inject({ method: 'PATCH', url: '/me', headers: { authorization: `Bearer ${token}` },
      payload: { telefone: '21 3333-4444', endereco: { cidade: 'Rio de Janeiro', uf: 'rj' } } });
    assert.equal(ok.statusCode, 200, ok.body);
    assert.equal(ok.json().usuario.telefone, '2133334444');
    assert.equal(ok.json().usuario.endereco.uf, 'RJ');

    for (const proibido of [{ cpf: '52998224725' }, { email: 'outro@exemplo.com' }, { ativo: false }]) {
      const r = await app.inject({ method: 'PATCH', url: '/me', headers: { authorization: `Bearer ${token}` }, payload: proibido });
      assert.equal(r.statusCode, 400, JSON.stringify(proibido));
    }
    assert.equal((await app.inject({ method: 'PATCH', url: '/me', payload: { telefone: '11987654321' } })).statusCode, 401);
  });
});

describe('login', () => {
  it('devolve token e dados basicos', async () => {
    const r = await post('/login', { email: 'ANA@exemplo.com', senha: SENHA });
    assert.equal(r.statusCode, 200);
    const j = r.json();
    assert.ok(j.token.split('.').length === 3);
    assert.equal(j.usuario.pais, 'BR');
    assert.equal(j.expira_em_segundos, 3600);
  });

  it('senha errada e e-mail inexistente dao a mesma resposta 401', async () => {
    const a = await post('/login', { email: 'ana@exemplo.com', senha: 'errada-errada' });
    const b = await post('/login', { email: 'ninguem@exemplo.com', senha: 'errada-errada' });
    assert.equal(a.statusCode, 401);
    assert.equal(b.statusCode, 401);
    assert.deepEqual(a.json(), b.json());
  });

  it('5 erros seguidos bloqueiam a conta (423), mesmo com a senha certa', async () => {
    await cadastrar('bloqueio@exemplo.com');
    for (let i = 0; i < 5; i++) {
      assert.equal((await post('/login', { email: 'bloqueio@exemplo.com', senha: 'errada-errada' })).statusCode, 401);
    }
    const r = await post('/login', { email: 'bloqueio@exemplo.com', senha: SENHA });
    assert.equal(r.statusCode, 423);
    assert.equal(r.json().erro, 'conta_bloqueada');
    // Enquanto bloqueada, mais tentativas nao prolongam o bloqueio.
    const antes = (await su.query("SELECT bloqueado_ate FROM controle.usuario WHERE email = 'bloqueio@exemplo.com'")).rows[0].bloqueado_ate;
    await post('/login', { email: 'bloqueio@exemplo.com', senha: 'errada-errada' });
    const depois = (await su.query("SELECT bloqueado_ate FROM controle.usuario WHERE email = 'bloqueio@exemplo.com'")).rows[0].bloqueado_ate;
    assert.equal(depois.getTime(), antes.getTime());
  });

  it('passado o bloqueio, a senha certa entra e zera as tentativas', async () => {
    await su.query("UPDATE controle.usuario SET bloqueado_ate = now() - interval '1 minute' WHERE email = 'bloqueio@exemplo.com'");
    await entrar('bloqueio@exemplo.com');
    const { rows } = await su.query("SELECT tentativas_login, bloqueado_ate FROM controle.usuario WHERE email = 'bloqueio@exemplo.com'");
    assert.equal(rows[0].tentativas_login, 0);
    assert.equal(rows[0].bloqueado_ate, null);
  });

  it('exige e-mail e senha', async () => {
    assert.equal((await post('/login', { email: 'ana@exemplo.com' })).statusCode, 400);
  });
});

describe('/me', () => {
  it('sem token, com token adulterado ou expirado: 401', async () => {
    assert.equal((await get('/me')).statusCode, 401);
    const token = await entrar('ana@exemplo.com');
    assert.equal((await get('/me', token.slice(0, -3) + 'abc')).statusCode, 401);
    const expirado = await new SignJWT({}).setProtectedHeader({ alg: 'HS256' })
      .setSubject('00000000-0000-0000-0000-000000000000').setIssuer('controle-pessoal')
      .setIssuedAt(Math.floor(Date.now() / 1000) - 7200).setExpirationTime('1h')
      .sign(new TextEncoder().encode(config.jwtSecret));
    assert.equal((await get('/me', expirado)).statusCode, 401);
  });

  it('rejeita token assinado com outro segredo', async () => {
    const id = (await su.query("SELECT id FROM controle.usuario WHERE email = 'ana@exemplo.com'")).rows[0].id;
    const falso = await new SignJWT({}).setProtectedHeader({ alg: 'HS256' })
      .setSubject(id).setIssuer('controle-pessoal').setIssuedAt().setExpirationTime('1h')
      .sign(new TextEncoder().encode('outro-segredo-que-o-atacante-inventou-123456'));
    assert.equal((await get('/me', falso)).statusCode, 401);
  });

  it('usuario comum: modulos de uso diario, licenca gratuita e sem permissoes de administracao', async () => {
    const me = (await get('/me', await entrar('ana@exemplo.com'))).json();
    assert.equal(me.usuario.email, 'ana@exemplo.com');
    assert.equal(me.licenca.plano, 'gratuito');
    assert.equal(me.acesso, true);
    for (const m of ['financas', 'saude', 'agenda', 'painel', 'sincronizacao']) {
      assert.ok(me.modulos.includes(m), 'faltou o modulo ' + m);
    }
    assert.ok(me.permissoes.includes('financas.lancamento.ver'));
    assert.ok(!me.permissoes.includes('acesso.usuario.ver'));
    assert.ok(!me.modulos.includes('administracao'));
    assert.equal('senha_hash' in me.usuario, false);
  });

  it('com a cobranca ligada e sem licenca paga, acesso = false', async () => {
    await su.query("UPDATE controle.configuracao SET valor = 'true' WHERE chave = 'cobranca_ativa'");
    try {
      const me = (await get('/me', await entrar('ana@exemplo.com'))).json();
      assert.equal(me.acesso, false);
    } finally {
      await su.query("UPDATE controle.configuracao SET valor = 'false' WHERE chave = 'cobranca_ativa'");
    }
  });

  it('o usuario so enxerga a si mesmo pelo banco (RLS), e o modo admin enxerga todos', async () => {
    const id = (await su.query("SELECT id FROM controle.usuario WHERE email = 'ana@exemplo.com'")).rows[0].id;
    const total = (await su.query('SELECT count(*)::int AS n FROM controle.usuario')).rows[0].n;
    const comum = await comUsuario(pool, id, async (c) => (await c.query('SELECT count(*)::int AS n FROM controle.usuario')).rows[0].n);
    const admin = await comUsuario(pool, id, async (c) => (await c.query('SELECT count(*)::int AS n FROM controle.usuario')).rows[0].n, { admin: true });
    assert.equal(comum, 1);
    assert.equal(admin, total);
    // O modo admin nao vaza para a proxima transacao na mesma conexao.
    const depois = await comUsuario(pool, id, async (c) => (await c.query('SELECT count(*)::int AS n FROM controle.usuario')).rows[0].n);
    assert.equal(depois, 1);
  });
});

describe('administracao de usuarios', () => {
  let tokenAdmin;
  let tokenComum;
  let idComum;

  before(async () => {
    await cadastrar('admin@exemplo.com');
    idComum = await cadastrar('comum@exemplo.com');
    await promover(pool, 'admin@exemplo.com');
    tokenAdmin = await entrar('admin@exemplo.com');
    tokenComum = await entrar('comum@exemplo.com');
  });

  it('usuario comum recebe 403 e administrador recebe a lista', async () => {
    const negado = await get('/usuarios', tokenComum);
    assert.equal(negado.statusCode, 403);
    assert.equal(negado.json().permissao, 'acesso.usuario.ver');
    assert.equal((await get('/usuarios')).statusCode, 401);

    const r = await get('/usuarios?limite=2', tokenAdmin);
    assert.equal(r.statusCode, 200);
    const j = r.json();
    assert.ok(j.total >= 4);
    assert.equal(j.itens.length, 2);
    assert.equal('senha_hash' in j.itens[0], false);
  });

  it('o administrador aparece com o perfil e as permissoes de administracao em /me', async () => {
    const me = (await get('/me', tokenAdmin)).json();
    assert.ok(me.permissoes.includes('acesso.usuario.editar'));
    assert.ok(me.modulos.includes('administracao'));
  });

  it('usuario comum nao desativa ninguem; administrador desativa e a conta cai na hora', async () => {
    assert.equal((await patch(`/usuarios/${idComum}`, { ativo: false }, tokenComum)).statusCode, 403);

    const r = await patch(`/usuarios/${idComum}`, { ativo: false }, tokenAdmin);
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().ativo, false);

    // O token que ja existia deixa de valer imediatamente...
    assert.equal((await get('/me', tokenComum)).statusCode, 401);
    // ...e um novo login e recusado (senha certa, conta inativa).
    const login = await post('/login', { email: 'comum@exemplo.com', senha: SENHA });
    assert.equal(login.statusCode, 403);
    assert.equal(login.json().erro, 'conta_inativa');

    const volta = await patch(`/usuarios/${idComum}`, { ativo: true }, tokenAdmin);
    assert.equal(volta.json().ativo, true);
    assert.equal((await post('/login', { email: 'comum@exemplo.com', senha: SENHA })).statusCode, 200);
  });

  it('o administrador nao desativa a si mesmo e id invalido ou inexistente falha', async () => {
    const idAdmin = (await su.query("SELECT id FROM controle.usuario WHERE email = 'admin@exemplo.com'")).rows[0].id;
    assert.equal((await patch(`/usuarios/${idAdmin}`, { ativo: false }, tokenAdmin)).statusCode, 400);
    assert.equal((await patch('/usuarios/nao-e-uuid', { ativo: false }, tokenAdmin)).statusCode, 400);
    assert.equal((await patch('/usuarios/11111111-1111-1111-1111-111111111111', { ativo: false }, tokenAdmin)).statusCode, 404);
  });

  const put = (url, payload, token) => app.inject({
    method: 'PUT', url, payload, headers: { authorization: `Bearer ${token}` } });

  it('GET /usuarios/:id traz dados, plano, perfis e modulos; usuario comum recebe 403', async () => {
    assert.equal((await get(`/usuarios/${idComum}`, tokenComum)).statusCode, 403);
    const r = await get(`/usuarios/${idComum}`, tokenAdmin);
    assert.equal(r.statusCode, 200);
    const j = r.json();
    assert.equal(j.usuario.email, 'comum@exemplo.com');
    assert.equal(j.usuario.cpf.length, 11);
    assert.equal(j.licenca.plano, 'gratuito');
    assert.deepEqual(j.perfis, ['usuario']);
    const fin = j.modulos.find((m) => m.codigo === 'financas');
    assert.equal(fin.liberacao, 'padrao');
    assert.equal(fin.efetivo, true);
    assert.equal((await get('/usuarios/11111111-1111-1111-1111-111111111111', tokenAdmin)).statusCode, 404);
  });

  it('busca por nome, e-mail ou CPF', async () => {
    const cpf = (await get(`/usuarios/${idComum}`, tokenAdmin)).json().usuario.cpf;
    const porEmail = (await get('/usuarios?busca=comum@', tokenAdmin)).json();
    assert.equal(porEmail.total, 1);
    const porCpf = (await get(`/usuarios?busca=${cpf.slice(0, 6)}`, tokenAdmin)).json();
    assert.ok(porCpf.itens.some((u) => u.id === idComum));
    assert.equal((await get('/usuarios?busca=zzzz-nao-existe', tokenAdmin)).json().total, 0);
  });

  it('GET /catalogo lista planos, modulos e perfis', async () => {
    assert.equal((await get('/catalogo', tokenComum)).statusCode, 403);
    const j = (await get('/catalogo', tokenAdmin)).json();
    assert.deepEqual(j.planos.map((p) => p.codigo).sort(), ['anual', 'gratuito', 'mensal', 'vitalicio']);
    assert.ok(j.modulos.some((m) => m.codigo === 'saude'));
    assert.ok(j.perfis.some((p) => p.codigo === 'administrador'));
  });

  it('administrador bloqueia e libera modulos de UM usuario, e isso vale em /me', async () => {
    const r = await put(`/usuarios/${idComum}/modulos`, { modulos: { saude: false } }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    const saude = r.json().modulos.find((m) => m.codigo === 'saude');
    assert.equal(saude.liberacao, 'bloqueado');
    assert.equal(saude.efetivo, false);
    const me = (await get('/me', tokenComum)).json();
    assert.ok(!me.modulos.includes('saude'));
    assert.ok(me.modulos.includes('financas'));

    // volta ao padrao do plano
    const volta = await put(`/usuarios/${idComum}/modulos`, { modulos: { saude: null } }, tokenAdmin);
    assert.equal(volta.json().modulos.find((m) => m.codigo === 'saude').efetivo, true);
    assert.ok((await get('/me', tokenComum)).json().modulos.includes('saude'));

    assert.equal((await put(`/usuarios/${idComum}/modulos`, { modulos: { saude: false } }, tokenComum)).statusCode, 403);
    assert.equal((await put(`/usuarios/${idComum}/modulos`, { modulos: { modulo_falso: true } }, tokenAdmin)).statusCode, 400);
    await put(`/usuarios/${idComum}/modulos`, { modulos: { saude: null } }, tokenAdmin);
  });

  it('administrador troca o plano; a licenca antiga e cancelada', async () => {
    const r = await put(`/usuarios/${idComum}/plano`, { plano: 'anual' }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    assert.equal(r.json().licenca.plano, 'anual');
    assert.equal(r.json().licenca.origem, 'cortesia');
    const { rows } = await su.query(
      "SELECT plano_codigo, status FROM controle.licenca WHERE usuario_id = $1 ORDER BY criado_em, plano_codigo", [idComum]);
    assert.ok(rows.some((l) => l.plano_codigo === 'gratuito' && l.status === 'cancelada'));
    assert.equal(rows.filter((l) => l.status === 'ativa').length, 1);

    assert.equal((await put(`/usuarios/${idComum}/plano`, { plano: 'anual' }, tokenComum)).statusCode, 403);
    assert.equal((await put(`/usuarios/${idComum}/plano`, { plano: 'inexistente' }, tokenAdmin)).statusCode, 400);
    await put(`/usuarios/${idComum}/plano`, { plano: 'gratuito' }, tokenAdmin);
  });

  it('administrador troca os perfis e nao tira o proprio perfil de administrador', async () => {
    const r = await put(`/usuarios/${idComum}/perfis`, { perfis: ['leitura'] }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    assert.deepEqual(r.json().perfis, ['leitura']);
    const me = (await get('/me', tokenComum)).json();
    assert.ok(!me.permissoes.includes('financas.lancamento.editar'));
    assert.ok(me.permissoes.includes('financas.lancamento.ver'));

    assert.equal((await put(`/usuarios/${idComum}/perfis`, { perfis: ['perfil-falso'] }, tokenAdmin)).statusCode, 400);
    assert.equal((await put(`/usuarios/${idComum}/perfis`, { perfis: [] }, tokenAdmin)).statusCode, 400);
    const idAdmin = (await su.query("SELECT id FROM controle.usuario WHERE email = 'admin@exemplo.com'")).rows[0].id;
    const sozinho = await put(`/usuarios/${idAdmin}/perfis`, { perfis: ['usuario'] }, tokenAdmin);
    assert.equal(sozinho.statusCode, 400);
    await put(`/usuarios/${idComum}/perfis`, { perfis: ['usuario'] }, tokenAdmin);
  });

  it('administrador cadastra um usuario ja com plano, perfil e modulos liberados', async () => {
    const r = await app.inject({
      method: 'POST', url: '/usuarios', headers: { authorization: `Bearer ${tokenAdmin}` },
      payload: {
        nome: 'Davi Novo', email: 'davi@exemplo.com', senha: SENHA, ...pessoa(),
        nascimento: '1985-03-02', endereco: { cidade: 'Curitiba', uf: 'PR' },
        plano: 'mensal', perfis: ['usuario'], modulos: { saude: false, painel: true },
      },
    });
    assert.equal(r.statusCode, 201, r.body);
    const j = r.json();
    assert.equal(j.licenca.plano, 'mensal');
    assert.deepEqual(j.perfis, ['usuario']);
    assert.equal(j.modulos.find((m) => m.codigo === 'saude').efetivo, false);
    assert.equal(j.modulos.find((m) => m.codigo === 'painel').liberacao, 'liberado');
    assert.equal(j.usuario.endereco.cidade, 'Curitiba');

    // o novo usuario ja consegue entrar e so ve os modulos liberados
    const me = (await get('/me', await entrar('davi@exemplo.com'))).json();
    assert.ok(me.modulos.includes('financas'));
    assert.ok(!me.modulos.includes('saude'));
  });

  it('cadastro pelo administrador: CPF repetido da 409 e usuario comum recebe 403', async () => {
    const cpf = (await get(`/usuarios/${idComum}`, tokenAdmin)).json().usuario.cpf;
    const dup = await app.inject({ method: 'POST', url: '/usuarios', headers: { authorization: `Bearer ${tokenAdmin}` },
      payload: { nome: 'Eva', email: 'eva@exemplo.com', senha: SENHA, cpf, telefone: '11987654321' } });
    assert.equal(dup.statusCode, 409);
    assert.equal(dup.json().erro, 'cpf_ja_cadastrado');
    const negado = await app.inject({ method: 'POST', url: '/usuarios', headers: { authorization: `Bearer ${tokenComum}` },
      payload: { nome: 'Eva', email: 'eva@exemplo.com', senha: SENHA, ...pessoa() } });
    assert.equal(negado.statusCode, 403);
  });

  it('administrador edita os dados pessoais de outro usuario (inclusive CPF)', async () => {
    const novoCpf = cpfNovo();
    const r = await patch(`/usuarios/${idComum}`, { nome: 'Comum Editado', cpf: novoCpf, telefone: '31 99999-0000',
      endereco: { cidade: 'Belo Horizonte', uf: 'MG' } }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    const d = (await get(`/usuarios/${idComum}`, tokenAdmin)).json().usuario;
    assert.equal(d.nome, 'Comum Editado');
    assert.equal(d.cpf, novoCpf);
    assert.equal(d.telefone, '31999990000');
    assert.equal(d.endereco.uf, 'MG');
    const ruim = await patch(`/usuarios/${idComum}`, { cpf: '123' }, tokenAdmin);
    assert.equal(ruim.statusCode, 400);
  });

  it('promover avisa quando o usuario ou o perfil nao existem', async () => {
    await assert.rejects(() => promover(pool, 'nao-existe@exemplo.com'), /usuario nao encontrado/);
    await assert.rejects(() => promover(pool, 'ana@exemplo.com', 'perfil-falso'), /perfil nao encontrado/);
  });
});
