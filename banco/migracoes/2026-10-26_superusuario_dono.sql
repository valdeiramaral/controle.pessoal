-- SuperUsuario e isolamento por usuario: cada usuario ve so o que e dele; o SuperUsuario ve tudo.
-- Para bancos ja criados (instalacoes novas ja trazem isso no schema.sql). PowerShell:
--   Get-Content banco/migracoes/2026-10-26_superusuario_dono.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS superusuario boolean NOT NULL DEFAULT false;
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS criado_por uuid REFERENCES usuario (id) ON DELETE SET NULL;
ALTER TABLE modulo ADD COLUMN IF NOT EXISTS dono_id uuid REFERENCES usuario (id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION e_superusuario(u uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  SELECT coalesce((SELECT superusuario FROM usuario WHERE id = u AND excluido_em IS NULL AND ativo), false)
$$;
REVOKE ALL ON FUNCTION e_superusuario(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION e_superusuario(uuid) TO app_api;
