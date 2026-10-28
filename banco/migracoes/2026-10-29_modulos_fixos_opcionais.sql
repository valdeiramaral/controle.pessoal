-- Nenhum modulo e fixo automaticamente: "fixo para todos os usuarios" (no_pacote) passa a ser escolha do
-- SuperUsuario no cadastro de modulos. Os modulos de fabrica com tela (Hoje, Financas, Saude, Agenda) agora
-- entram no menu do app pelo cadastro. PowerShell:
--   Get-Content banco/migracoes/2026-10-29_modulos_fixos_opcionais.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;

UPDATE modulo SET no_pacote = false
 WHERE codigo IN ('financas', 'saude', 'agenda', 'painel', 'sincronizacao') AND NOT exibir_no_menu;

-- Nomes curtos para o menu (so se ninguem os tiver mudado).
UPDATE modulo SET nome = 'Agenda do Dia' WHERE codigo = 'painel' AND nome IN ('Hoje', 'Painel Hoje e relatórios');
UPDATE permissao SET nome = 'Ver a Agenda do Dia' WHERE codigo = 'painel.hoje.ver' AND nome = 'Ver o painel Hoje';
UPDATE modulo SET nome = 'Agenda', descricao = 'Compromissos, eventos, tarefas e lembretes'
 WHERE codigo = 'agenda' AND nome = 'Agenda e compromissos';
