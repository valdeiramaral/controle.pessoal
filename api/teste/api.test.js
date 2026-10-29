import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { SignJWT } from 'jose';
import { criarApp } from '../src/app.js';
import { criarPool, comUsuario } from '../src/db.js';
import { promover, criarSuperusuario } from '../src/admin.js';
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
    await su.query("UPDATE controle.usuario SET superusuario = true WHERE email = 'admin@exemplo.com'");
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

describe('perfis, grupos e permissoes individuais', () => {
  let tokenAdmin;
  let tokenComum;
  let idComum;
  let idAdmin;

  const send = (method, url, payload, token) => app.inject({
    method, url, payload, headers: { authorization: `Bearer ${token}` } });
  const permissoesDe = async (token) => (await get('/me', token)).json().permissoes;

  before(async () => {
    idAdmin = await cadastrar('adm-acesso@exemplo.com');
    idComum = await cadastrar('comum-acesso@exemplo.com');
    await promover(pool, 'adm-acesso@exemplo.com');
    await su.query("UPDATE controle.usuario SET superusuario = true WHERE email = 'adm-acesso@exemplo.com'");
    tokenAdmin = await entrar('adm-acesso@exemplo.com');
    tokenComum = await entrar('comum-acesso@exemplo.com');
  });

  it('GET /permissoes lista o catalogo por modulo; usuario comum recebe 403', async () => {
    assert.equal((await get('/permissoes', tokenComum)).statusCode, 403);
    const j = (await get('/permissoes', tokenAdmin)).json();
    assert.ok(j.permissoes.length >= 27);
    const p = j.permissoes.find((x) => x.codigo === 'financas.conta.gerenciar');
    assert.equal(p.modulo_codigo, 'financas');
    assert.equal(p.modulo_nome, 'Finanças');
  });

  it('GET /perfis lista os de fabrica com contagens', async () => {
    const j = (await get('/perfis', tokenAdmin)).json();
    const adm = j.itens.find((x) => x.codigo === 'administrador');
    assert.equal(adm.sistema, true);
    assert.ok(adm.total_permissoes >= 27);
    assert.ok(adm.total_usuarios >= 1);
    assert.ok(j.itens.some((x) => x.codigo === 'leitura'));
  });

  let idPerfil;
  it('cria um perfil novo com permissoes detalhadas e o codigo vem do nome', async () => {
    const r = await send('POST', '/perfis', {
      nome: 'Contador Externo', descricao: 'So finanças',
      permissoes: ['financas.lancamento.ver', 'financas.lancamento.editar'],
    }, tokenAdmin);
    assert.equal(r.statusCode, 201, r.body);
    const j = r.json();
    assert.equal(j.codigo, 'contador_externo');
    assert.equal(j.sistema, false);
    assert.deepEqual(j.permissoes, ['financas.lancamento.editar', 'financas.lancamento.ver']);
    idPerfil = j.id;

    assert.equal((await send('POST', '/perfis', { nome: 'contador externo' }, tokenAdmin)).statusCode, 409);
    assert.equal((await send('POST', '/perfis', { nome: 'X', permissoes: ['nao.existe.nada'] }, tokenAdmin)).statusCode, 400);
    assert.equal((await send('POST', '/perfis', { nome: '!!!' }, tokenAdmin)).statusCode, 400);
    assert.equal((await send('POST', '/perfis', { nome: 'Outro' }, tokenComum)).statusCode, 403);
  });

  it('atribuir o perfil novo ao usuario libera exatamente aquelas permissoes', async () => {
    const r = await send('PUT', `/usuarios/${idComum}/perfis`, { perfis: ['contador_externo'] }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    const ps = await permissoesDe(tokenComum);
    assert.deepEqual(ps, ['financas.lancamento.editar', 'financas.lancamento.ver']);
  });

  it('editar as permissoes do perfil vale na hora para quem o tem', async () => {
    const r = await send('PUT', `/perfis/${idPerfil}`, {
      nome: 'Contador', permissoes: ['financas.lancamento.ver'] }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    assert.equal(r.json().nome, 'Contador');
    assert.equal(r.json().codigo, 'contador_externo'); // o codigo nao muda
    assert.deepEqual(await permissoesDe(tokenComum), ['financas.lancamento.ver']);
    assert.equal((await send('PUT', `/perfis/${idPerfil}`, { nome: 'Z' }, tokenComum)).statusCode, 403);
    assert.equal((await send('PUT', '/perfis/11111111-1111-1111-1111-111111111111', { nome: 'Z' }, tokenAdmin)).statusCode, 404);
  });

  it('o perfil administrador nao tem as permissoes alteradas, mas pode mudar de descricao', async () => {
    const adm = (await get('/perfis', tokenAdmin)).json().itens.find((x) => x.codigo === 'administrador');
    const trava = await send('PUT', `/perfis/${adm.id}`, { permissoes: ['acesso.usuario.ver'] }, tokenAdmin);
    assert.equal(trava.statusCode, 400);
    assert.equal(trava.json().erro, 'perfil_administrador_fixo');
    const ok = await send('PUT', `/perfis/${adm.id}`, { descricao: 'Acesso total' }, tokenAdmin);
    assert.equal(ok.statusCode, 200);
    assert.equal(ok.json().descricao, 'Acesso total');
    assert.ok((await permissoesDe(tokenAdmin)).includes('acesso.usuario.editar'));
  });

  it('nao apaga perfil de fabrica nem perfil em uso; apaga o que ninguem usa', async () => {
    const leitura = (await get('/perfis', tokenAdmin)).json().itens.find((x) => x.codigo === 'leitura');
    const sist = await send('DELETE', `/perfis/${leitura.id}`, undefined, tokenAdmin);
    assert.equal(sist.statusCode, 400);
    assert.equal(sist.json().erro, 'perfil_de_sistema');

    const uso = await send('DELETE', `/perfis/${idPerfil}`, undefined, tokenAdmin);
    assert.equal(uso.statusCode, 409);
    assert.equal(uso.json().usuarios, 1);

    await send('PUT', `/usuarios/${idComum}/perfis`, { perfis: ['usuario'] }, tokenAdmin);
    assert.equal((await send('DELETE', `/perfis/${idPerfil}`, undefined, tokenAdmin)).statusCode, 204);
    assert.equal((await get(`/perfis/${idPerfil}`, tokenAdmin)).statusCode, 404);
  });

  let idGrupo;
  it('cria um grupo com perfil e membros; o membro herda as permissoes do perfil do grupo', async () => {
    await send('POST', '/perfis', { nome: 'Agenda Leve', permissoes: ['agenda.evento.ver', 'agenda.evento.editar'] }, tokenAdmin);
    // tira do usuario comum o perfil "usuario" para ver so o efeito do grupo
    await send('PUT', `/usuarios/${idComum}/perfis`, { perfis: ['leitura'] }, tokenAdmin);
    const antes = await permissoesDe(tokenComum);
    assert.ok(!antes.includes('agenda.evento.editar'));

    const r = await send('POST', '/grupos', {
      nome: 'Equipe Agenda', descricao: 'Time de agenda', perfis: ['agenda_leve'], membros: [idComum],
    }, tokenAdmin);
    assert.equal(r.statusCode, 201, r.body);
    const g = r.json();
    assert.deepEqual(g.perfis, ['agenda_leve']);
    assert.deepEqual(g.membros.map((m) => m.id), [idComum]);
    idGrupo = g.id;
    assert.ok((await permissoesDe(tokenComum)).includes('agenda.evento.editar'));
  });

  it('GET /grupos lista com contagens; nome repetido da 409; comum recebe 403', async () => {
    const j = (await get('/grupos', tokenAdmin)).json();
    const g = j.itens.find((x) => x.id === idGrupo);
    assert.equal(g.total_membros, 1);
    assert.deepEqual(g.perfis, ['agenda_leve']);
    assert.equal((await send('POST', '/grupos', { nome: 'Equipe Agenda' }, tokenAdmin)).statusCode, 409);
    assert.equal((await send('POST', '/grupos', { nome: 'Nada' }, tokenComum)).statusCode, 403);
    assert.equal((await send('POST', '/grupos', { nome: 'Ruim', perfis: ['perfil-falso'] }, tokenAdmin)).statusCode, 400);
  });

  it('editar o grupo troca perfis e membros', async () => {
    const r = await send('PUT', `/grupos/${idGrupo}`, { nome: 'Equipe de Agenda', membros: [] }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    assert.equal(r.json().nome, 'Equipe de Agenda');
    assert.deepEqual(r.json().membros, []);
    assert.ok(!(await permissoesDe(tokenComum)).includes('agenda.evento.editar'));

    const volta = await send('PUT', `/usuarios/${idComum}/grupos`, { grupos: [idGrupo] }, tokenAdmin);
    assert.equal(volta.statusCode, 200, volta.body);
    assert.deepEqual(volta.json().grupos.map((x) => x.id), [idGrupo]);
    assert.ok((await permissoesDe(tokenComum)).includes('agenda.evento.editar'));
    assert.equal((await send('PUT', `/usuarios/${idComum}/grupos`, { grupos: ['11111111-1111-1111-1111-111111111111'] }, tokenAdmin)).statusCode, 400);
  });

  it('excecoes individuais: conceder uma permissao e negar outra (a negacao vence)', async () => {
    // concede: o usuario comum ganha uma permissao fora dos seus perfis
    const r = await send('PUT', `/usuarios/${idComum}/permissoes`, {
      permissoes: { 'financas.conta.gerenciar': true, 'agenda.evento.editar': false } }, tokenAdmin);
    assert.equal(r.statusCode, 200, r.body);
    assert.deepEqual(r.json().excecoes, { 'financas.conta.gerenciar': true, 'agenda.evento.editar': false });
    const ps = await permissoesDe(tokenComum);
    assert.ok(ps.includes('financas.conta.gerenciar'));
    assert.ok(!ps.includes('agenda.evento.editar')); // negada mesmo vindo do grupo
    assert.ok(r.json().permissoes.includes('financas.conta.gerenciar'));

    // volta ao herdado
    const volta = await send('PUT', `/usuarios/${idComum}/permissoes`, {
      permissoes: { 'financas.conta.gerenciar': null, 'agenda.evento.editar': null } }, tokenAdmin);
    assert.deepEqual(volta.json().excecoes, {});
    assert.ok((await permissoesDe(tokenComum)).includes('agenda.evento.editar'));

    assert.equal((await send('PUT', `/usuarios/${idComum}/permissoes`, { permissoes: { 'x.y.z': true } }, tokenAdmin)).statusCode, 400);
    assert.equal((await send('PUT', `/usuarios/${idComum}/permissoes`, { permissoes: { 'agenda.evento.ver': false } }, tokenComum)).statusCode, 403);
  });

  it('o administrador nao nega a si mesmo permissoes de acesso e administracao', async () => {
    const r = await send('PUT', `/usuarios/${idAdmin}/permissoes`, { permissoes: { 'acesso.usuario.editar': false } }, tokenAdmin);
    assert.equal(r.statusCode, 400);
    assert.equal(r.json().erro, 'nao_pode_negar_a_si_mesmo');
    // negar outra coisa a si mesmo pode
    const ok = await send('PUT', `/usuarios/${idAdmin}/permissoes`, { permissoes: { 'painel.relatorio.exportar': false } }, tokenAdmin);
    assert.equal(ok.statusCode, 200);
    await send('PUT', `/usuarios/${idAdmin}/permissoes`, { permissoes: { 'painel.relatorio.exportar': null } }, tokenAdmin);
  });

  it('GET /usuarios/:id traz grupos, excecoes e permissoes efetivas', async () => {
    const j = (await get(`/usuarios/${idComum}`, tokenAdmin)).json();
    assert.deepEqual(j.grupos.map((x) => x.id), [idGrupo]);
    assert.deepEqual(j.excecoes, {});
    assert.ok(Array.isArray(j.permissoes) && j.permissoes.includes('agenda.evento.editar'));
  });

  it('apagar o grupo tira as permissoes que vinham dele', async () => {
    assert.equal((await send('DELETE', `/grupos/${idGrupo}`, undefined, tokenAdmin)).statusCode, 204);
    assert.ok(!(await permissoesDe(tokenComum)).includes('agenda.evento.editar'));
    assert.equal((await send('DELETE', `/grupos/${idGrupo}`, undefined, tokenAdmin)).statusCode, 404);
  });
});

describe('superusuario de testes', () => {
  it('cria com todas as permissoes e modulos, entra pela API e pode ser repetido', async () => {
    const email = 'super@exemplo.com';
    const r = await criarSuperusuario(pool, { email, senha: 'senha-super-123' });
    assert.equal(r.criado, true);
    const token = await entrar(email, 'senha-super-123');
    const me = (await get('/me', token)).json();
    assert.ok(me.permissoes.includes('acesso.perfil.gerenciar'));
    assert.ok(me.modulos.includes('financas') && me.modulos.includes('saude') && me.modulos.includes('agenda'));
    assert.equal((await get('/perfis', token)).statusCode, 200);

    const de_novo = await criarSuperusuario(pool, { email, senha: 'outra-senha-456' });
    assert.equal(de_novo.criado, false);
    assert.equal(de_novo.id, r.id);
    await entrar(email, 'outra-senha-456');
  });
});

describe('excluir usuario', () => {
  it('exclusao logica: some da lista, nao entra mais, libera e-mail e nao exclui a si mesmo', async () => {
    const adm = await criarSuperusuario(pool, { email: 'chefe@exemplo.com', senha: 'senha-chefe-123' });
    const token = await entrar('chefe@exemplo.com', 'senha-chefe-123');
    const alvo = await cadastrar('apagar@exemplo.com');
    const del = (id) => app.inject({ method: 'DELETE', url: `/usuarios/${id}`, headers: { authorization: `Bearer ${token}` } });

    assert.equal((await del(adm.id)).json().erro, 'nao_pode_excluir_a_si_mesmo');
    assert.equal((await del(alvo)).statusCode, 204);
    assert.equal((await del(alvo)).statusCode, 404);
    assert.equal((await post('/login', { email: 'apagar@exemplo.com', senha: SENHA })).statusCode, 401);
    const lista = (await get('/usuarios?busca=apagar', token)).json();
    assert.equal(lista.total, 0);
    await cadastrar('apagar@exemplo.com'); // e-mail liberado
  });

  it('sem permissao nao exclui', async () => {
    await cadastrar('comum2@exemplo.com');
    const alvo = await cadastrar('alvo2@exemplo.com');
    const token = await entrar('comum2@exemplo.com');
    const r = await app.inject({ method: 'DELETE', url: `/usuarios/${alvo}`, headers: { authorization: `Bearer ${token}` } });
    assert.equal(r.statusCode, 403);
  });
});

describe('cadastro de modulos', () => {
  const com = (method, url, token, payload) => app.inject({ method, url, payload, headers: { authorization: `Bearer ${token}` } });

  it('SuperUsuario libera o modulo para varios usuarios, com validade ou vitalicio, e pode desativar', async () => {
    await criarSuperusuario(pool, { email: 'mod@exemplo.com', senha: 'senha-mod-123' });
    const token = await entrar('mod@exemplo.com', 'senha-mod-123');
    const idA = await cadastrar('lib-a@exemplo.com');
    const idB = await cadastrar('lib-b@exemplo.com');
    const idC = await cadastrar('lib-c@exemplo.com');
    const ta = await entrar('lib-a@exemplo.com');
    const tb = await entrar('lib-b@exemplo.com');
    const tc = await entrar('lib-c@exemplo.com');
    const dia = 24 * 3600 * 1000;
    const iso = (offsetDias) => new Date(Date.now() + offsetDias * dia).toISOString();

    const r = await com('POST', '/modulos', token, {
      nome: 'Academia & Treino', icone: 'fitness', descricao: 'Treinos',
      liberacoes: [{ usuario_id: idA }, { usuario_id: idB, vitalicio: false, inicio: iso(-1), fim: iso(30) }],
    });
    assert.equal(r.statusCode, 201, r.body);
    assert.equal(r.json().codigo, 'academia_treino');
    assert.equal(r.json().sistema, false);
    assert.equal(r.json().liberacoes.length, 2);
    assert.equal((await com('POST', '/modulos', token, { nome: 'Academia & Treino' })).statusCode, 409);

    // "fixo" e escolhido na liberacao de cada usuario (fixa o modulo no topo do menu dele)
    assert.equal(r.json().liberacoes.every((l) => l.fixo === true), true); // por padrao aparece no menu
    const noMenuA = async () => (await get('/meus-modulos', ta)).json().itens.some((m) => m.codigo === 'academia_treino');
    assert.equal(await noMenuA(), true);
    assert.equal((await com('PUT', '/modulos/academia_treino', token, {
      liberacoes: [{ usuario_id: idA, fixo: false }, { usuario_id: idB, vitalicio: false, inicio: iso(-1), fim: iso(30) }],
    })).statusCode, 200);
    assert.equal(await noMenuA(), false); // liberado, mas oculto do menu
    assert.equal((await com('PUT', '/modulos/academia_treino', token, {
      liberacoes: [{ usuario_id: idA, fixo: true }, { usuario_id: idB, vitalicio: false, inicio: iso(-1), fim: iso(30) }],
    })).statusCode, 200);
    assert.equal(await noMenuA(), true);

    // (os modulos de fabrica com tela entram no menu pelo cadastro; aqui so interessa o modulo criado no teste)
    const COM_TELA = ['painel', 'financas', 'saude', 'agenda'];
    const menu = async (t) => (await get('/meus-modulos', t)).json().itens.map((m) => m.codigo).filter((c) => !COM_TELA.includes(c));
    assert.deepEqual(await menu(ta), ['academia_treino']);
    assert.deepEqual(await menu(tb), ['academia_treino']);
    assert.deepEqual(await menu(tc), []); // nao liberado
    assert.deepEqual(await menu(token), ['academia_treino']); // SuperUsuario ve todos

    // nao-super nao gerencia modulos
    assert.equal((await com('PUT', '/modulos/academia_treino', ta, { nome: 'X' })).statusCode, 403);

    // validacoes: sem datas, fim antes do inicio, usuario repetido ou inexistente
    const put = (liberacoes) => com('PUT', '/modulos/academia_treino', token, { liberacoes });
    assert.equal((await put([{ usuario_id: idA, vitalicio: false }])).statusCode, 400);
    assert.equal((await put([{ usuario_id: idA, vitalicio: false, inicio: iso(5), fim: iso(1) }])).statusCode, 400);
    assert.equal((await put([{ usuario_id: idA }, { usuario_id: idA }])).statusCode, 400);
    assert.equal((await put([{ usuario_id: '00000000-0000-0000-0000-000000000000' }])).statusCode, 400);

    // validade vencida: o usuario perde o acesso; vitalicio ignora as datas
    assert.equal((await put([
      { usuario_id: idA, vitalicio: false, inicio: iso(-10), fim: iso(-1) },
      { usuario_id: idB, vitalicio: true, inicio: iso(-10), fim: iso(-1) },
      { usuario_id: idC, vitalicio: false, inicio: iso(1), fim: iso(10) },
    ])).statusCode, 200);
    assert.deepEqual(await menu(ta), []); // venceu
    assert.deepEqual(await menu(tb), ['academia_treino']); // vitalicio
    assert.deepEqual(await menu(tc), []); // ainda nao comecou
    const det = (await com('GET', '/modulos/academia_treino', token)).json();
    assert.equal(det.liberacoes.find((l) => l.usuario_id === idA).vigente, false);
    assert.equal(det.liberacoes.find((l) => l.usuario_id === idB).vigente, true);

    // desativar a liberacao de um usuario (continua cadastrada)
    assert.equal((await put([{ usuario_id: idB, ativa: false }, { usuario_id: idC }])).statusCode, 200);
    assert.deepEqual(await menu(tb), []);
    assert.deepEqual(await menu(tc), ['academia_treino']);
    assert.equal((await com('GET', '/modulos/academia_treino', token)).json().liberacoes.length, 2);

    // o SuperUsuario decide quais modulos fazem parte do pacote: valem para todos, sem liberacao
    assert.equal((await com('PUT', '/modulos/academia_treino', token, { no_pacote: true })).json().no_pacote, true);
    assert.deepEqual(await menu(tc), ['academia_treino']);
    const idD = await cadastrar('lib-d@exemplo.com');
    assert.deepEqual(await menu(await entrar('lib-d@exemplo.com')), ['academia_treino']);
    assert.ok(idD);
    assert.equal((await com('PUT', '/modulos/academia_treino', token, { no_pacote: false })).json().no_pacote, false);
    assert.deepEqual(await menu(await entrar('lib-d@exemplo.com')), []);
    // modulos de fabrica: nada e fixo por padrao, e o menu obedece ao cadastro (fixo, plano ou usuario)
    const lista0 = (await com('GET', '/modulos', token)).json().itens;
    const saude0 = lista0.find((m) => m.codigo === 'saude');
    assert.equal(lista0.find((m) => m.codigo === 'financas').no_pacote, false);
    assert.equal(saude0.no_pacote, false);
    const noMenu = async (t, c) => (await get('/meus-modulos', t)).json().itens.some((m) => m.codigo === c);
    const tD = await entrar('lib-d@exemplo.com');
    assert.equal((await com('PUT', '/modulos/saude', token, { planos: [], no_pacote: false })).statusCode, 200);
    assert.equal(await noMenu(tD, 'saude'), false); // sem plano e sem ser fixo
    assert.equal(await noMenu(token, 'saude'), true); // SuperUsuario ve todos
    assert.equal((await com('PUT', '/modulos/saude', token, { no_pacote: true })).json().no_pacote, true);
    assert.equal(await noMenu(tD, 'saude'), true); // fixo para todos os usuarios
    assert.equal((await com('PUT', '/modulos/saude', token, { no_pacote: false, planos: saude0.planos })).statusCode, 200);

    // modulo inativo some do menu de todos
    await com('PUT', '/modulos/academia_treino', token, { ativo: false });
    assert.deepEqual(await menu(tc), []);
    await com('PUT', '/modulos/academia_treino', token, { ativo: true });

    // modulos de fabrica nao se excluem nem se desativam, mas o nome pode mudar
    assert.equal((await com('DELETE', '/modulos/financas', token)).json().erro, 'modulo_de_sistema');
    assert.equal((await com('PUT', '/modulos/financas', token, { ativo: false })).json().erro, 'modulo_de_sistema');
    assert.equal((await com('PUT', '/modulos/financas', token, { descricao: 'Dinheiro' })).statusCode, 200);

    assert.equal((await com('DELETE', '/modulos/academia_treino', token)).statusCode, 204);
    assert.equal((await com('GET', '/modulos/academia_treino', token)).statusCode, 404);
    const lista = (await com('GET', '/modulos', token)).json().itens;
    assert.ok(lista.some((m) => m.codigo === 'financas' && m.sistema === true));
    assert.ok([idA, idB, idC].every(Boolean));
  });

  it('usuario comum nao cadastra modulos e ve apenas o proprio menu', async () => {
    await cadastrar('semperm@exemplo.com');
    const token = await entrar('semperm@exemplo.com');
    assert.equal((await com('POST', '/modulos', token, { nome: 'Teste' })).statusCode, 403);
    assert.equal((await com('GET', '/modulos', token)).statusCode, 403);
    assert.equal((await get('/meus-modulos', token)).statusCode, 200);
  });
});

describe('isolamento por usuario', () => {
  const com = (method, url, token, payload) => app.inject({ method, url, payload, headers: { authorization: `Bearer ${token}` } });

  it('administrador comum so alcanca quem ele cadastrou; SuperUsuario ve todos', async () => {
    const adminA = await cadastrar('adm-a@exemplo.com');
    await promover(pool, 'adm-a@exemplo.com');
    await cadastrar('adm-b@exemplo.com');
    await promover(pool, 'adm-b@exemplo.com');
    const tokenA = await entrar('adm-a@exemplo.com');
    const tokenB = await entrar('adm-b@exemplo.com');
    const sup = await criarSuperusuario(pool, { email: 'super-iso@exemplo.com', senha: 'senha-iso-1234' });
    const tokenS = await entrar('super-iso@exemplo.com', 'senha-iso-1234');
    assert.equal((await get('/me', tokenS)).json().superusuario, true);
    assert.equal((await get('/me', tokenA)).json().superusuario, false);

    const novo = await com('POST', '/usuarios', tokenA, { nome: 'Filho de A', email: 'filho-a@exemplo.com', senha: SENHA, ...pessoa() });
    assert.equal(novo.statusCode, 201, novo.body);
    const filho = novo.json().id ?? novo.json().usuario?.id;

    const listaA = (await com('GET', '/usuarios?limite=100', tokenA)).json();
    const emailsA = listaA.itens.map((u) => u.email);
    assert.ok(emailsA.includes('filho-a@exemplo.com') && emailsA.includes('adm-a@exemplo.com'));
    assert.ok(!emailsA.includes('adm-b@exemplo.com') && !emailsA.includes('super-iso@exemplo.com'));
    assert.equal(listaA.total, listaA.itens.length);

    assert.equal((await com('GET', `/usuarios/${filho}`, tokenB)).statusCode, 404);
    assert.equal((await com('PATCH', `/usuarios/${filho}`, tokenB, { nome: 'X' })).statusCode, 404);
    assert.equal((await com('DELETE', `/usuarios/${filho}`, tokenB)).statusCode, 404);
    assert.equal((await com('GET', `/usuarios/${filho}`, tokenA)).statusCode, 200);
    assert.equal((await com('GET', `/usuarios/${adminA}`, tokenA)).statusCode, 200);
    assert.equal((await com('GET', `/usuarios/${adminA}`, tokenB)).statusCode, 404);

    const emailsS = (await com('GET', '/usuarios?limite=100', tokenS)).json().itens.map((u) => u.email);
    assert.ok(emailsS.includes('filho-a@exemplo.com') && emailsS.includes('adm-b@exemplo.com'));
    assert.equal((await com('GET', `/usuarios/${filho}`, tokenS)).statusCode, 200);
    assert.ok(sup.id);

    // grupos: quem nao e SuperUsuario so enxerga os membros do proprio escopo
    const idB = (await get('/me', tokenB)).json().usuario.id;
    const g = await com('POST', '/grupos', tokenS, { nome: 'Grupo isolamento', perfis: [], membros: [filho, idB, adminA] });
    assert.equal(g.statusCode, 201, g.body);
    const gid = g.json().id;
    const visto = (await com('GET', `/grupos/${gid}`, tokenA)).json();
    assert.deepEqual(visto.membros.map((m) => m.email).sort(), ['adm-a@exemplo.com', 'filho-a@exemplo.com']);
    const lista = (await com('GET', '/grupos', tokenA)).json().itens.find((x) => x.id === gid);
    assert.equal(lista.total_membros, 2);
    assert.equal((await com('GET', `/grupos/${gid}`, tokenS)).json().membros.length, 3);

    // catalogo e ficha mostram so modulos de fabrica; perfis/grupos so o SuperUsuario altera
    assert.equal((await com('POST', '/perfis', tokenA, { nome: 'Meu perfil', permissoes: [] })).statusCode, 403);
    assert.equal((await com('GET', '/modulos', tokenA)).statusCode, 403);
  });
});

describe('preferencias de aparencia', () => {
  it('cada usuario guarda o proprio padrao e valida os valores', async () => {
    await cadastrar('pref-a@exemplo.com');
    await cadastrar('pref-b@exemplo.com');
    const ta = await entrar('pref-a@exemplo.com');
    const tb = await entrar('pref-b@exemplo.com');
    const put = (token, payload) => app.inject({ method: 'PUT', url: '/me/preferencias', payload, headers: { authorization: `Bearer ${token}` } });
    assert.deepEqual((await get('/me', ta)).json().preferencias, {});
    const ok = await put(ta, { modo: 'claro', escala: 1.15, cor: 'verde' });
    assert.equal(ok.statusCode, 200, ok.body);
    assert.deepEqual((await get('/me', ta)).json().preferencias, { modo: 'claro', escala: 1.15, cor: 'verde' });
    assert.deepEqual((await get('/me', tb)).json().preferencias, {});
    assert.equal((await put(ta, { modo: 'rosa', escala: 1, cor: 'verde' })).statusCode, 400);
    assert.equal((await put(ta, { modo: 'claro', escala: 5, cor: 'verde' })).statusCode, 400);
    assert.equal((await put(ta, { modo: 'claro', escala: 1, cor: 'marrom' })).statusCode, 400);
  });
});

describe('PATCH /me/senha (alterar a propria senha)', () => {
  const trocar = (token, corpo) => app.inject({ method: 'PATCH', url: '/me/senha',
    headers: token ? { authorization: `Bearer ${token}` } : {}, payload: corpo });

  it('exige login, a senha atual certa e uma nova diferente de 8+ caracteres', async () => {
    const email = 'trocasenha@exemplo.com';
    await cadastrar(email);
    const token = await entrar(email);
    assert.equal((await trocar(null, { senha_atual: SENHA, senha_nova: 'outra-senha-1' })).statusCode, 401);
    const errada = await trocar(token, { senha_atual: 'errada-errada', senha_nova: 'outra-senha-1' });
    assert.equal(errada.statusCode, 400);
    assert.equal(errada.json().erro, 'senha_atual_incorreta');
    assert.equal((await trocar(token, { senha_atual: SENHA, senha_nova: SENHA })).json().erro, 'senha_nova_igual');
    assert.equal((await trocar(token, { senha_atual: SENHA, senha_nova: 'curta' })).statusCode, 400);
  });

  it('troca a senha: a nova entra, a antiga nao, e os dados continuam', async () => {
    const email = 'trocasenha2@exemplo.com';
    await cadastrar(email);
    const token = await entrar(email);
    const antes = (await get('/me', token)).json().usuario;
    const r = await trocar(token, { senha_atual: SENHA, senha_nova: 'outra-senha-1' });
    assert.equal(r.statusCode, 204, r.body);
    assert.equal((await post('/login', { email, senha: SENHA })).statusCode, 401);
    assert.equal((await post('/login', { email, senha: 'outra-senha-1' })).statusCode, 200);
    const depois = (await get('/me', await entrar(email, 'outra-senha-1'))).json().usuario;
    assert.deepEqual(depois, antes);
  });
});
