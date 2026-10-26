import { lerConfig } from './config.js';
import { criarPool } from './db.js';
import { criarApp } from './app.js';

let config;
try {
  config = lerConfig();
} catch (e) {
  console.error('ERRO: ' + e.message);
  process.exit(1);
}

const pool = criarPool(config.db);
const app = await criarApp({ pool, config, logger: true });

for (const sinal of ['SIGINT', 'SIGTERM']) {
  process.on(sinal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
}

await app.listen({ host: config.host, port: config.porta });
