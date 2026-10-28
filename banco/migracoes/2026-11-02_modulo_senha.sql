-- Modulo Senha (cofre de senhas, com tela propria no app). Nao apaga nada: se o modulo "senha" ja foi
-- cadastrado pelo SuperUsuario, ele e mantido como esta. PowerShell:
--   Get-Content banco/migracoes/2026-11-02_modulo_senha.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;
INSERT INTO modulo (codigo, nome, descricao, ordem, liberado_para_todos)
VALUES ('senha', 'Senha', 'Cofre de senhas, cartões, notas e chaves de acesso (cifrado no aparelho)', 12, false)
ON CONFLICT (codigo) DO NOTHING;
