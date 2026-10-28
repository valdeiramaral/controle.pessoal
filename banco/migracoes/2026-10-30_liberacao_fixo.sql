-- Na liberacao do modulo para um usuario, escolhe-se se o modulo fica "fixo" (fixado no topo do menu dele). PowerShell:
--   Get-Content banco/migracoes/2026-10-30_liberacao_fixo.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;
ALTER TABLE liberacao_modulo ADD COLUMN IF NOT EXISTS fixo boolean NOT NULL DEFAULT false;
-- A chave "fixo para todos os usuarios" saiu do cadastro do modulo: ninguem e fixo automaticamente.
UPDATE modulo SET no_pacote = false WHERE no_pacote;
