// Gera a lista de rotas da API (metodo, caminho, permissao exigida, arquivo) lendo o codigo-fonte.
// Uso: node src/cli/docs-api.js > ../docs/04-api-rotas.md
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'rotas');
const rotaRe = /app\.(get|post|put|patch|delete)\(\s*'([^']+)'/g;
const saida = [];
saida.push('# Rotas da API (gerado)', '');
saida.push('Gerado por `node src/cli/docs-api.js` a partir de `api/src/rotas/*.js`.', '');
saida.push('Legenda de acesso: **publica** = sem login; **login** = precisa de token; **permissao X** = login + permissao X;');
saida.push('**SuperUsuario** = so o SuperUsuario. Regras detalhadas em docs/03-regras-de-negocio.md.', '');
let total = 0;
for (const arq of readdirSync(raiz).filter((f) => f.endsWith('.js')).sort()) {
  const txt = readFileSync(path.join(raiz, arq), 'utf8');
  const marcas = [...txt.matchAll(rotaRe)];
  if (!marcas.length) continue;
  saida.push(`## ${arq}`, '', '| Metodo | Caminho | Acesso |', '|---|---|---|');
  marcas.forEach((m, i) => {
    const fim = marcas[i + 1]?.index ?? txt.length;
    const trecho = txt.slice(m.index, Math.min(fim, m.index + 700));
    const acesso = [];
    const perm = [...trecho.matchAll(/app\.exigir\('([^']+)'\)/g)].map((x) => x[1]);
    if (perm.length) acesso.push(...perm.map((p) => `permissao ${p}`));
    if (/exigirSuper|gerenciar\b/.test(trecho) && /exigirSuper/.test(txt.slice(0, m.index)) === false && /exigirSuper/.test(trecho)) acesso.push('SuperUsuario');
    if (/preHandler:\s*gerenciar\b/.test(trecho) && /const gerenciar = \[[^\]]*exigirSuper/.test(txt)) acesso.push('SuperUsuario');
    if (/exigirSuper/.test(trecho) && !acesso.includes('SuperUsuario')) acesso.push('SuperUsuario');
    if (!acesso.length && /app\.autenticar/.test(trecho)) acesso.push('login');
    if (!acesso.length) acesso.push('publica');
    saida.push(`| ${m[1].toUpperCase()} | \`${m[2]}\` | ${acesso.join(' + ')} |`);
    total++;
  });
  saida.push('');
}
saida.push(`Total: ${total} rotas.`, '');
console.log(saida.join('\n'));
