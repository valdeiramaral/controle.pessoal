-- Sincronizacao entre aparelhos (tabela nova; NAO apaga nem altera nenhum dado existente).
-- Aplique uma vez no banco ja criado. PowerShell:
--   Get-Content banco/migracoes/2026-11-03_sincronizacao_registro.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;

-- ---------- Sincronizacao entre aparelhos (um registro por linha, qualquer modulo) ----------
-- Cada aparelho envia e recebe os registros do app (financas, saude, agenda, leitura,
-- biblioteca...) como JSON: nenhum campo e perdido e uma regra do banco nunca trava o envio.
-- id = UUID gerado no aparelho; editado_em = hora da ultima edicao no aparelho (decide
-- conflitos: a ultima edicao vence; exclusao vence edicao); atualizado_em = hora do SERVIDOR
-- (clock_timestamp, serve de cursor). Nada e apagado: excluir e marcar excluido_em.
CREATE TABLE IF NOT EXISTS sincronizacao_registro (
  usuario_id    uuid NOT NULL REFERENCES usuario(id),
  tabela        text NOT NULL CHECK (tabela ~ '^[a-z_]{1,40}$'),
  id            text NOT NULL CHECK (length(id) BETWEEN 1 AND 64),
  dados         jsonb NOT NULL,
  editado_em    timestamptz NOT NULL,
  excluido_em   timestamptz,
  atualizado_em timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (usuario_id, tabela, id)
);
CREATE INDEX IF NOT EXISTS ix_sincronizacao_registro_cursor ON sincronizacao_registro (usuario_id, atualizado_em);
ALTER TABLE sincronizacao_registro ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_sincronizacao_registro_dono ON sincronizacao_registro;
CREATE POLICY p_sincronizacao_registro_dono ON sincronizacao_registro
  USING (usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid)
  WITH CHECK (usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid);
DROP TRIGGER IF EXISTS trg_sincronizacao_registro_atualizado ON sincronizacao_registro;
CREATE TRIGGER trg_sincronizacao_registro_atualizado BEFORE INSERT OR UPDATE ON sincronizacao_registro
  FOR EACH ROW EXECUTE FUNCTION set_atualizado_em();


-- O papel da API precisa enxergar a tabela nova (as tabelas antigas ja foram liberadas na criacao).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_api') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON sincronizacao_registro TO app_api;
  END IF;
END $$;
