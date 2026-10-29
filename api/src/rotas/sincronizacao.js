import { comUsuario } from '../db.js';

// Sincronizacao entre aparelhos (ver contrato-sincronizacao.md, secao "Versao 2").
// Cada registro do app (qualquer modulo) e guardado como JSON em sincronizacao_registro.
//  - Conflito: a ultima edicao (editado_em) vence; exclusao vence edicao; nada e apagado.
//  - Cursor: sempre a hora do SERVIDOR (atualizado_em), devolvida como texto com microssegundos.
//  - Reenviar o mesmo lote nao muda nada (idempotente).

const MAX_REGISTROS_POR_ENVIO = 100;
const MAX_REGISTROS_POR_RESPOSTA = 100;
const NOME_TABELA = '^[a-z_]{1,40}$';

const registro = {
  type: 'object',
  required: ['id', 'editado_em', 'dados'],
  additionalProperties: false,
  properties: {
    id: { type: 'string', minLength: 1, maxLength: 64 },
    editado_em: { type: 'string', minLength: 10, maxLength: 40 },
    excluido_em: { type: ['string', 'null'], maxLength: 40 },
    dados: { type: 'object' },
  },
};

const CURSOR_SQL = `to_char(atualizado_em AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;

export default async function rotasSincronizacao(app) {
  const { pool } = app;

  app.post('/sincronizar', {
    preHandler: app.exigir('sincronizacao.sincronizar'),
    bodyLimit: 32 * 1024 * 1024,
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        properties: {
          cursor: { type: ['string', 'null'], maxLength: 40 },
          alteracoes: {
            type: 'object',
            propertyNames: { pattern: NOME_TABELA },
            additionalProperties: { type: 'array', items: registro },
          },
        },
      },
    },
  }, async (req, reply) => {
    const { cursor = null, alteracoes = {} } = req.body ?? {};
    const total = Object.values(alteracoes).reduce((n, l) => n + l.length, 0);
    if (total > MAX_REGISTROS_POR_ENVIO) {
      return reply.code(400).send({ erro: 'dados_invalidos', detalhe: `no maximo ${MAX_REGISTROS_POR_ENVIO} registros por envio` });
    }
    if (cursor !== null && Number.isNaN(Date.parse(cursor))) {
      return reply.code(400).send({ erro: 'dados_invalidos', campo: 'cursor', detalhe: 'cursor invalido' });
    }
    for (const lista of Object.values(alteracoes)) {
      for (const r of lista) {
        if (Number.isNaN(Date.parse(r.editado_em)) || (r.excluido_em && Number.isNaN(Date.parse(r.excluido_em)))) {
          return reply.code(400).send({ erro: 'dados_invalidos', campo: 'editado_em', detalhe: `data invalida no registro ${r.id}` });
        }
      }
    }

    return comUsuario(pool, req.usuarioId, async (c) => {
      // 1. Grava o que o aparelho enviou. A linha so e trocada se for mais nova e nao estiver excluida.
      const recusados = [];
      for (const [tabela, lista] of Object.entries(alteracoes)) {
        for (const r of lista) {
          const res = await c.query(
            `INSERT INTO controle.sincronizacao_registro AS s (usuario_id, tabela, id, dados, editado_em, excluido_em)
             VALUES ($1, $2, $3, $4::jsonb, $5::timestamptz, $6::timestamptz)
             ON CONFLICT (usuario_id, tabela, id) DO UPDATE
               SET dados = EXCLUDED.dados, editado_em = EXCLUDED.editado_em, excluido_em = EXCLUDED.excluido_em
             WHERE s.excluido_em IS NULL
               AND (EXCLUDED.excluido_em IS NOT NULL OR EXCLUDED.editado_em > s.editado_em)`,
            [req.usuarioId, tabela, r.id, JSON.stringify(r.dados), r.editado_em, r.excluido_em ?? null]);
          if (res.rowCount === 0) recusados.push({ tabela, id: r.id });
        }
      }

      // 2. Devolve o que mudou no servidor depois do cursor (inclui o que o proprio aparelho acabou de enviar).
      const lidos = (await c.query(
        `SELECT tabela, id, dados, excluido_em, ${CURSOR_SQL} AS cursor,
                to_char(editado_em AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS editado_em
           FROM controle.sincronizacao_registro
          WHERE usuario_id = $1 AND ($2::timestamptz IS NULL OR atualizado_em > $2::timestamptz)
          ORDER BY atualizado_em, tabela, id
          LIMIT $3`,
        [req.usuarioId, cursor, MAX_REGISTROS_POR_RESPOSTA + 1])).rows;
      const temMais = lidos.length > MAX_REGISTROS_POR_RESPOSTA;
      const pagina = temMais ? lidos.slice(0, MAX_REGISTROS_POR_RESPOSTA) : lidos;
      const saida = {};
      for (const l of pagina) {
        (saida[l.tabela] ??= []).push({
          id: l.id, editado_em: l.editado_em, excluido_em: l.excluido_em ? new Date(l.excluido_em).toISOString() : null, dados: l.dados,
        });
      }

      // 3. Registros que o servidor recusou (ja existe versao mais nova ou excluida): devolve a versao do servidor.
      const conflitos = [];
      for (const { tabela, id } of recusados) {
        const s = (await c.query(
          `SELECT dados, excluido_em, to_char(editado_em AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS editado_em
             FROM controle.sincronizacao_registro WHERE usuario_id = $1 AND tabela = $2 AND id = $3`,
          [req.usuarioId, tabela, id])).rows[0];
        if (!s) continue;
        conflitos.push({ tabela, id });
        const ja = (saida[tabela] ??= []);
        if (!ja.some((x) => x.id === id)) {
          ja.push({ id, editado_em: s.editado_em, excluido_em: s.excluido_em ? new Date(s.excluido_em).toISOString() : null, dados: s.dados });
        }
      }

      const novoCursor = pagina.length ? pagina[pagina.length - 1].cursor : cursor;
      return { cursor: novoCursor, tem_mais: temMais, alteracoes: saida, conflitos };
    });
  });
}
