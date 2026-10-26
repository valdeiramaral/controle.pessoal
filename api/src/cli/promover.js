// Uso: npm run promover -- email@exemplo.com [perfil]     (perfil padrao: administrador)
import { lerConfig } from '../config.js';
import { criarPool } from '../db.js';
import { promover } from '../admin.js';

const [email, perfil = 'administrador'] = process.argv.slice(2);
if (!email) {
  console.error('Uso: promover <email> [perfil]');
  process.exit(1);
}
const pool = criarPool(lerConfig().db);
try {
  const id = await promover(pool, email.trim().toLowerCase(), perfil);
  console.log(`OK: ${email} agora tem o perfil "${perfil}" (id ${id}).`);
} catch (e) {
  console.error('ERRO: ' + e.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
