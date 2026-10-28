# Regras de negócio

## Acesso e sessão
1. Todo início do app exige login válido; não há uso sem conta nem sessão automática.
2. Cada usuário é autônomo: não vê lançamentos, módulos, configurações ou dados de outro usuário.
3. O **SuperUsuário** vê e administra tudo (usuários, perfis, grupos, módulos).
4. Administradores comuns veem apenas a si mesmos e os usuários que criaram (`criado_por`).
5. Perfis e grupos: escrita somente pelo SuperUsuário. Membros de grupos só aparecem dentro do escopo do solicitante.
6. Permissões efetivas = perfis + grupos + exceções por usuário.
7. Exclusão de usuário é lógica (`excluido_em`).

## Módulos
1. Módulos de fábrica (`NOT exibir_no_menu`) não podem ser excluídos nem desativados.
2. Módulos personalizados: criados/alterados/excluídos só pelo SuperUsuário; aparecem em `/meus-modulos` apenas se `modulo_liberado` (SuperUsuário vê todos).
3. **Fixo no menu** (`liberacao_modulo.fixo`): escolhido na liberação do módulo para cada usuário: marcado = aparece no menu dele; desmarcado = liberado, mas oculto do menu. Não existe módulo fixo para todos automaticamente.
4. **Liberação** (`liberacao_modulo`) por usuário, grupo ou plano, com `ativa`.
5. **Vitalício:** datas ignoradas. **Não vitalício:** `inicio` e `fim` obrigatórios, `fim > inicio` (fim enviado como 23:59:59 local). Depois do fim, o acesso é perdido.
6. `liberado_para_todos` libera sem exigir concessão.

## Aparência (por usuário, em `usuario.preferencias`)
modo ∈ claro | escuro | sistema; escala de fonte 0,8–1,6; cor ∈ azul | verde | roxo | laranja | rosa | turquesa. Salvo via `PUT /me/preferencias`.

## Tela e interface
Nome, e-mail e **Sair** aparecem ao lado da conta em todas as telas. Tela inicial "Agenda do Dia" (antes "Hoje") em abas com filtros de período e indicadores.

## Dados
Todas as tabelas de dados do usuário têm `id` (UUID do aparelho), `usuario_id`, `criado_em`, `atualizado_em`, `excluido_em`. Detalhes de cada objeto em `05-banco-objetos.md`; rotas em `04-api-rotas.md`.

## Finanças — dashboard
Ver tabela de regras em `06-telas-e-funcoes-do-app.md` (seção Dashboard de Finanças). Valores em centavos; só registros ativos (`excluido_em` nulo); transferência não conta como receita/despesa; recorrência: fixa = tem `recorrencia`, parcelada = tem `parcela_total`, variável = demais; orçamento é único por categoria e mês (dia 1).

## Finanças — contas bancárias
Titularidade `propria` (do usuário; tem saldo) ou `externa` (de terceiros; só cadastro, fora de saldos e lançamentos). Banco/agência/número únicos entre contas ativas. Documento (CPF/CNPJ) guardado só com dígitos. Conta padrão e contas com lançamentos não podem ser excluídas. Detalhes em `06-telas-e-funcoes-do-app.md`; colunas em `05-banco-objetos.md` (tabela `conta`).
