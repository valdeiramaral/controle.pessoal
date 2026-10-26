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

async function cadastrar(email, extra = {}) {
  const r = await post('/cadastro', { nome: 'Pessoa Teste', email, senha: SENHA, ...extra });
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
    const r = await post('/cadastro', { nome: 'X', email: 'ANA@exemplo.com', senha: SENHA });
    assert.equal(r.statusCode, 409);
    assert.equal(r.json().erro, 'email_ja_cadastrado');
  });

  it('recusa e-mail invalido, senha curta, nome vazio e campo desconhecido', async () => {
    const base = { nome: 'X', email: 'x@exemplo.com', senha: SENHA };
    assert.equal((await post('/cadastro', { ...base, email: 'sem-arroba' })).json().erro, 'email_invalido');
    assert.equal((await post('/cadastro', { ...base, senha: '1234567' })).statusCode, 400);
    assert.equal((await post('/cadastro', { ...base, nome: '   ' })).statusCode, 400);
    assert.equal((await post('/cadastro', { ...base, admin: true })).statusCode, 400);
  });

  it('recusa pais inexistente', async () => {
    const r = await post('/cadastro', { nome: 'X', email: 'pais@exemplo.com', senha: SENHA, pais: 'ZZ' });
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

  it('promover avisa quando o usuario ou o perfil nao existem', async () => {
    await assert.rejects(() => promover(pool, 'nao-existe@exemplo.com'), /usuario nao encontrado/);
    await assert.rejects(() => promover(pool, 'ana@exemplo.com', 'perfil-falso'), /perfil nao encontrado/);
  });
});
