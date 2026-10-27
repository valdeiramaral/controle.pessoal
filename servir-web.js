// Servidor estatico minimo para o app web compilado (app/build/web). Usado pelo rede.ps1.
// Uso: node servir-web.js [porta]
const http = require('http');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, 'app', 'build', 'web');
const porta = Number(process.argv[2] || 8090);
const tipos = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff2': 'font/woff2', '.map': 'application/json', '.txt': 'text/plain; charset=utf-8',
};

http.createServer((req, res) => {
  let rel = decodeURIComponent((req.url || '/').split('?')[0]);
  let arq = path.normalize(path.join(raiz, rel));
  if (!arq.startsWith(raiz)) { res.writeHead(403).end(); return; }
  if (!fs.existsSync(arq) || fs.statSync(arq).isDirectory()) {
    const idx = path.join(arq, 'index.html');
    arq = fs.existsSync(idx) ? idx : path.join(raiz, 'index.html');
  }
  res.writeHead(200, { 'content-type': tipos[path.extname(arq).toLowerCase()] || 'application/octet-stream', 'cache-control': 'no-cache' });
  fs.createReadStream(arq).pipe(res);
}).listen(porta, '0.0.0.0', () => console.log(`App web em http://0.0.0.0:${porta}`));
