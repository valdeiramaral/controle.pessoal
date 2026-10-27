# Telas e funções do app

| Área (`app/lib/features`) | Função |
|---|---|
| `auth` | Login (abas Entrar / Criar conta), cadastro completo, sessão segura, "lembrar e-mail" |
| `nav` | Casca com menu lateral recolhível, ícones coloridos, barra de página com nome/e-mail/Sair (`acoes_usuario.dart`) |
| `hoje` | Tela inicial em abas, filtros de período, indicadores (KPIs) |
| `financas` | Contas, categorias, lançamentos, saldos |
| `saude` | Medicamentos, consultas, indicadores, documentos |
| `agenda` | Eventos, tarefas, lembretes |
| `aparencia` | Claro/Escuro/Sistema, tamanho da letra, cor do sistema |
| `admin` | Usuários, perfis, grupos, permissões, planos, cadastro de módulos (pacote, liberação por usuário, validade/vitalício, ícones com busca) |
| `modulos` | Menu dinâmico a partir de `/meus-modulos` |

Testes em `app/test/` (19 arquivos). Execução: `testar.bat`.

## Dashboard de Finanças (`features/financas/dashboard_page.dart`)
Aba **Dashboard** do módulo Finanças (ao lado da aba **Lançamentos**), com navegação mês a mês. Cálculos puros em `core/dashboard.dart` (testados em `app/test/dashboard_financas_test.dart`).

| Cartão | Regra |
|---|---|
| Inicial / Saldo atual / Previsto | Inicial = saldo inicial das contas + pagos antes do mês; atual = + pagos até o fim do mês; previsto = + todos (pagos e pendentes) até o fim do mês |
| Ranking categorias | Despesas do mês por categoria (barras com %); sem categoria aparece como "Sem categoria" |
| Visão geral | Saldo nas contas, Total recebido, Total gasto (lançamentos do mês), Total faturas (despesas em contas tipo cartão); variação % contra o mês anterior (verde = bom, vermelho = ruim) |
| Contas | Por conta: receitas e despesas do mês, saldo (pagos) e previsto (todos) |
| Orçamentos de despesas | Limite por categoria e mês (menu ⋮ → Definir orçamento); barra gasto/limite, vermelho ao estourar, marcador "Hoje" no mês atual |
| Despesas por recorrência | Rosca: **Fixas** (lançamento com recorrência), **Parceladas** (com parcelas), **Variáveis** (demais) |

Transferências não entram em receitas nem despesas. O menu ⋮ também cria contas e categorias. O diálogo "Novo lançamento" agora aceita conta, categoria e recorrência (variável, fixa mensal ou parcelada, que cria uma parcela por mês).
