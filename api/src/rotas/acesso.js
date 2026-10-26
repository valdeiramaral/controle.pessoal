import { comUsuario } from '../db.js';

// Perfis, grupos e catalogo de permissoes (modulo "acesso").
// Cada rota confere a permissao ANTES de ligar o modo administrador do banco.
const paramId = { type: 'object', properties: { id: { type: 'string', format: 'uuid' } }, required: ['id'] };
const textoCodigo = { type: 'string', minLength: 1, maxLength: 120 };
const listaCodigos = { type: 'array', items: textoCodigo, maxItems: 300, uniqueItems: true };
const listaIds = { type: 'array', items: { type: 'string', format: 'uuid' }, maxItems: 500, uniqueItems: true };

/** "Gerente de Contas" -> "gerente_de_contas" */
export function codigoDoNome(nome) {
  return nome.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

export default async function rotasAcesso(app) {
  const { pool } = app;
  const admin = (req, fn) => comUsuario(pool, req.usuarioId, fn, { admin: true });

  const erroDoBanco = (e, reply) => {
    if (e.code === '23505' && /perfil/.test(e.constraint ?? '')) return reply.code(409).send({ erro: 'perfil_ja_existe' });
    if (e.code === '23505' && /grupo/.test(e.constraint ?? '')) return reply.code(409).send({ erro: 'grupo_ja_existe' });
    if (e.code === '23503') return reply.code(400).send({ erro: 'referencia_invalida', detalhe: e.detail ?? e.message });
    throw e;
  };

  // ------------------------------------------------------------ permissoes
  app.get('/permissoes', { preHandler: app.exigir('acesso.usuario.ver') }, async (req) => admin(req, async (c) => ({
    permissoes: (await c.query(
      `SELECT p.codigo, p.nome, p.modulo_codigo, m.nome AS modulo_nome
         FROM controle.permissao p JOIN controle.modulo m ON m.codigo = p.modulo_codigo
        ORDER BY m.ordem, p.codigo`)).rows,
  })));

  // ---------------------------------------------------------------- perfis
  app.get('/perfis', { preHandler: app.exigir('acesso.usuario.ver') }, async (req) => admin(req, async (c) => ({
    itens: (await c.query(
      `SELECT p.id, p.codigo, p.nome, p.descricao, p.sistema,
              (SELECT count(*)::int FROM controle.perfil_permissao x WHERE x.perfil_id = p.id) AS total_permissoes,
              (SELECT count(*)::int FROM controle.usuario_perfil x WHERE x.perfil_id = p.id) AS total_usuarios
         FROM controle.perfil p ORDER BY p.sistema DESC, p.nome`)).rows,
  })));

  async function detalhePerfil(c, id) {
    const p = (await c.query(
      'SELECT id, codigo, nome, descricao, sistema FROM controle.perfil WHERE id = $1', [id])).rows[0];
    if (!p) return null;
    p.permissoes = (await c.query(
      'SELECT permissao_codigo FROM controle.perfil_permissao WHERE perfil_id = $1 ORDER BY 1', [id]))
      .rows.map((r) => r.permissao_codigo);
    return p;
  }

  app.get('/perfis/:id', {
    preHandler: app.exigir('acesso.usuario.ver'), schema: { params: paramId },
  }, async (req, reply) => (await admin(req, (c) => detalhePerfil(c, req.params.id)))
    ?? reply.code(404).send({ erro: 'perfil_nao_encontrado' }));

  async function gravarPermissoes(c, perfilId, codigos) {
    await c.query('DELETE FROM controle.perfil_permissao WHERE perfil_id = $1', [perfilId]);
    if (codigos.length) {
      await c.query(
        'INSERT INTO controle.perfil_permissao (perfil_id, permissao_codigo) SELECT $1, unnest($2::text[])',
        [perfilId, codigos]);
    }
  }

  app.post('/perfis', {
    preHandler: app.exigir('acesso.perfil.gerenciar'),
    schema: {
      body: {
        type: 'object', required: ['nome'], additionalProperties: false,
        properties: {
          nome: { type: 'string', minLength: 1, maxLength: 80 },
          descricao: { type: ['string', 'null'], maxLength: 300 },
          permissoes: listaCodigos,
        },
      },
    },
  }, async (req, reply) => {
    const { nome, descricao, permissoes = [] } = req.body;
    const codigo = codigoDoNome(nome);
    if (!codigo) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'nome', detalhe: 'Nome inválido.' });
    try {
      const r = await admin(req, async (c) => {
        const id = (await c.query(
          'INSERT INTO controle.perfil (codigo, nome, descricao) VALUES ($1, $2, $3) RETURNING id',
          [codigo, nome.trim(), descricao ?? null])).rows[0].id;
        await gravarPermissoes(c, id, permissoes);
        return detalhePerfil(c, id);
      });
      return reply.code(201).send(r);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.put('/perfis/:id', {
    preHandler: app.exigir('acesso.perfil.gerenciar'),
    schema: {
      params: paramId,
      body: {
        type: 'object', additionalProperties: false, minProperties: 1,
        properties: {
          nome: { type: 'string', minLength: 1, maxLength: 80 },
          descricao: { type: ['string', 'null'], maxLength: 300 },
          permissoes: listaCodigos,
        },
      },
    },
  }, async (req, reply) => {
    try {
      const r = await admin(req, async (c) => {
        const atual = await detalhePerfil(c, req.params.id);
        if (!atual) return { codigo404: true };
        // O perfil administrador e fixo: mexer nele poderia trancar todo mundo para fora.
        if (atual.codigo === 'administrador' && req.body.permissoes !== undefined) return { fixo: true };
        if (req.body.nome !== undefined || req.body.descricao !== undefined) {
          await c.query(
            'UPDATE controle.perfil SET nome = coalesce($2, nome), descricao = CASE WHEN $4 THEN $3 ELSE descricao END WHERE id = $1',
            [req.params.id, req.body.nome?.trim() ?? null, req.body.descricao ?? null, 'descricao' in req.body]);
        }
        if (req.body.permissoes !== undefined) await gravarPermissoes(c, req.params.id, req.body.permissoes);
        return { perfil: await detalhePerfil(c, req.params.id) };
      });
      if (r.codigo404) return reply.code(404).send({ erro: 'perfil_nao_encontrado' });
      if (r.fixo) return reply.code(400).send({ erro: 'perfil_administrador_fixo' });
      return r.perfil;
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.delete('/perfis/:id', {
    preHandler: app.exigir('acesso.perfil.gerenciar'), schema: { params: paramId },
  }, async (req, reply) => {
    const r = await admin(req, async (c) => {
      const p = (await c.query('SELECT sistema FROM controle.perfil WHERE id = $1', [req.params.id])).rows[0];
      if (!p) return { nao: 404 };
      if (p.sistema) return { nao: 400 };
      const uso = (await c.query(
        `SELECT (SELECT count(*)::int FROM controle.usuario_perfil WHERE perfil_id = $1) AS usuarios,
                (SELECT count(*)::int FROM controle.grupo_perfil WHERE perfil_id = $1) AS grupos`,
        [req.params.id])).rows[0];
      if (uso.usuarios || uso.grupos) return { nao: 409, uso };
      await c.query('DELETE FROM controle.perfil WHERE id = $1', [req.params.id]);
      return { ok: true };
    });
    if (r.nao === 404) return reply.code(404).send({ erro: 'perfil_nao_encontrado' });
    if (r.nao === 400) return reply.code(400).send({ erro: 'perfil_de_sistema' });
    if (r.nao === 409) return reply.code(409).send({ erro: 'perfil_em_uso', ...r.uso });
    return reply.code(204).send();
  });

  // ---------------------------------------------------------------- grupos
  app.get('/grupos', { preHandler: app.exigir('acesso.usuario.ver') }, async (req) => admin(req, async (c) => ({
    itens: (await c.query(
      `SELECT g.id, g.nome, g.descricao,
              (SELECT count(*)::int FROM controle.usuario_grupo x WHERE x.grupo_id = g.id) AS total_membros,
              coalesce((SELECT array_agg(p.codigo ORDER BY p.codigo)
                          FROM controle.grupo_perfil gp JOIN controle.perfil p ON p.id = gp.perfil_id
                         WHERE gp.grupo_id = g.id), '{}') AS perfis
         FROM controle.grupo g ORDER BY g.nome`)).rows,
  })));

  async function detalheGrupo(c, id) {
    const g = (await c.query('SELECT id, nome, descricao FROM controle.grupo WHERE id = $1', [id])).rows[0];
    if (!g) return null;
    g.perfis = (await c.query(
      `SELECT p.codigo FROM controle.grupo_perfil gp JOIN controle.perfil p ON p.id = gp.perfil_id
        WHERE gp.grupo_id = $1 ORDER BY 1`, [id])).rows.map((r) => r.codigo);
    g.membros = (await c.query(
      `SELECT u.id, u.nome, u.email FROM controle.usuario_grupo ug JOIN controle.usuario u ON u.id = ug.usuario_id
        WHERE ug.grupo_id = $1 AND u.excluido_em IS NULL ORDER BY u.nome`, [id])).rows;
    return g;
  }

  app.get('/grupos/:id', {
    preHandler: app.exigir('acesso.usuario.ver'), schema: { params: paramId },
  }, async (req, reply) => (await admin(req, (c) => detalheGrupo(c, req.params.id)))
    ?? reply.code(404).send({ erro: 'grupo_nao_encontrado' }));

  async function gravarPerfisDoGrupo(c, grupoId, codigos) {
    const achados = (await c.query('SELECT id FROM controle.perfil WHERE codigo = ANY($1)', [codigos])).rows;
    if (achados.length !== codigos.length) {
      const e = new Error('perfil inexistente'); e.code = '23503'; e.detail = 'perfil inexistente'; throw e;
    }
    await c.query('DELETE FROM controle.grupo_perfil WHERE grupo_id = $1', [grupoId]);
    for (const p of achados) {
      await c.query('INSERT INTO controle.grupo_perfil (grupo_id, perfil_id) VALUES ($1, $2)', [grupoId, p.id]);
    }
  }

  async function gravarMembros(c, grupoId, ids) {
    await c.query('DELETE FROM controle.usuario_grupo WHERE grupo_id = $1', [grupoId]);
    if (ids.length) {
      await c.query(
        'INSERT INTO controle.usuario_grupo (grupo_id, usuario_id) SELECT $1, unnest($2::uuid[])', [grupoId, ids]);
    }
  }

  const corpoGrupo = (obrigatorio) => ({
    type: 'object', additionalProperties: false, minProperties: 1,
    ...(obrigatorio ? { required: ['nome'] } : {}),
    properties: {
      nome: { type: 'string', minLength: 1, maxLength: 80 },
      descricao: { type: ['string', 'null'], maxLength: 300 },
      perfis: { type: 'array', items: { type: 'string', maxLength: 60 }, maxItems: 30, uniqueItems: true },
      membros: listaIds,
    },
  });

  app.post('/grupos', {
    preHandler: app.exigir('acesso.grupo.gerenciar'), schema: { body: corpoGrupo(true) },
  }, async (req, reply) => {
    const { nome, descricao, perfis = [], membros = [] } = req.body;
    try {
      const r = await admin(req, async (c) => {
        const id = (await c.query(
          'INSERT INTO controle.grupo (nome, descricao) VALUES ($1, $2) RETURNING id',
          [nome.trim(), descricao ?? null])).rows[0].id;
        await gravarPerfisDoGrupo(c, id, perfis);
        await gravarMembros(c, id, membros);
        return detalheGrupo(c, id);
      });
      return reply.code(201).send(r);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.put('/grupos/:id', {
    preHandler: app.exigir('acesso.grupo.gerenciar'), schema: { params: paramId, body: corpoGrupo(false) },
  }, async (req, reply) => {
    try {
      const r = await admin(req, async (c) => {
        if (!(await c.query('SELECT 1 FROM controle.grupo WHERE id = $1', [req.params.id])).rowCount) return null;
        if (req.body.nome !== undefined || 'descricao' in req.body) {
          await c.query(
            'UPDATE controle.grupo SET nome = coalesce($2, nome), descricao = CASE WHEN $4 THEN $3 ELSE descricao END WHERE id = $1',
            [req.params.id, req.body.nome?.trim() ?? null, req.body.descricao ?? null, 'descricao' in req.body]);
        }
        if (req.body.perfis !== undefined) await gravarPerfisDoGrupo(c, req.params.id, req.body.perfis);
        if (req.body.membros !== undefined) await gravarMembros(c, req.params.id, req.body.membros);
        return detalheGrupo(c, req.params.id);
      });
      return r ?? reply.code(404).send({ erro: 'grupo_nao_encontrado' });
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.delete('/grupos/:id', {
    preHandler: app.exigir('acesso.grupo.gerenciar'), schema: { params: paramId },
  }, async (req, reply) => {
    const r = await admin(req, (c) => c.query('DELETE FROM controle.grupo WHERE id = $1', [req.params.id]));
    return r.rowCount ? reply.code(204).send() : reply.code(404).send({ erro: 'grupo_nao_encontrado' });
  });
}
