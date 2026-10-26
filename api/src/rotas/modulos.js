import { comUsuario } from '../db.js';
import { codigoDoNome } from './acesso.js';

// Cadastro de modulos (modulo "administracao") e a lista de modulos do menu.
// Modulos criados aqui tem exibir_no_menu = true; os de fabrica (financas, saude...) nao podem ser
// excluidos nem desativados.
export const ICONES = [
  'extension', 'folder', 'star', 'work', 'school', 'cart', 'home', 'fitness', 'pets',
  'flight', 'book', 'build', 'chart', 'people', 'wallet',
];

const paramCodigo = { type: 'object', properties: { codigo: { type: 'string', maxLength: 60 } }, required: ['codigo'] };
const listaPlanos = { type: 'array', items: { type: 'string', maxLength: 60 }, maxItems: 50, uniqueItems: true };
const propriedades = {
  nome: { type: 'string', minLength: 1, maxLength: 80 },
  descricao: { type: ['string', 'null'], maxLength: 300 },
  icone: { type: 'string', enum: ICONES },
  ordem: { type: 'integer', minimum: 1, maximum: 9999 },
  ativo: { type: 'boolean' },
  liberado_para_todos: { type: 'boolean' },
  planos: listaPlanos,
};

export default async function rotasModulos(app) {
  const { pool } = app;
  const admin = (req, fn) => comUsuario(pool, req.usuarioId, fn, { admin: true });
  const gerenciar = app.exigir('administracao.modulo.gerenciar');

  const SELECT = `
    SELECT m.codigo, m.nome, m.descricao, m.ordem, m.ativo, m.liberado_para_todos, m.icone,
           m.exibir_no_menu, NOT m.exibir_no_menu AS sistema,
           coalesce((SELECT array_agg(l.plano_codigo ORDER BY l.plano_codigo) FROM liberacao_modulo l
                      WHERE l.modulo_codigo = m.codigo AND l.plano_codigo IS NOT NULL AND l.concedida), '{}') AS planos
      FROM controle.modulo m`;

  const gravarPlanos = async (c, codigo, planos) => {
    await c.query('DELETE FROM controle.liberacao_modulo WHERE modulo_codigo = $1 AND plano_codigo IS NOT NULL', [codigo]);
    for (const p of planos) {
      await c.query('INSERT INTO controle.liberacao_modulo (modulo_codigo, plano_codigo) VALUES ($1, $2)', [codigo, p]);
    }
  };

  const erroDoBanco = (e, reply) => {
    if (e.code === '23505') return reply.code(409).send({ erro: 'modulo_ja_existe' });
    if (e.code === '23503') return reply.code(409).send({ erro: 'referencia_invalida', detalhe: e.detail ?? e.message });
    throw e;
  };

  // Lista para a tela de cadastro (todos, inclusive inativos).
  app.get('/modulos', { preHandler: gerenciar }, async (req) => admin(req, async (c) => ({
    itens: (await c.query(`${SELECT} ORDER BY m.ordem, m.codigo`)).rows,
  })));

  app.get('/modulos/:codigo', { preHandler: gerenciar, schema: { params: paramCodigo } }, async (req, reply) => {
    const m = (await admin(req, (c) => c.query(`${SELECT} WHERE m.codigo = $1`, [req.params.codigo]))).rows[0];
    return m ?? reply.code(404).send({ erro: 'modulo_nao_encontrado' });
  });

  app.post('/modulos', {
    preHandler: gerenciar,
    schema: { body: { type: 'object', required: ['nome'], additionalProperties: false, properties: propriedades } },
  }, async (req, reply) => {
    const b = req.body;
    const codigo = codigoDoNome(b.nome);
    if (!/^[a-z][a-z0-9_]{1,40}$/.test(codigo)) {
      return reply.code(400).send({ erro: 'dados_invalidos', campo: 'nome', detalhe: 'Use um nome com letras (ao menos 2).' });
    }
    try {
      const m = await admin(req, async (c) => {
        const ordem = b.ordem ?? ((await c.query('SELECT coalesce(max(ordem), 0) + 1 AS n FROM controle.modulo')).rows[0].n);
        await c.query(
          `INSERT INTO controle.modulo (codigo, nome, descricao, ordem, ativo, liberado_para_todos, icone, exibir_no_menu)
           VALUES ($1, $2, $3, $4, $5, $6, $7, true)`,
          [codigo, b.nome.trim(), b.descricao ?? null, ordem, b.ativo ?? true, b.liberado_para_todos ?? true,
            b.icone ?? 'extension']);
        await gravarPlanos(c, codigo, b.planos ?? []);
        return (await c.query(`${SELECT} WHERE m.codigo = $1`, [codigo])).rows[0];
      });
      return reply.code(201).send(m);
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.put('/modulos/:codigo', {
    preHandler: gerenciar,
    schema: { params: paramCodigo, body: { type: 'object', additionalProperties: false, minProperties: 1, properties: propriedades } },
  }, async (req, reply) => {
    const b = req.body;
    try {
      const r = await admin(req, async (c) => {
        const atual = (await c.query('SELECT exibir_no_menu FROM controle.modulo WHERE codigo = $1', [req.params.codigo])).rows[0];
        if (!atual) return { nao: 404 };
        if (!atual.exibir_no_menu && b.ativo === false) return { nao: 400 };
        const campos = [];
        const valores = [req.params.codigo];
        for (const k of ['nome', 'descricao', 'ordem', 'ativo', 'liberado_para_todos', 'icone']) {
          if (k in b) { valores.push(k === 'nome' ? b[k].trim() : b[k]); campos.push(`${k} = $${valores.length}`); }
        }
        if (campos.length) await c.query(`UPDATE controle.modulo SET ${campos.join(', ')} WHERE codigo = $1`, valores);
        if (b.planos !== undefined) await gravarPlanos(c, req.params.codigo, b.planos);
        return { m: (await c.query(`${SELECT} WHERE m.codigo = $1`, [req.params.codigo])).rows[0] };
      });
      if (r.nao === 404) return reply.code(404).send({ erro: 'modulo_nao_encontrado' });
      if (r.nao === 400) return reply.code(400).send({ erro: 'modulo_de_sistema' });
      return r.m;
    } catch (e) { return erroDoBanco(e, reply); }
  });

  app.delete('/modulos/:codigo', { preHandler: gerenciar, schema: { params: paramCodigo } }, async (req, reply) => {
    try {
      const r = await admin(req, async (c) => {
        const atual = (await c.query('SELECT exibir_no_menu FROM controle.modulo WHERE codigo = $1', [req.params.codigo])).rows[0];
        if (!atual) return 404;
        if (!atual.exibir_no_menu) return 400;
        await c.query('DELETE FROM controle.modulo WHERE codigo = $1', [req.params.codigo]);
        return 204;
      });
      if (r === 404) return reply.code(404).send({ erro: 'modulo_nao_encontrado' });
      if (r === 400) return reply.code(400).send({ erro: 'modulo_de_sistema' });
      return reply.code(204).send();
    } catch (e) {
      if (e.code === '23503') return reply.code(409).send({ erro: 'modulo_em_uso' });
      throw e;
    }
  });

  // Modulos criados pelo administrador que ESTE usuario pode usar: viram itens do menu.
  app.get('/meus-modulos', { preHandler: app.autenticar }, async (req) => comUsuario(pool, req.usuarioId, async (c) => ({
    itens: (await c.query(
      `SELECT m.codigo, m.nome, m.descricao, m.icone
         FROM controle.modulo m
        WHERE m.ativo AND m.exibir_no_menu AND controle.modulo_liberado($1, m.codigo)
        ORDER BY m.ordem, m.nome`, [req.usuarioId])).rows,
  })));
}
