-- Modulo Leitura (ficha de leitura, com tela propria no app). Nao apaga nada: se o modulo "leitura" ja foi
-- cadastrado pelo SuperUsuario, ele e mantido como esta. PowerShell:
--   Get-Content banco/migracoes/2026-10-31_modulo_leitura.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;
INSERT INTO modulo (codigo, nome, descricao, ordem, liberado_para_todos)
VALUES ('leitura', 'Leitura', 'Fichas de leitura: livros lidos, notas e frases favoritas', 10, false)
ON CONFLICT (codigo) DO NOTHING;
