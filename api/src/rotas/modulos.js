import { comUsuario } from '../db.js';
import { codigoDoNome } from './acesso.js';

// Cadastro de modulos: so o SuperUsuario cria e entrega modulos; cada modulo criado tem um DONO,
// e so o dono (alem do SuperUsuario) o ve no menu. Os de fabrica (financas, saude...) valem para
// todos, nao tem dono e nao podem ser excluidos nem desativados.
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
  dono_id: { type: 'string', format: 'uuid' },
};

export default async function rotasModulos(app) {
  const { pool } = app;
  const admin = (req, fn) => comUsuario(pool, req.usuarioId, fn, { admin: true });
  const gerenciar = [app.exigir('administracao.modulo.gerenciar'), app.exigirSuper];

  const SELECT = `
    SELECT m.codigo, m.nome, m.descricao, m.ordem, m.ativo, m.liberado_para_todos, m.icone,
           m.exibir_no_menu, NOT m.exibir_no_menu AS sistema, m.dono_id,
           (SELECT u.nome FROM controle.usuario u WHERE u.id = m.dono_id) AS dono_nome,
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
    schema: { body: { type: 'object', required: ['nome', 'dono_id'], additionalProperties: false, properties: propriedades } },
  }, async (req, reply) => {
    const b = req.body;
    const codigo = codigoDoNome(b.nome);
    if (!/^[a-z][a-z0-9_]{1,40}$/.test(codigo)) {
      return reply.code(400).send({ erro: 'dados_invalidos', campo: 'nome', detalhe: 'Use um nome com letras (ao menos 2).' });
    }
    try {
      const m = await admin(req, async (c) => {
        const ordem = b.ordem ?? ((await c.query('SELECT coalesce(max(ordem), 0) + 1 AS n FROM controle.modulo')).rows[0].n);
        if (!(await c.query('SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [b.dono_id])).rowCount) {
          return null;
        }
        await c.query(
          `INSERT INTO controle.modulo (codigo, nome, descricao, ordem, ativo, liberado_para_todos, icone, exibir_no_menu, dono_id)
           VALUES ($1, $2, $3, $4, $5, false, $6, true, $7)`,
          [codigo, b.nome.trim(), b.descricao ?? null, ordem, b.ativo ?? true, b.icone ?? 'extension', b.dono_id]);
        return (await c.query(`${SELECT} WHERE m.codigo = $1`, [codigo])).rows[0];
      });
      if (!m) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'dono_id', detalhe: 'Usuário dono não encontrado.' });
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
        // Modulo do SuperUsuario: tem dono e nao se libera por plano; de fabrica: nao tem dono.
        const chaves = atual.exibir_no_menu ? ['nome', 'descricao', 'ordem', 'ativo', 'icone', 'dono_id']
          : ['nome', 'descricao', 'ordem', 'liberado_para_todos', 'icone'];
        if (atual.exibir_no_menu && b.dono_id !== undefined
          && !(await c.query('SELECT 1 FROM controle.usuario WHERE id = $1 AND excluido_em IS NULL', [b.dono_id])).rowCount) {
          return { nao: 422 };
        }
        const campos = [];
        const valores = [req.params.codigo];
        for (const k of chaves) {
          if (k in b) { valores.push(k === 'nome' ? b[k].trim() : b[k]); campos.push(`${k} = $${valores.length}`); }
        }
        if (campos.length) await c.query(`UPDATE controle.modulo SET ${campos.join(', ')} WHERE codigo = $1`, valores);
        if (b.planos !== undefined && !atual.exibir_no_menu) await gravarPlanos(c, req.params.codigo, b.planos);
        return { m: (await c.query(`${SELECT} WHERE m.codigo = $1`, [req.params.codigo])).rows[0] };
      });
      if (r.nao === 404) return reply.code(404).send({ erro: 'modulo_nao_encontrado' });
      if (r.nao === 400) return reply.code(400).send({ erro: 'modulo_de_sistema' });
      if (r.nao === 422) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'dono_id', detalhe: 'Usuário dono não encontrado.' });
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

  // Modulos do menu do usuario logado: os que ele possui. O SuperUsuario ve os de todos (com o nome do dono).
  app.get('/meus-modulos', { preHandler: app.autenticar }, async (req) => {
    const todos = await app.ehSuperusuario(req.usuarioId);
    return comUsuario(pool, req.usuarioId, async (c) => ({
      itens: (await c.query(
        `SELECT m.codigo, m.nome, m.descricao, m.icone, m.dono_id,
                (SELECT u.nome FROM controle.usuario u WHERE u.id = m.dono_id) AS dono_nome
           FROM controle.modulo m
          WHERE m.ativo AND m.exibir_no_menu AND ($2 OR m.dono_id = $1)
          ORDER BY m.ordem, m.nome`, [req.usuarioId, todos])).rows,
    }), { admin: todos });
  });
}
