import pg from 'pg';

export function criarPool(db) {
  return new pg.Pool({ ...db, max: 10 });
}

/**
 * Roda `fn(client)` dentro de uma transacao com o usuario da sessao definido
 * (app.usuario_id), para a seguranca por linha (RLS) do banco valer.
 *
 * `admin: true` liga o modo administrador (app.admin = 'on'): so use depois de
 * conferir a permissao do usuario logado. O valor vale apenas dentro da
 * transacao (set_config com `true`), entao nao vaza para a proxima requisicao
 * que reaproveitar a conexao.
 */
export async function comUsuario(pool, usuarioId, fn, { admin = false } = {}) {
  const c = await pool.connect();
  let descartar = false;
  try {
    await c.query('BEGIN');
    await c.query("SELECT set_config('app.usuario_id', $1, true)", [usuarioId ?? '']);
    if (admin) await c.query("SELECT set_config('app.admin', 'on', true)");
    const r = await fn(c);
    await c.query('COMMIT');
    return r;
  } catch (e) {
    try { await c.query('ROLLBACK'); } catch { descartar = true; }
    throw e;
  } finally {
    c.release(descartar);
  }
}
