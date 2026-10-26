import { comUsuario } from '../db.js';
import { conferirSenha, emitirToken, gerarHash, hashFalso } from '../seguranca.js';

const limite = (app) => ({ rateLimit: { max: app.config.limiteAuth, timeWindow: '1 minute' } });
const normalizarEmail = (e) => e.trim().toLowerCase();

export default async function rotasAuth(app) {
  const { pool, config } = app;

  // ---------------------------------------------------------------- cadastro
  app.post('/cadastro', {
    config: limite(app),
    schema: {
      body: {
        type: 'object',
        required: ['nome', 'email', 'senha'],
        additionalProperties: false,
        properties: {
          nome: { type: 'string', minLength: 1, maxLength: 120 },
          email: { type: 'string', minLength: 3, maxLength: 254 },
          senha: { type: 'string', minLength: 8, maxLength: 128 },
          pais: { type: 'string', minLength: 2, maxLength: 2 },
          idioma: { type: 'string', minLength: 2, maxLength: 10 },
        },
      },
    },
  }, async (req, reply) => {
    const { nome, email, senha, pais, idioma } = req.body;
    if (!nome.trim()) return reply.code(400).send({ erro: 'dados_invalidos', detalhe: 'nome vazio' });
    const senhaHash = await gerarHash(senha);
    try {
      const r = await pool.query(
        'SELECT controle.cadastrar_usuario($1, $2, $3, $4, $5) AS id',
        [nome, normalizarEmail(email), senhaHash, pais ?? 'BR', idioma ?? null]);
      return reply.code(201).send({ id: r.rows[0].id });
    } catch (e) {
      if (e.code === '23505') return reply.code(409).send({ erro: 'email_ja_cadastrado' });
      if (e.constraint === 'ck_usuario_email') return reply.code(400).send({ erro: 'email_invalido' });
      if (e.code === 'P0001') return reply.code(400).send({ erro: 'dados_invalidos', detalhe: e.message });
      throw e;
    }
  });

  // ------------------------------------------------------------------ login
  app.post('/login', {
    config: limite(app),
    schema: {
      body: {
        type: 'object',
        required: ['email', 'senha'],
        additionalProperties: false,
        properties: {
          email: { type: 'string', minLength: 1, maxLength: 254 },
          senha: { type: 'string', minLength: 1, maxLength: 128 },
        },
      },
    },
  }, async (req, reply) => {
    const { email, senha } = req.body;
    const credenciaisInvalidas = () => reply.code(401).send({ erro: 'credenciais_invalidas' });

    const achou = await pool.query('SELECT * FROM controle.buscar_login($1)', [normalizarEmail(email)]);
    const u = achou.rows[0];

    // Conta inexistente: confere um hash falso para gastar o mesmo tempo.
    if (!u || !u.senha_hash) {
      await conferirSenha(await hashFalso(), senha);
      return credenciaisInvalidas();
    }

    // Conta bloqueada (5 erros seguidos): nao confere a senha nem conta nova tentativa.
    if (u.bloqueado_ate && new Date(u.bloqueado_ate) > new Date()) {
      return reply.code(423).send({ erro: 'conta_bloqueada', ate: new Date(u.bloqueado_ate).toISOString() });
    }

    const ok = await conferirSenha(u.senha_hash, senha);
    await pool.query('SELECT controle.registrar_login($1, $2)', [u.id, ok]);
    if (!ok) return credenciaisInvalidas();
    if (!u.ativo) return reply.code(403).send({ erro: 'conta_inativa' });

    const token = await emitirToken(config, u.id);
    return {
      token,
      expira_em_segundos: config.tokenExpiraSegundos,
      usuario: { id: u.id, nome: u.nome, idioma: u.idioma, pais: u.pais },
    };
  });

  // -------------------------------------------------------------------- /me
  app.get('/me', { preHandler: app.autenticar }, async (req) => {
    const id = req.usuarioId;
    return comUsuario(pool, id, async (c) => {
      const u = (await c.query(
        `SELECT id, nome, email, pais, idioma, fuso_horario, moeda_padrao, email_verificado_em
           FROM controle.usuario WHERE id = $1`, [id])).rows[0];
      const licenca = (await c.query(
        `SELECT plano_codigo AS plano, status, inicio, fim
           FROM controle.licenca
          WHERE usuario_id = $1 AND status = 'ativa' AND inicio <= now() AND (fim IS NULL OR fim > now())
          ORDER BY inicio DESC LIMIT 1`, [id])).rows[0] ?? null;
      const modulos = (await c.query('SELECT m FROM controle.modulos_do_usuario($1) AS m', [id])).rows.map((r) => r.m);
      const permissoes = (await c.query('SELECT p FROM controle.permissoes_do_usuario($1) AS p', [id])).rows.map((r) => r.p);
      const acesso = (await c.query('SELECT controle.tem_acesso($1) AS a', [id])).rows[0].a;
      return { usuario: u, licenca, acesso, modulos, permissoes };
    });
  });
}
