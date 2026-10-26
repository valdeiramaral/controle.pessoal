import { comUsuario } from '../db.js';

// Administracao de usuarios (modulo "acesso"). Cada rota confere a permissao
// ANTES de ligar o modo administrador do banco.
export default async function rotasUsuarios(app) {
  const { pool } = app;

  app.get('/usuarios', {
    preHandler: app.exigir('acesso.usuario.ver'),
    schema: {
      querystring: {
        type: 'object',
        properties: {
          limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
          pagina: { type: 'integer', minimum: 1, default: 1 },
        },
      },
    },
  }, async (req) => {
    const { limite, pagina } = req.query;
    return comUsuario(pool, req.usuarioId, async (c) => {
      const total = (await c.query('SELECT count(*)::int AS n FROM controle.usuario WHERE excluido_em IS NULL')).rows[0].n;
      const itens = (await c.query(
        `SELECT id, nome, email, pais, idioma, ativo, criado_em, ultimo_login_em
           FROM controle.usuario WHERE excluido_em IS NULL
          ORDER BY nome, id LIMIT $1 OFFSET $2`, [limite, (pagina - 1) * limite])).rows;
      return { total, pagina, itens };
    }, { admin: true });
  });

  app.patch('/usuarios/:id', {
    preHandler: app.exigir('acesso.usuario.editar'),
    schema: {
      params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } }, required: ['id'] },
      body: {
        type: 'object', required: ['ativo'], additionalProperties: false,
        properties: { ativo: { type: 'boolean' } },
      },
    },
  }, async (req, reply) => {
    const { id } = req.params;
    if (id === req.usuarioId && req.body.ativo === false) {
      return reply.code(400).send({ erro: 'nao_pode_desativar_a_si_mesmo' });
    }
    const r = await comUsuario(pool, req.usuarioId, (c) => c.query(
      `UPDATE controle.usuario SET ativo = $2
        WHERE id = $1 AND excluido_em IS NULL RETURNING id, nome, email, ativo`,
      [id, req.body.ativo]), { admin: true });
    if (!r.rowCount) return reply.code(404).send({ erro: 'usuario_nao_encontrado' });
    return r.rows[0];
  });
}
