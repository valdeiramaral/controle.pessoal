// Cria (ou atualiza) um superusuario de testes: perfil administrador, plano vitalicio
// e todos os modulos liberados. A senha NUNCA fica no codigo: vem do ambiente.
//   Docker:  docker compose exec -e SUPER_EMAIL=a@b.com -e SUPER_SENHA=... api node src/cli/superusuario.js
import { lerConfig } from '../config.js';
import { criarPool } from '../db.js';
import { criarSuperusuario } from '../admin.js';

const email = (process.env.SUPER_EMAIL ?? '').trim().toLowerCase();
const senha = process.env.SUPER_SENHA ?? '';
if (!email || senha.length < 8) {
  console.error('Defina SUPER_EMAIL e SUPER_SENHA (minimo 8 caracteres).');
  process.exit(1);
}
const pool = criarPool(lerConfig().db);
try {
  const r = await criarSuperusuario(pool, { email, senha, nome: process.env.SUPER_NOME || undefined });
  console.log(`OK: ${email} ${r.criado ? 'criado' : 'atualizado'} como administrador (plano ${r.plano}, todos os modulos liberados).`);
} catch (e) {
  console.error('ERRO: ' + e.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
