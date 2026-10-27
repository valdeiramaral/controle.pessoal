# Histórico das etapas

Fonte: `git log` (41 commits até `8dda663`). Hash entre parênteses.

## Etapa 0 — Base do app
- Escopo, contrato de sincronização, esquema PostgreSQL (14 entidades de dados + acesso/licenças), app Flutter com Drift (SQLite local), módulos Finanças, Saúde, Agenda. (70ff56b, b681186)

## Fase 1 — API e autenticação
- API Node.js/Fastify: cadastro, login (JWT + argon2id), `/me`, administração de usuários. (5a76eaa)
- `preparar.bat` sobe banco e API. (f1841f2)
- App: telas de login/cadastro, cliente da API, sessão segura (35 testes). (56aee4b)
- Versão web de teste (SQLite WebAssembly, CORS, `web.bat`; porta livre). (2747af0, 3d28d86)
- Visual do login: degradê, cartão, duas colunas, painel da marca. (ff2e547, fb31e4d, cd68eff)
- "Lembrar de mim". (f591ad1)

## Fase 2 — Administração de acesso
- Cadastro completo (CPF, telefone, endereço, nascimento); plano, perfil e módulos por usuário. (5edbc78)
- Perfis, grupos e exceções de permissão por usuário (API e app). (d5427ee, 4d01170, 1f346ca, 7f34adb)
- CLI `superusuario` (senha só por variável de ambiente). (49bb4f5)
- Exclusão lógica de usuário. (960dee0)
- Ajustes: login de teste via `.env`, "Meus dados", CORS PUT/DELETE, menu da conta rolável. (362362d, 10e71fc, d4ffefe, d30cc74)

## Fase 3 — Visual e módulos
- Visual único, ícones outline, menu lateral recolhível. (fead893, 26e2d10)
- Cadastro de módulos; módulos novos aparecem no menu. (6615d13, f95528e)

## Fase 4 — SuperUsuário e isolamento
- SuperUsuário e isolamento por usuário na API e no app. (ff925cd, 9b46f93)
- Login obrigatório a cada abertura; sem sessão automática. (a00f1ec)
- Tela inicial "Hoje" em abas com filtros de período e indicadores. (e12a99a)
- Aparência por usuário: claro/escuro/sistema, tamanho da letra, cor, ícones coloridos. (e1e6d80, 85d5298)
- Nome, e-mail e **Sair** no topo de todas as telas. (9230661)
- Lançamentos só para o SuperUsuário (e83110f) — **revertido** (5effd43): a regra correta é autonomia total de cada usuário.
- Isolamento real: banco local por usuário; membros de grupos filtrados por escopo. (c31e192)

## Fase 5 — Licenciamento de módulos
- API: liberação para vários usuários, validade (início/fim) ou vitalício, desativável; módulos "do pacote" sem liberação; SuperUsuário define o pacote. (7e8c352)
- App: cadastro de módulos com pacote, liberação por usuário, validade e desativação. (e35db08)
- 91 ícones vetoriais gratuitos (Material Icons) por categoria, com busca. (b536a50)
- Correção "Invalid argument: 1" na aba Resumo. (8dda663)

## Fase 6 — Documentação e backup
- Esta pasta `docs/`, geradores automáticos e `backup.bat`/`backup.ps1`.

## Fase 7 — Dashboard de Finanças
- Aba Dashboard em Finanças no layout de referência (saldos, ranking, visão geral, contas, orçamentos, recorrência), cálculos em `core/dashboard.dart`, orçamentos/contas/categorias e lançamentos com categoria e recorrência.

## Pendências conhecidas
- Rodar `testar.bat` (testes Flutter novos), aplicar migração `2026-10-28_liberacao_modulo_validade.sql` e reconstruir a imagem da API.
- Importar lançamentos locais antigos "órfãos" para a conta do SuperUsuário (opcional).
- Pacotes de ícones SVG (Lucide/Tabler) via `flutter_svg` (opcional).
