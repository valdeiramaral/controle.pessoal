import { comUsuario } from './db.js';
import { gerarHash } from './seguranca.js';

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

/**
 * Cria (ou atualiza) um superusuario de testes: perfil administrador, plano
 * vitalicio (ou anual, se nao existir) e todos os modulos liberados.
 * Se o e-mail ja existe, a senha e trocada e a conta reativada.
 */
export async function criarSuperusuario(pool, { email, senha, nome = 'Super Usuário' }) {
  const senhaHash = await gerarHash(senha);
  let id = (await comUsuario(pool, '', (c) => c.query('SELECT id FROM controle.buscar_login($1)', [email]),
    { admin: true })).rows[0]?.id;
  const criado = !id;
  if (criado) {
    id = (await pool.query('SELECT controle.cadastrar_usuario($1, $2, $3) AS id', [nome, email, senhaHash])).rows[0].id;
  } else {
    await comUsuario(pool, '', (c) => c.query(
      'UPDATE controle.usuario SET senha_hash = $2, ativo = true WHERE id = $1', [id, senhaHash]),
    { admin: true });
  }
  await promover(pool, email, 'administrador');
  const plano = await comUsuario(pool, '', async (c) => {
    const p = (await c.query("SELECT codigo FROM controle.plano WHERE codigo = 'vitalicio'")).rowCount
      ? 'vitalicio' : 'anual';
    await c.query(
      `UPDATE controle.licenca SET status = 'cancelada',
              fim = greatest(inicio + interval '1 microsecond', least(coalesce(fim, now()), now()))
        WHERE usuario_id = $1 AND status = 'ativa'`, [id]);
    await c.query(
      "INSERT INTO controle.licenca (usuario_id, plano_codigo, status, origem) VALUES ($1, $2, 'ativa', 'cortesia')",
      [id, p]);
    for (const m of (await c.query('SELECT codigo FROM controle.modulo WHERE ativo')).rows) {
      await c.query('DELETE FROM controle.liberacao_modulo WHERE usuario_id = $1 AND modulo_codigo = $2', [id, m.codigo]);
      await c.query('INSERT INTO controle.liberacao_modulo (modulo_codigo, usuario_id, concedida) VALUES ($1, $2, true)',
        [m.codigo, id]);
    }
    return p;
  }, { admin: true });
  return { id, criado, plano };
}
