import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';

const aqui = path.dirname(fileURLToPath(import.meta.url));
// No Docker, o testar.ps1 monta o banco/ em /banco e informa SCHEMA_SQL.
const SCHEMA = process.env.SCHEMA_SQL || path.join(aqui, '..', '..', 'banco', 'schema.sql');
export const NOME_BANCO = 'ctrl_api_teste';
export const USUARIO_API = 'app_api_teste';
export const SENHA_API = 'teste';

// Conexao de administrador (variaveis PGHOST, PGPORT, PGUSER, PGPASSWORD).
export async function conexaoAdmin(database = NOME_BANCO) {
  const c = new pg.Client({ database });
  await c.connect();
  return c;
}

/** Cria um banco novo com o schema.sql e um papel parecido com o app_api. */
export async function prepararBanco() {
  const adm = await conexaoAdmin('postgres');
  await adm.query(`DROP DATABASE IF EXISTS ${NOME_BANCO} WITH (FORCE)`);
  await adm.query(`CREATE DATABASE ${NOME_BANCO}`);
  await adm.query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${USUARIO_API}') THEN
        CREATE ROLE ${USUARIO_API} LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD '${SENHA_API}';
      END IF;
    END $$`);
  await adm.end();

  const c = await conexaoAdmin();
  await c.query(readFileSync(SCHEMA, 'utf8'));
  await c.query(`
    GRANT USAGE ON SCHEMA controle TO ${USUARIO_API};
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA controle TO ${USUARIO_API};
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA controle TO ${USUARIO_API};
    ALTER ROLE ${USUARIO_API} IN DATABASE ${NOME_BANCO} SET search_path TO controle, public;`);
  return c; // conexao de superusuario para o teste ajustar dados
}

export async function removerBanco() {
  const adm = await conexaoAdmin('postgres');
  await adm.query(`DROP DATABASE IF EXISTS ${NOME_BANCO} WITH (FORCE)`);
  // O papel so tinha permissoes dentro do banco que acabou de ser apagado.
  await adm.query(`DROP ROLE IF EXISTS ${USUARIO_API}`).catch(() => {});
  await adm.end();
}

export function configDeTeste() {
  return {
    host: '127.0.0.1',
    porta: 0,
    db: {
      host: process.env.PGHOST || 'localhost',
      port: Number(process.env.PGPORT || 5432),
      database: NOME_BANCO,
      user: USUARIO_API,
      password: SENHA_API,
    },
    jwtSecret: 'segredo-de-teste-com-mais-de-32-caracteres!!',
    tokenExpiraSegundos: 3600,
    limiteAuth: 10000,
  };
}
