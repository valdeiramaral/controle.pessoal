-- Cadastro de modulos: icone e "aparece no menu" (modulos criados pelo administrador).
-- Para bancos ja criados (instalacoes novas ja trazem isso no schema.sql):
--   docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /dev/stdin' < banco/migracoes/2026-10-26_modulo_menu.sql
SET search_path TO controle, public;
ALTER TABLE modulo ADD COLUMN IF NOT EXISTS icone text NOT NULL DEFAULT 'extension';
ALTER TABLE modulo ADD COLUMN IF NOT EXISTS exibir_no_menu boolean NOT NULL DEFAULT false;
