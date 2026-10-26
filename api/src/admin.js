import { comUsuario } from './db.js';

/**
 * Da um perfil a um usuario (ex.: promover a administrador). Usado pelo
 * comando `npm run promover`: a API nao tem rota publica para isso, porque o
 * primeiro administrador precisa nascer fora dela.
 */
export async function promover(pool, email, perfilCodigo = 'administrador') {
  return comUsuario(pool, '', async (c) => {
    const u = await c.query('SELECT id FROM controle.buscar_login($1)', [email]);
    if (!u.rowCount) throw new Error(`usuario nao encontrado: ${email}`);
    const p = await c.query('SELECT id FROM controle.perfil WHERE codigo = $1', [perfilCodigo]);
    if (!p.rowCount) throw new Error(`perfil nao encontrado: ${perfilCodigo}`);
    await c.query(
      'INSERT INTO controle.usuario_perfil (usuario_id, perfil_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [u.rows[0].id, p.rows[0].id]);
    return u.rows[0].id;
  }, { admin: true });
}
