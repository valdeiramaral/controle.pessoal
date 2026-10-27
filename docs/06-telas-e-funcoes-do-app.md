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

## Contas bancárias (`features/financas/contas_page.dart`, `conta_form_page.dart`, `conta_detalhe_page.dart`)
Aba **Contas** de Finanças, em três telas:
1. **Lista** — "Minhas contas" (cartões com banco, agência, conta e saldo) e "Contas externas" (só cadastro, sem saldo); botão **Adicionar conta**.
2. **Adicionar/Editar conta** — tipo (corrente, poupança, cartão, dinheiro), "Conta de minha titularidade?", banco (catálogo de 19 opções em `core/bancos.dart`, selo colorido com sigla, sem logotipos), agência, conta, CPF/CNPJ (opcional), chave PIX (opcional), apelido (opcional) e saldo inicial (só contas próprias). Tipo "Dinheiro" esconde os dados bancários e exige um nome.
3. **Gerenciar conta** — mostra os dados, botão **Editar** e lixeira para excluir.

Regras:
- Agência: 1–5 dígitos (+ `-dígito`); conta: 1–12 dígitos (+ `-dígito`); CPF/CNPJ com dígitos verificadores corretos; PIX: CPF/CNPJ, celular, e-mail ou chave aleatória (`core/conta_validacao.dart`).
- Não permite duas contas ativas com o mesmo banco + agência + número.
- Contas **externas** não têm saldo e não entram no saldo total, no dashboard nem na escolha de conta do lançamento.
- Exclusão é lógica; é **recusada** para a conta padrão (Carteira) e para contas com lançamentos.
- Banco local: `schemaVersion 2` (migração adiciona `titularidade, banco, agencia, numero_conta, documento, chave_pix, apelido`); servidor: `banco/migracoes/2026-10-27_conta_bancaria.sql`.
- "Novo banco" (primeiro da lista) permite cadastrar um banco fora da lista Febraban e exige o nome do banco.

## Lançamento de despesas e receitas (`features/financas/lancamento_form_page.dart`)
Botão **+** da aba Lançamentos abre o formulário (Despesa ou Receita). Cálculos em `core/lancamento_calculo.dart`; gravação em `Banco.lancar`.
1. **Descrição** (obrigatória) — texto que facilita achar a despesa na listagem (Aluguel da casa, Telefone, Energia).
2. **Valor** — maior que zero. Em despesa parcelada é o **valor total**, dividido nas parcelas (a sobra de centavos vai para as primeiras; a soma fecha exatamente o total). Mostra prévia ("3x de ...").
3. **Data** — vencimento (recebimento, para receita), por seletor de data.
4. **Conta/cartão** — contas próprias (corrente, poupança, cartão, dinheiro); contas externas não aparecem.
5. **Categoria** — da lista do tipo (despesa/receita), "Sem categoria" ou **+ Nova categoria** sem sair da tela.
6. **Repetir** — *Não repetir* (opção "Já foi paga"), *Fixa (todo mês)* por N meses (2 a 60; um lançamento por mês, recorrência mensal) ou *Parcelada* em N vezes (2 a 120). Vencimentos mensais mantêm o dia, sem estourar o fim do mês (31/01 + 1 mês = 28/02).
7. **Observação** — texto livre até 500 caracteres (método de pagamento, juros...).
8. **Anexos** — vários arquivos (PDF, foto, texto), até 10, 5 MB cada, escolhidos pelo seletor do aparelho; ficam no banco local (tabela `anexo`, schema v3) e, em séries, no primeiro lançamento.
9. **Tags** — palavras livres em minúsculas, sem repetição, até 10 de 30 letras; gravadas separadas por vírgula.
Na listagem, cada lançamento mostra data, tags e o clipe com a quantidade de anexos.
### Detalhe, edição e exclusão (`lancamento_detalhe_page.dart`)
Tocar num lançamento da lista abre o **detalhe**: descrição, valor, situação (paga/a pagar, alternável), vencimento, conta/cartão, categoria, parcela ou repetição, observação, tags e anexos.
- **Anexos:** tocar abre a prévia (imagem ou texto) com botão **Baixar**; PDF e demais tipos são baixados direto (`file_saver`: download no navegador ou gravação na pasta do aparelho).
- **Editar** (lápis): mesmo formulário, com tipo e repetição fixos. Valor, descrição, vencimento e situação valem só para o lançamento aberto; numa série (fixa/parcelada) a caixa "Aplicar conta, categoria, tags e observação também aos N seguintes" estende esses quatro campos aos lançamentos posteriores. Anexos podem ser removidos (desfazer antes de salvar) e novos podem ser adicionados.
- **Excluir** (lixeira): exclusão lógica do lançamento e dos seus anexos; em série pergunta "Só este" ou "Este e os seguintes". Deslizar na lista exclui só aquele lançamento.

Limitação: a tabela `anexo` é só local (sem equivalente no PostgreSQL, pois a sincronização de lançamentos não está ativa).
