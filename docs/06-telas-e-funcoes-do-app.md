# Telas e funções do app

| Área (`app/lib/features`) | Função |
|---|---|
| `auth` | Login (abas Entrar / Criar conta), cadastro completo, sessão segura, "lembrar e-mail" |
| `nav` | Casca com menu lateral recolhível, ícones coloridos, barra de página com nome/e-mail/Sair (`acoes_usuario.dart`) |
| `hoje` | Tela inicial em abas, filtros de período, indicadores (KPIs) |
| `financas` | Contas, categorias, lançamentos, saldos |
| `saude` | Medicação (posologia, doses do dia, estoque), consultas e exames (únicos ou periódicos), indicadores, documentos |
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

### Pagamento / recebimento (`core/pagamento.dart`, seção "Dados do pagamento" do formulário)
A **Data de vencimento** (despesa ou receita) é o campo do lançamento. Ao marcar **Registrar pagamento** (ou *Registrar recebimento*, nas receitas) — no formulário ou no botão do detalhe — aparecem:
- **Data do pagamento/recebimento** (padrão: hoje);
- **Forma de pagamento/recebimento:** dinheiro, PIX, transferência (TED/DOC), boleto, cartão de débito, cartão de crédito, débito automático, cheque, outro;
- **Banco/conta do pagamento/recebimento:** uma das suas contas (padrão: a conta do lançamento); é dela que o dinheiro sai ou entra no saldo;
- **Tipo:** *Total* quita o lançamento (fica pago); *Parcial* registra uma parte, o lançamento continua em aberto e o detalhe mostra "Falta pagar/receber";
- **Valor de desconto** (opcional, não passa do valor);
- **Valor pago/recebido:** no tipo Total começa em valor − desconto e pode ser alterado (juros, multa). No tipo Parcial deve ser maior que zero e, somado ao desconto, ficar abaixo do valor.
Regras de saldo: lançamento pago movimenta o caixa pelo **valor pago** (se registrado) na **conta do pagamento**; pagamento parcial ainda não altera saldos (só a quitação total). O dashboard continua posicionando o lançamento no mês do vencimento. **Desfazer pagamento** volta a pendente e limpa esses dados. Marcar o quadradinho da lista registra pagamento total, hoje, sem detalhes. Banco local `schemaVersion 4`.

## Saúde (`features/saude/`, regras em `core/saude_calculo.dart`)
A tela **Saúde** tem duas abas: **Medicação** e **Consultas e exames**. Banco local `schemaVersion 5` (tabelas `medicamento` ampliada e `agendamento_saude` nova).

### Medicação
- **Hoje:** doses programadas do dia em ordem de horário, cada uma com **Tomei** (registra o horário real e desconta do estoque), **Pular** e **Desfazer** (devolve ao estoque). Dose pendente depois do horário aparece como *Atrasada*. Medicamentos "somente quando necessário" têm o botão **Registrar dose**. Ao tomar e o estoque chegar ao mínimo, aparece o aviso de estoque baixo.
- **Meus medicamentos:** nome, dose, formato, frequência/horários, tratamento, estoque (com dias restantes estimados; vermelho quando baixo) e *Não estou tomando* para os suspensos. Tocar abre o formulário.
- **Formulário** (`medicamento_form_page.dart`), em três blocos:
  1. *Detalhes:* **Nome**, **Dose** (ex.: 100 mg), **Formato** (comprimido, cápsula, líquido, gotas, injeção, pomada, spray, adesivo, pó, outro), **Tratamento** (para que serve) e **Instruções**.
  2. *Quando você toma:* **Começar**, **Terminar** (opcional), **Frequência** (*todos os dias*, *dias da semana*, *a cada N dias*, *somente quando necessário*), **Horários** (até 12, por seletor de hora) e **Quantidade por tomada** (unidades descontadas do estoque a cada dose).
  3. *Estoque:* **Estoque atual**, **Lembrete de reabastecer** e **Lembrar quando restarem N** unidades.
- **Suspender:** pede confirmação ("O medicamento será alterado para *Não estou tomando*. Você não receberá mais lembretes"), cancela os lembretes e tira o medicamento das doses de hoje e do painel Hoje. **Voltar a tomar** reativa e refaz os lembretes. **Excluir** remove o medicamento.
- **Lembretes:** notificação local por horário — diária, semanal por dia da semana, ou doses avulsas (próximas 30) quando há data final ou intervalo de N dias; renovadas ao abrir a tela. Na web não há lembretes locais.

### Consultas e exames
- **Lista:** *Próximos* (do dia de hoje em diante, em ordem) e *Histórico* (realizados, cancelados, faltas e antigos sem baixa); filtros *Todos / Consultas / Exames / Vacinas e outros*; séries mostram `n/total`.
- **Formulário** (`agendamento_form_page.dart`): **Tipo** (consulta, exame, retorno, vacina, outro), **Descrição** (ou nome do exame), **Especialidade** (consulta/retorno), **Médico/profissional** (ou solicitante), **Local** (ou laboratório), **Data e hora**, **Lembrete** (15 min a 2 dias antes, ou nenhum; padrão 1 hora), **Preparo** (jejum, documentos) e **Observação**.
- **Agendamento periódico:** *Repetir* = semanal, quinzenal, mensal, bimestral, trimestral, semestral, anual ou **personalizado** (a cada N dias/semanas/meses/anos) com o **total de agendamentos** (2 a 60). Gera uma linha por data (31/01 + 1 mês = 28/02; hora mantida), com prévia "N agendamentos: de … a …".
- **Agenda:** cada data vira também um compromisso do tipo *saúde* na aba Agenda. Cancelar ou marcar *Faltei* tira o compromisso da Agenda; voltar para *agendado* o recoloca; excluir remove.
- **Detalhe** (`agendamento_detalhe_page.dart`): todos os dados e ações **Realizado** (com campo de resultado/anotações), **Faltei**, **Cancelar agendamento**, **Voltar para agendado**, **Editar** e **Excluir**. Em série, editar tem a caixa "Aplicar descrição, local, profissional, preparo, observação e lembrete também aos N seguintes" (a data muda só no aberto) e excluir pergunta *Só este* ou *Este e os seguintes*.

Limitação: os campos novos de `medicamento` e a tabela `agendamento_saude` são só locais por enquanto (a sincronização com o PostgreSQL não está ativa). Valores numéricos de estoque são inteiros (unidades).
