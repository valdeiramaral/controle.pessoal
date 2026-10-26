#!/bin/bash
# Roda na primeira subida do container, depois do schema.sql.
# Cria o papel que a API usa. Ele NAO e dono das tabelas nem superusuario,
# entao a seguranca por linha (RLS) vale para ele.
set -e
psql -v ON_ERROR_STOP=1 -v senha="$APP_API_SENHA" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE app_api LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD :'senha';
GRANT USAGE ON SCHEMA controle TO app_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA controle TO app_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA controle TO app_api;
ALTER ROLE app_api SET search_path TO controle, public;
SQL
