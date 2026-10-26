// Gera a documentacao de TODOS os objetos do banco (tabelas, colunas, restricoes, indices, tipos,
// funcoes, gatilhos, politicas de seguranca por linha) lendo o catalogo do PostgreSQL.
// Uso: PGHOST=... PGPORT=... PGUSER=... PGPASSWORD=... PGDATABASE=... node src/cli/docs-banco.js > ../docs/05-banco-objetos.md
import pg from 'pg';

const SCHEMA = process.env.DOCS_SCHEMA ?? 'controle';
const c = new pg.Client();
await c.connect();
const q = async (sql, p = []) => (await c.query(sql, p)).rows;
const esc = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
const linhas = [];
const w = (s = '') => linhas.push(s);

w('# Objetos do banco de dados (gerado)');
w();
w(`Gerado a partir do catalogo do PostgreSQL, esquema \`${SCHEMA}\`. Fonte da verdade: \`banco/schema.sql\` e \`banco/migracoes/\`.`);
w('Para atualizar: `docker compose exec api node src/cli/docs-banco.js` (veja docs/08-operacao-backup.md).');
w();

const tabelas = await q(
  `SELECT c.oid, c.relname, c.relrowsecurity, c.relforcerowsecurity, obj_description(c.oid) AS comentario
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind IN ('r', 'p') ORDER BY c.relname`, [SCHEMA]);
const enums = await q(
  `SELECT t.typname, array_agg(e.enumlabel::text ORDER BY e.enumsortorder) AS valores
     FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE n.nspname = $1 GROUP BY t.typname ORDER BY t.typname`, [SCHEMA]);
const funcoes = await q(
  `SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_function_result(p.oid) AS retorno,
          p.prosecdef, l.lanname, obj_description(p.oid) AS comentario, p.provolatile
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = $1 AND p.prokind = 'f' ORDER BY p.proname, args`, [SCHEMA]);
const gatilhos = await q(
  `SELECT c.relname AS tabela, t.tgname, pg_get_triggerdef(t.oid) AS def
     FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND NOT t.tgisinternal ORDER BY c.relname, t.tgname`, [SCHEMA]);
const politicas = await q(
  `SELECT tablename, policyname, cmd, roles, qual, with_check FROM pg_policies WHERE schemaname = $1 ORDER BY tablename, policyname`, [SCHEMA]);
const views = await q(`SELECT viewname FROM pg_views WHERE schemaname = $1 ORDER BY 1`, [SCHEMA]);
const extensoes = await q(`SELECT extname, extversion FROM pg_extension ORDER BY 1`);

w('## Resumo');
w();
w(`| Tipo de objeto | Quantidade |`);
w(`|---|---|`);
w(`| Tabelas | ${tabelas.length} |`);
w(`| Tipos enumerados | ${enums.length} |`);
w(`| Funcoes | ${funcoes.length} |`);
w(`| Gatilhos (triggers) | ${gatilhos.length} |`);
w(`| Politicas de seguranca por linha (RLS) | ${politicas.length} |`);
w(`| Views | ${views.length} |`);
w();
w(`Extensoes instaladas: ${extensoes.map((e) => `${e.extname} ${e.extversion}`).join(', ')}.`);
w();
w('## Tabelas');
w();
w('| Tabela | Colunas | RLS | Descricao |');
w('|---|---|---|---|');
const nCols = Object.fromEntries((await q(
  `SELECT c.relname, count(*)::int AS n FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND a.attnum > 0 AND NOT a.attisdropped AND c.relkind IN ('r','p') GROUP BY c.relname`, [SCHEMA])).map((r) => [r.relname, r.n]));
for (const t of tabelas) w(`| [\`${t.relname}\`](#${t.relname}) | ${nCols[t.relname]} | ${t.relrowsecurity ? 'sim' : 'nao'} | ${esc(t.comentario)} |`);
w();

for (const t of tabelas) {
  w(`### ${t.relname}`);
  w();
  if (t.comentario) { w(t.comentario); w(); }
  const cols = await q(
    `SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS tipo, a.attnotnull, pg_get_expr(d.adbin, d.adrelid) AS padrao,
            col_description(a.attrelid, a.attnum) AS comentario
       FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = $1 AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum`, [t.oid]);
  w('| Coluna | Tipo | Obrigatoria | Padrao | Descricao |');
  w('|---|---|---|---|---|');
  for (const k of cols) w(`| \`${k.attname}\` | ${esc(k.tipo)} | ${k.attnotnull ? 'sim' : 'nao'} | ${esc(k.padrao)} | ${esc(k.comentario)} |`);
  w();
  const cons = await q(
    `SELECT conname, contype, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = $1 ORDER BY contype, conname`, [t.oid]);
  const nomes = { p: 'Chave primaria', f: 'Chave estrangeira', u: 'Unica', c: 'Regra (CHECK)', x: 'Exclusao' };
  if (cons.length) {
    w('Restricoes:');
    w();
    for (const k of cons) w(`- **${nomes[k.contype] ?? k.contype}** \`${k.conname}\`: \`${esc(k.def)}\``);
    w();
  }
  const idx = await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = $1 AND tablename = $2 ORDER BY indexname`, [SCHEMA, t.relname]);
  if (idx.length) {
    w('Indices:');
    w();
    for (const i of idx) w(`- \`${i.indexname}\`: \`${esc(i.indexdef)}\``);
    w();
  }
  const gt = gatilhos.filter((g) => g.tabela === t.relname);
  if (gt.length) {
    w('Gatilhos:');
    w();
    for (const g of gt) w(`- \`${g.tgname}\`: \`${esc(g.def)}\``);
    w();
  }
  const po = politicas.filter((p) => p.tablename === t.relname);
  if (po.length) {
    w('Seguranca por linha (RLS):');
    w();
    for (const p of po) w(`- \`${p.policyname}\` (${p.cmd}): USING \`${esc(p.qual)}\`${p.with_check ? ` WITH CHECK \`${esc(p.with_check)}\`` : ''}`);
    w();
  }
}

w('## Tipos enumerados');
w();
for (const e of enums) w(`- \`${e.typname}\`: ${e.valores.map((v) => `\`${v}\``).join(', ')}`);
w();
w('## Funcoes');
w();
w('| Funcao | Argumentos | Retorno | Linguagem | Roda como dono (SECURITY DEFINER) | Descricao |');
w('|---|---|---|---|---|---|');
for (const f of funcoes) w(`| \`${f.proname}\` | ${esc(f.args)} | ${esc(f.retorno)} | ${f.lanname} | ${f.prosecdef ? 'sim' : 'nao'} | ${esc(f.comentario)} |`);
w();
if (views.length) {
  w('## Views');
  w();
  for (const v of views) w(`- \`${v.viewname}\``);
  w();
}
console.log(linhas.join('\n'));
await c.end();
