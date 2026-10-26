import { comUsuario } from '../db.js';
import { codigoDoNome } from './acesso.js';

// Cadastro de modulos: so o SuperUsuario cria, libera e desativa. Cada modulo pode ser liberado para
// varios usuarios (e/ou por plano); a liberacao de cada usuario pode ser vitalicia ou valer entre duas
// datas. Passada a data final (ou desativada a liberacao), o usuario deixa de ter acesso ao modulo.
// Os de fabrica (financas, saude...) nao podem ser excluidos nem desativados.
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
  liberacoes: {
    type: 'array',
    maxItems: 500,
    items: {
      type: 'object',
      additionalProperties: false,
      required: ['usuario_id'],
      properties: {
        usuario_id: { type: 'string', format: 'uuid' },
        ativa: { type: 'boolean' },
        vitalicio: { type: 'boolean' },
        inicio: { type: ['string', 'null'], format: 'date-time' },
        fim: { type: ['string', 'null'], format: 'date-time' },
      },
    },
  },
};

export default async function rotasModulos(app) {
  const { pool } = app;
  const admin = (req, fn) => comUsuario(pool, req.usuarioId, fn, { admin: true });
  const gerenciar = [app.exigir('administracao.modulo.gerenciar'), app.exigirSuper];

  const SELECT = `
    SELECT m.codigo, m.nome, m.descricao, m.ordem, m.ativo, m.liberado_para_todos, m.icone,
           m.exibir_no_menu, NOT m.exibir_no_menu AS sistema,
           coalesce((SELECT array_agg(l.plano_codigo ORDER BY l.plano_codigo) FROM controle.liberacao_modulo l
                      WHERE l.modulo_codigo = m.codigo AND l.plano_codigo IS NOT NULL AND l.concedida), '{}') AS planos,
           coalesce((SELECT json_agg(json_build_object(
                       'usuario_id', l.usuario_id, 'usuario_nome', u.nome, 'usuario_email', u.email,
                       'ativa', l.ativa, 'vitalicio', l.vitalicio, 'inicio', l.inicio, 'fim', l.fim,
                       'vigente', (l.ativa AND (l.vitalicio OR ((l.inicio IS NULL OR l.inicio <= now())
                                                               AND (l.fim IS NULL OR l.fim > now()))))
                     ) ORDER BY u.nome)
                       FROM controle.liberacao_modulo l
                       JOIN controle.usuario u ON u.id = l.usuario_id AND u.excluido_em IS NULL
                      WHERE l.modulo_codigo = m.codigo AND l.usuario_id IS NOT NULL AND l.concedida), '[]'::json) AS liberacoes
      FROM controle.modulo m`;

  /** Valida e normaliza as liberacoes; devolve a mensagem de erro, ou null se estiver tudo certo. */
  const validarLiberacoes = (lista) => {
    const vistos = new Set();
    for (const l of lista) {
      if (vistos.has(l.usuario_id)) return 'Há o mesmo usuário mais de uma vez.';
      vistos.add(l.usuario_id);
      l.ativa = l.ativa ?? true;
      l.vitalicio = l.vitalicio ?? true;
      if (l.vitalicio) { l.inicio = null; l.fim = null; continue; }
      if (!l.inicio || !l.fim) return 'Informe a data de início e a data final, ou marque como vitalício.';
      if (!(new Date(l.fim) > new Date(l.inicio))) return 'A data final precisa ser depois da data de início.';
    }
    return null;
  };

  /** Troca as liberacoes por usuario do modulo pela lista recebida. */
  const gravarLiberacoes = async (c, codigo, lista) => {
    const ids = lista.map((l) => l.usuario_id);
    const achados = (await c.query(
      'SELECT id FROM controle.usuario WHERE id = ANY($1::uuid[]) AND excluido_em IS NULL', [ids])).rowCount;
    if (achados !== ids.length) { const e = new Error('usuario inexistente'); e.code = 'USUARIO'; throw e; }
    await c.query(
      `DELETE FROM controle.liberacao_modulo
        WHERE modulo_codigo = $1 AND usuario_id IS NOT NULL AND (concedida OR usuario_id = ANY($2::uuid[]))`,
      [codigo, ids]);
    for (const l of lista) {
      await c.query(
        `INSERT INTO controle.liberacao_modulo (modulo_codigo, usuario_id, ativa, vitalicio, inicio, fim)
         VALUES ($1, $2, $3, $4, $5, $6)`, [codigo, l.usuario_id, l.ativa, l.vitalicio, l.inicio, l.fim]);
    }
  };

  const gravarPlanos = async (c, codigo, planos) => {
    await c.query('DELETE FROM controle.liberacao_modulo WHERE modulo_codigo = $1 AND plano_codigo IS NOT NULL', [codigo]);
    for (const p of planos) {
      await c.query('INSERT INTO controle.liberacao_modulo (modulo_codigo, plano_codigo) VALUES ($1, $2)', [codigo, p]);
    }
  };

  const erroDoBanco = (e, reply) => {
    if (e.code === 'USUARIO') return reply.code(400).send({ erro: 'dados_invalidos', campo: 'liberacoes', detalhe: 'Usuário não encontrado.' });
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
    const falha = validarLiberacoes(b.liberacoes ?? []);
    if (falha) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'liberacoes', detalhe: falha });
    try {
      const m = await admin(req, async (c) => {
        const ordem = b.ordem ?? ((await c.query('SELECT coalesce(max(ordem), 0) + 1 AS n FROM controle.modulo')).rows[0].n);
        await c.query(
          `INSERT INTO controle.modulo (codigo, nome, descricao, ordem, ativo, liberado_para_todos, icone, exibir_no_menu)
           VALUES ($1, $2, $3, $4, $5, $6, $7, true)`,
          [codigo, b.nome.trim(), b.descricao ?? null, ordem, b.ativo ?? true, b.liberado_para_todos ?? false,
            b.icone ?? 'extension']);
        await gravarPlanos(c, codigo, b.planos ?? []);
        await gravarLiberacoes(c, codigo, b.liberacoes ?? []);
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
    const falha = validarLiberacoes(b.liberacoes ?? []);
    if (falha) return reply.code(400).send({ erro: 'dados_invalidos', campo: 'liberacoes', detalhe: falha });
    try {
      const r = await admin(req, async (c) => {
        const atual = (await c.query('SELECT exibir_no_menu FROM controle.modulo WHERE codigo = $1', [req.params.codigo])).rows[0];
        if (!atual) return { nao: 404 };
        if (!atual.exibir_no_menu && b.ativo === false) return { nao: 400 };
        // Modulos do pacote (de fabrica) fazem parte do app e nao precisam de liberacao.
        if (!atual.exibir_no_menu && (b.liberacoes !== undefined || b.planos !== undefined || b.liberado_para_todos !== undefined)) {
          return { nao: 422 };
        }
        const chaves = ['nome', 'descricao', 'ordem', 'icone', ...(atual.exibir_no_menu ? ['liberado_para_todos', 'ativo'] : [])];
        const campos = [];
        const valores = [req.params.codigo];
        for (const k of chaves) {
          if (k in b) { valores.push(k === 'nome' ? b[k].trim() : b[k]); campos.push(`${k} = $${valores.length}`); }
        }
        if (campos.length) await c.query(`UPDATE controle.modulo SET ${campos.join(', ')} WHERE codigo = $1`, valores);
        if (b.planos !== undefined) await gravarPlanos(c, req.params.codigo, b.planos);
        if (b.liberacoes !== undefined) await gravarLiberacoes(c, req.params.codigo, b.liberacoes);
        return { m: (await c.query(`${SELECT} WHERE m.codigo = $1`, [req.params.codigo])).rows[0] };
      });
      if (r.nao === 404) return reply.code(404).send({ erro: 'modulo_nao_encontrado' });
      if (r.nao === 400) return reply.code(400).send({ erro: 'modulo_de_sistema' });
      if (r.nao === 422) return reply.code(400).send({ erro: 'modulo_de_pacote' });
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

  // Modulos do menu do usuario logado: so os liberados para ele e dentro da validade.
  // O SuperUsuario ve todos os modulos cadastrados.
  app.get('/meus-modulos', { preHandler: app.autenticar }, async (req) => {
    const todos = await app.ehSuperusuario(req.usuarioId);
    return comUsuario(pool, req.usuarioId, async (c) => ({
      itens: (await c.query(
        `SELECT m.codigo, m.nome, m.descricao, m.icone
           FROM controle.modulo m
          WHERE m.ativo AND m.exibir_no_menu AND ($2 OR controle.modulo_liberado($1, m.codigo))
          ORDER BY m.ordem, m.nome`, [req.usuarioId, todos])).rows,
    }), { admin: todos });
  });
}
