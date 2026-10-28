-- Modulo Biblioteca (cadastro de obras, com tela propria no app). Nao apaga nada: se o modulo "biblioteca" ja foi
-- cadastrado pelo SuperUsuario, ele e mantido como esta. PowerShell:
--   Get-Content banco/migracoes/2026-11-01_modulo_biblioteca.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;
INSERT INTO modulo (codigo, nome, descricao, ordem, liberado_para_todos)
VALUES ('biblioteca', 'Biblioteca', 'Cadastro de obras (livros), acervo e localização', 11, false)
ON CONFLICT (codigo) DO NOTHING;
