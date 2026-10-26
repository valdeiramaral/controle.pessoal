import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { comUsuario } from './db.js';
import { lerToken } from './seguranca.js';
import rotasAuth from './rotas/auth.js';
import rotasUsuarios from './rotas/usuarios.js';
import rotasAcesso from './rotas/acesso.js';
import { ErroDado } from './pessoa.js';

export async function criarApp({ pool, config, logger = false }) {
  const app = Fastify({
    logger: logger ? { level: 'info', redact: ['req.headers.authorization'] } : false,
    bodyLimit: 16 * 1024,
    // Campo desconhecido no corpo vira erro 400 (o padrao do Fastify e ignora-lo em silencio).
    ajv: { customOptions: { removeAdditional: false } },
  });

  await app.register(rateLimit, { global: false });

  // CORS: deixa o app web (navegador) chamar a API. Libera so localhost/127.0.0.1
  // (qualquer porta) e as origens listadas em API_CORS_ORIGENS.
  const origemLocal = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;
  const extras = new Set(config.corsOrigens ?? []);
  app.addHook('onRequest', async (req, reply) => {
    const origem = req.headers.origin;
    if (!origem || !(origemLocal.test(origem) || extras.has(origem))) return;
    reply.header('access-control-allow-origin', origem);
    reply.header('vary', 'Origin');
    if (req.method === 'OPTIONS') {
      reply.header('access-control-allow-methods', 'GET, POST, PATCH, OPTIONS');
      reply.header('access-control-allow-headers', 'authorization, content-type');
      reply.header('access-control-max-age', '600');
      return reply.code(204).send();
    }
  });

  app.setErrorHandler((erro, req, reply) => {
    if (erro instanceof ErroDado) {
      return reply.code(400).send({ erro: 'dados_invalidos', campo: erro.campo, detalhe: erro.detalhe });
    }
    if (erro.validation) {
      return reply.code(400).send({ erro: 'dados_invalidos', detalhe: erro.message });
    }
    if (erro.statusCode && erro.statusCode < 500) {
      return reply.code(erro.statusCode).send({ erro: 'requisicao_invalida', detalhe: erro.message });
    }
    req.log.error(erro);
    return reply.code(500).send({ erro: 'erro_interno' });
  });

  app.decorate('pool', pool);
  app.decorate('config', config);

  // Confere o token e se a conta continua ativa (desativar um usuario vale na hora).
  app.decorate('autenticar', async (req, reply) => {
    const m = /^Bearer (.+)$/.exec(req.headers.authorization ?? '');
    if (!m) return reply.code(401).send({ erro: 'nao_autenticado' });
    let id;
    try { id = await lerToken(config, m[1]); } catch {
      return reply.code(401).send({ erro: 'nao_autenticado' });
    }
    const u = await comUsuario(pool, id, async (c) =>
      (await c.query(
        'SELECT ativo FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [id])).rows[0]);
    if (!u?.ativo) return reply.code(401).send({ erro: 'nao_autenticado' });
    req.usuarioId = id;
  });

  // Exige uma permissao (modulo.objeto.acao) calculada pelo banco.
  app.decorate('exigir', (codigo) => async (req, reply) => {
    await app.autenticar(req, reply);
    if (reply.sent) return reply;
    const r = await pool.query(
      'SELECT 1 FROM controle.permissoes_do_usuario($1) AS p(codigo) WHERE p.codigo = $2',
      [req.usuarioId, codigo]);
    if (!r.rowCount) return reply.code(403).send({ erro: 'sem_permissao', permissao: codigo });
  });

  // Confere uma permissao sem responder a requisicao (para rotas com varias acoes).
  app.decorate('temPermissao', async (usuarioId, codigo) => {
    const r = await pool.query(
      'SELECT 1 FROM controle.permissoes_do_usuario($1) AS p(codigo) WHERE p.codigo = $2',
      [usuarioId, codigo]);
    return r.rowCount > 0;
  });

  app.get('/saude', async () => {
    await pool.query('SELECT 1');
    return { ok: true };
  });

  await app.register(rotasAuth);
  await app.register(rotasUsuarios);
  await app.register(rotasAcesso);
  return app;
}
