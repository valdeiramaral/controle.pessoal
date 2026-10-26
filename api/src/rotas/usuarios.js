import { comUsuario } from '../db.js';
import { gerarHash } from '../seguranca.js';
import {
  COLUNAS_USUARIO, colunasDaPessoa, enderecoJson, esquemaDadosPessoais, montarSet, serializarUsuario,
} from '../pessoa.js';

// Administracao de usuarios (modulo "acesso"). Cada rota confere a permissao
// ANTES de ligar o modo administrador do banco.
const paramId = { type: 'object', properties: { id: { type: 'string', format: 'uuid' } }, required: ['id'] };
const normalizarEmail = (e) => e.trim().toLowerCase();

export default async function rotasUsuarios(app) {
  const { pool } = app;

  const naoEncontrado = (reply) => reply.code(404).send({ erro: 'usuario_nao_encontrado' });

  // Traduz erros de unicidade/validacao do banco em respostas claras.
  const erroDoBanco = (e, reply) => {
    if (e.code === '23505' && e.constraint === 'ux_usuario_cpf') return reply.code(409).send({ erro: 'cpf_ja_cadastrado' });
    if (e.code === '23505') return reply.code(409).send({ erro: 'email_ja_cadastrado' });
    if (e.constraint === 'ck_usuario_email') return reply.code(400).send({ erro: 'email_invalido' });
    if (e.code === '23503') return reply.code(400).send({ erro: 'referencia_invalida', detalhe: e.detail ?? e.message });
    if (e.code === 'P0001') return reply.code(400).send({ erro: 'dados_invalidos', detalhe: e.message });
    throw e;
  };

  // ------------------------------------------------------------- catalogo
  // Planos, modulos e perfis para montar as telas de cadastro/edicao.
  app.get('/catalogo', { preHandler: app.exigir('acesso.usuario.ver') }, async (req) => {
    return comUsuario(pool, req.usuarioId, async (c) => ({
      planos: (await c.query(
        'SELECT codigo, nome, periodo FROM controle.plano WHERE ativo ORDER BY duracao_meses NULLS FIRST, codigo')).rows,
      modulos: (await c.query(
        `SELECT codigo, nome, descricao, liberado_para_todos
           FROM controle.modulo WHERE ativo ORDER BY ordem`)).rows,
      perfis: (await c.query('SELECT codigo, nome, descricao FROM controle.perfil ORDER BY nome')).rows,
    }));
  });

  // ---------------------------------------------------------------- lista
  app.get('/usuarios', {
    preHandler: app.exigir('acesso.usuario.ver'),
    schema: {
      querystring: {
        type: 'object',
        properties: {
          limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
          pagina: { type: 'integer', minimum: 1, default: 1 },
          busca: { type: 'string', maxLength: 100 },
        },
      },
    },
  }, async (req) => {
    const { limite, pagina, busca } = req.query;
    const filtro = busca?.trim()
      ? `AND (u.nome ILIKE $1 OR u.email ILIKE $1 OR u.cpf LIKE $2)` : '';
    const params = busca?.trim()
      ? [`%${busca.trim().replace(/[%_\\]/g, '\\$&')}%`, busca.replace(/\D/g, '') ? `${busca.replace(/\D/g, '')}%` : null] : [];
    return comUsuario(pool, req.usuarioId, async (c) => {
      const total = (await c.query(
        `SELECT count(*)::int AS n FROM controle.usuario u WHERE u.excluido_em IS NULL ${filtro}`, params)).rows[0].n;
      const itens = (await c.query(
        `SELECT u.id, u.nome, u.email, u.cpf, u.telefone, u.pais, u.idioma, u.ativo, u.criado_em, u.ultimo_login_em,
                (SELECT l.plano_codigo FROM controle.licenca l
                  WHERE l.usuario_id = u.id AND l.status = 'ativa'
                    AND l.inicio <= now() AND (l.fim IS NULL OR l.fim > now())
                  ORDER BY l.inicio DESC LIMIT 1) AS plano
           FROM controle.usuario u WHERE u.excluido_em IS NULL ${filtro}
          ORDER BY u.nome, u.id LIMIT ${Number(limite)} OFFSET ${(Number(pagina) - 1) * Number(limite)}`,
        params)).rows;
      return { total, pagina, itens };
    }, { admin: true });
  });

  // -------------------------------------------------------------- detalhe
  async function detalhe(c, id) {
    const u = (await c.query(
      `SELECT ${COLUNAS_USUARIO}, criado_em, ultimo_login_em FROM controle.usuario
        WHERE id = $1 AND excluido_em IS NULL`, [id])).rows[0];
    if (!u) return null;
    const licenca = (await c.query(
      `SELECT plano_codigo AS plano, status, origem, inicio, fim FROM controle.licenca
        WHERE usuario_id = $1 AND status = 'ativa' AND inicio <= now() AND (fim IS NULL OR fim > now())
        ORDER BY inicio DESC LIMIT 1`, [id])).rows[0] ?? null;
    const perfis = (await c.query(
      `SELECT p.codigo FROM controle.usuario_perfil up JOIN controle.perfil p ON p.id = up.perfil_id
        WHERE up.usuario_id = $1 ORDER BY p.codigo`, [id])).rows.map((r) => r.codigo);
    // liberacao: 'padrao' (vale o plano), 'liberado' ou 'bloqueado' (so para este usuario);
    // efetivo: o que o banco calcula de fato (modulo_liberado).
    const modulos = (await c.query(
      `SELECT m.codigo, m.nome, m.liberado_para_todos,
              CASE (SELECT l.concedida FROM controle.liberacao_modulo l
                     WHERE l.usuario_id = $1 AND l.modulo_codigo = m.codigo
                       AND (l.inicio IS NULL OR l.inicio <= now()) AND (l.fim IS NULL OR l.fim > now())
                     ORDER BY l.criado_em DESC LIMIT 1)
                WHEN true THEN 'liberado' WHEN false THEN 'bloqueado' ELSE 'padrao' END AS liberacao,
              controle.modulo_liberado($1, m.codigo) AS efetivo
         FROM controle.modulo m WHERE m.ativo ORDER BY m.ordem`, [id])).rows;
    const grupos = (await c.query(
      `SELECT g.id, g.nome FROM controle.usuario_grupo ug JOIN controle.grupo g ON g.id = ug.grupo_id
        WHERE ug.usuario_id = $1 ORDER BY g.nome`, [id])).rows;
    // excecoes individuais: { 'financas.conta.gerenciar': false, ... } (true concede, false nega)
    const excecoes = Object.fromEntries((await c.query(
      'SELECT permissao_codigo, concedida FROM controle.usuario_permissao WHERE usuario_id = $1', [id]))
      .rows.map((r) => [r.permissao_codigo, r.concedida]));
    const permissoes = (await c.query(
      'SELECT p FROM controle.permissoes_do_usuario($1) AS p', [id])).rows.map((r) => r.p);
    return { usuario: serializarUsuario(u), licenca, perfis, modulos, grupos, excecoes, permissoes };
  }

  app.get('/usuarios/:id', {
    preHandler: app.exigir('acesso.usuario.ver'),
    schema: { params: paramId },
  }, async (req, reply) => {
    const r = await comUsuario(pool, req.usuarioId, (c) => detalhe(c, req.params.id), { admin: true });
    return r ?? naoEncontrado(reply);
  });

  // ------------------------------------------------- rotinas de gravacao
  async function trocarPlano(c, id, plano, fim) {
    await c.query(
      `UPDATE controle.licenca SET status = 'cancelada',
              fim = greatest(inicio + interval '1 microsecond', least(coalesce(fim, now()), now()))
        WHERE usuario_id = $1 AND status = 'ativa'`, [id]);
    await c.query(
      `INSERT INTO controle.licenca (usuario_id, plano_codigo, status, origem, fim)
       VALUES ($1, $2, 'ativa', $3, $4)`,
      [id, plano, plano === 'gratuito' ? 'gratuita' : 'cortesia', fim ?? null]);
  }

  async function definirModulos(c, id, mapa) {
    for (const [modulo, valor] of Object.entries(mapa)) {
      await c.query('DELETE FROM controle.liberacao_modulo WHERE usuario_id = $1 AND modulo_codigo = $2', [id, modulo]);
      if (valor === true || valor === false) {
        await c.query(
          'INSERT INTO controle.liberacao_modulo (modulo_codigo, usuario_id, concedida) VALUES ($1, $2, $3)',
          [modulo, id, valor]);
      }
    }
  }

  async function definirPerfis(c, id, codigos) {
    const achados = (await c.query('SELECT id, codigo FROM controle.perfil WHERE codigo = ANY($1)', [codigos])).rows;
    if (achados.length !== new Set(codigos).size) {
      const e = new Error('perfil inexistente'); e.code = '23503'; e.detail = 'perfil inexistente'; throw e;
    }
    await c.query('DELETE FROM controle.usuario_perfil WHERE usuario_id = $1', [id]);
    for (const p of achados) {
      await c.query('INSERT INTO controle.usuario_perfil (usuario_id, perfil_id) VALUES ($1, $2)', [id, p.id]);
    }
  }

  const esquemaModulos = {
    type: 'object',
    additionalProperties: { type: ['boolean', 'null'] }, // true libera, false bloqueia, null volta ao padrao do plano
  };
  const esquemaPerfis = { type: 'array', items: { type: 'string', maxLength: 60 }, minItems: 1, maxItems: 10 };
  const esquemaPlano = { type: 'string', minLength: 1, maxLength: 40 };

  // ------------------------------------------------------- novo usuario
  // O administrador cadastra a pessoa ja informando plano, perfis e modulos liberados.
  app.post('/usuarios', {
    preHandler: app.exigir('acesso.usuario.cadastrar'),
    schema: {
      body: {
        type: 'object',
        required: ['nome', 'email', 'senha', 'cpf', 'telefone'],
        additionalProperties: false,
        properties: {
          nome: { type: 'string', minLength: 1, maxLength: 120 },
          email: { type: 'string', minLength: 3, maxLength: 254 },
          senha: { type: 'string', minLength: 8, maxLength: 128 },
          ...esquemaDadosPessoais,
          plano: esquemaPlano,
          perfis: esquemaPerfis,
          modulos: esquemaModulos,
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    // Cada parte extra exige a sua propria permissao.
    const exigencias = [
      [b.plano !== undefined, 'licencas.licenca.conceder'],
      [b.perfis !== undefined, 'acesso.perfil.gerenciar'],
      [b.modulos !== undefined, 'administracao.liberacao.gerenciar'],
    ];
    for (const [pedido, perm] of exigencias) {
      if (pedido && !(await app.temPermissao(req.usuarioId, perm))) {
        return reply.code(403).send({ erro: 'sem_permissao', permissao: perm });
      }
    }
    const d = colunasDaPessoa(b);
    if (!d.cpf) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'cpf', detalhe: 'Informe o CPF.' });
    if (!d.telefone) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'telefone', detalhe: 'Informe o telefone.' });
    const senhaHash = await gerarHash(b.senha);
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const id = (await c.query(
          'SELECT controle.cadastrar_usuario($1, $2, $3, $4, $5, $6, $7, $8, $9) AS id',
          [d.nome, normalizarEmail(b.email), senhaHash, 'BR', null,
            d.cpf, d.telefone, d.data_nascimento ?? null, enderecoJson(d)])).rows[0].id;
        if (b.plano !== undefined) await trocarPlano(c, id, b.plano, null);
        if (b.perfis !== undefined) await definirPerfis(c, id, b.perfis);
        if (b.modulos !== undefined) await definirModulos(c, id, b.modulos);
        return detalhe(c, id);
      }, { admin: true });
      return reply.code(201).send(r);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // ------------------------------------------------- editar dados / ativo
  app.patch('/usuarios/:id', {
    preHandler: app.exigir('acesso.usuario.editar'),
    schema: {
      params: paramId,
      body: {
        type: 'object', additionalProperties: false, minProperties: 1,
        properties: {
          ativo: { type: 'boolean' },
          nome: { type: 'string', maxLength: 120 },
          email: { type: 'string', minLength: 3, maxLength: 254 },
          ...esquemaDadosPessoais,
        },
      },
    },
  }, async (req, reply) => {
    const { id } = req.params;
    const { ativo, email, ...pessoa } = req.body;
    if (id === req.usuarioId && ativo === false) {
      return reply.code(400).send({ erro: 'nao_pode_desativar_a_si_mesmo' });
    }
    const col = colunasDaPessoa(pessoa);
    if ('telefone' in col && !col.telefone) {
      return reply.code(400).send({ erro: 'dados_invalidos', campo: 'telefone', detalhe: 'Informe o telefone.' });
    }
    if (ativo !== undefined) col.ativo = ativo;
    if (email !== undefined) col.email = normalizarEmail(email);
    const { sql, valores } = montarSet(col);
    try {
      const r = await comUsuario(pool, req.usuarioId, (c) => c.query(
        `UPDATE controle.usuario SET ${sql} WHERE id = $1 AND excluido_em IS NULL
         RETURNING id, nome, email, ativo`, [id, ...valores]), { admin: true });
      if (!r.rowCount) return naoEncontrado(reply);
      return r.rows[0];
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // ---------------------------------------------------------------- plano
  app.put('/usuarios/:id/plano', {
    preHandler: app.exigir('licencas.licenca.conceder'),
    schema: {
      params: paramId,
      body: {
        type: 'object', required: ['plano'], additionalProperties: false,
        properties: { plano: esquemaPlano, fim: { type: ['string', 'null'], format: 'date-time' } },
      },
    },
  }, async (req, reply) => {
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const existe = (await c.query(
          'SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [req.params.id])).rowCount;
        if (!existe) return null;
        await trocarPlano(c, req.params.id, req.body.plano, req.body.fim);
        return detalhe(c, req.params.id);
      }, { admin: true });
      return r ?? naoEncontrado(reply);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // -------------------------------------------------------------- modulos
  app.put('/usuarios/:id/modulos', {
    preHandler: app.exigir('administracao.liberacao.gerenciar'),
    schema: {
      params: paramId,
      body: { type: 'object', required: ['modulos'], additionalProperties: false, properties: { modulos: esquemaModulos } },
    },
  }, async (req, reply) => {
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const existe = (await c.query(
          'SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [req.params.id])).rowCount;
        if (!existe) return null;
        await definirModulos(c, req.params.id, req.body.modulos);
        return detalhe(c, req.params.id);
      }, { admin: true });
      return r ?? naoEncontrado(reply);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // ------------------------------------------------------------- excluir
  // Exclusao logica: a conta some das listas e nao entra mais; e-mail e CPF ficam livres.
  app.delete('/usuarios/:id', {
    preHandler: app.exigir('acesso.usuario.editar'), schema: { params: paramId },
  }, async (req, reply) => {
    if (req.params.id === req.usuarioId) return reply.code(400).send({ erro: 'nao_pode_excluir_a_si_mesmo' });
    const r = await comUsuario(pool, req.usuarioId, (c) => c.query(
      `UPDATE controle.usuario SET excluido_em = now(), ativo = false
        WHERE id = $1 AND excluido_em IS NULL`, [req.params.id]), { admin: true });
    return r.rowCount ? reply.code(204).send() : naoEncontrado(reply);
  });

  // --------------------------------------------------------------- grupos
  app.put('/usuarios/:id/grupos', {
    preHandler: app.exigir('acesso.grupo.gerenciar'),
    schema: {
      params: paramId,
      body: {
        type: 'object', required: ['grupos'], additionalProperties: false,
        properties: { grupos: { type: 'array', items: { type: 'string', format: 'uuid' }, maxItems: 100, uniqueItems: true } },
      },
    },
  }, async (req, reply) => {
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const existe = (await c.query(
          'SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [req.params.id])).rowCount;
        if (!existe) return null;
        await c.query('DELETE FROM controle.usuario_grupo WHERE usuario_id = $1', [req.params.id]);
        if (req.body.grupos.length) {
          await c.query(
            'INSERT INTO controle.usuario_grupo (usuario_id, grupo_id) SELECT $1, unnest($2::uuid[])',
            [req.params.id, req.body.grupos]);
        }
        return detalhe(c, req.params.id);
      }, { admin: true });
      return r ?? naoEncontrado(reply);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // ------------------------------------------------- excecoes de permissao
  // true concede, false nega (a negacao vence), null remove a excecao.
  app.put('/usuarios/:id/permissoes', {
    preHandler: app.exigir('acesso.perfil.gerenciar'),
    schema: {
      params: paramId,
      body: {
        type: 'object', required: ['permissoes'], additionalProperties: false,
        properties: { permissoes: { type: 'object', additionalProperties: { type: ['boolean', 'null'] } } },
      },
    },
  }, async (req, reply) => {
    // Ninguem nega a si mesmo o acesso a administracao (evita se trancar para fora).
    if (req.params.id === req.usuarioId) {
      const trava = Object.entries(req.body.permissoes)
        .find(([cod, v]) => v === false && /^(acesso|administracao)\./.test(cod));
      if (trava) return reply.code(400).send({ erro: 'nao_pode_negar_a_si_mesmo', permissao: trava[0] });
    }
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const existe = (await c.query(
          'SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [req.params.id])).rowCount;
        if (!existe) return null;
        for (const [cod, valor] of Object.entries(req.body.permissoes)) {
          await c.query('DELETE FROM controle.usuario_permissao WHERE usuario_id = $1 AND permissao_codigo = $2',
            [req.params.id, cod]);
          if (valor === true || valor === false) {
            await c.query(
              'INSERT INTO controle.usuario_permissao (usuario_id, permissao_codigo, concedida) VALUES ($1, $2, $3)',
              [req.params.id, cod, valor]);
          }
        }
        return detalhe(c, req.params.id);
      }, { admin: true });
      return r ?? naoEncontrado(reply);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  // --------------------------------------------------------------- perfis
  app.put('/usuarios/:id/perfis', {
    preHandler: app.exigir('acesso.perfil.gerenciar'),
    schema: {
      params: paramId,
      body: { type: 'object', required: ['perfis'], additionalProperties: false, properties: { perfis: esquemaPerfis } },
    },
  }, async (req, reply) => {
    if (req.params.id === req.usuarioId && !req.body.perfis.includes('administrador')) {
      return reply.code(400).send({ erro: 'nao_pode_remover_o_proprio_perfil_administrador' });
    }
    try {
      const r = await comUsuario(pool, req.usuarioId, async (c) => {
        const existe = (await c.query(
          'SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [req.params.id])).rowCount;
        if (!existe) return null;
        await definirPerfis(c, req.params.id, req.body.perfis);
        return detalhe(c, req.params.id);
      }, { admin: true });
      return r ?? naoEncontrado(reply);
    } catch (e) { return erroDoBanco(e, reply); }
  });
}
