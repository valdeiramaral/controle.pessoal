# Cronograma de desenvolvimento por módulos

Projeto: app de controle pessoal (finanças, saúde, agenda), Android e iOS.
Início: 19/10/2026 · Última revisão: 20/10/2026 · Previsão de término: **30/04/2027**.

As durações são estimativas para uma pessoa trabalhando com apoio do Claude. As fases rodam em sequência (de segunda a sexta) e há uma semana de folga no fim do ano. Se uma fase atrasar, as seguintes deslizam; a coluna "Folga" mostra onde dá para recuperar tempo.

## Como os módulos funcionam

Cada módulo tem uma lista de processos. Cada processo é uma permissão (`modulo.objeto.acao`).

- **Cadastro:** o administrador cadastra módulos e permissões (módulo Administração).
- **Liberação:** um módulo só aparece para quem estiver liberado. A liberação vale para um usuário, para um grupo ou para um plano (gratuito, mensal, anual, vitalício). Um bloqueio explícito vence qualquer liberação.
- **Permissão:** dentro do módulo liberado, o usuário só faz o que seus perfis permitem. Os perfis vêm do próprio usuário ou dos grupos dele. Exceções individuais concedem ou negam uma permissão só para ele.
- **Cobrança:** desligada no início (tudo gratuito). Quando ligada, só licença paga vigente dá acesso.

Já pronto no banco (108 testes passando em 20/10/2026): catálogos de país e idioma, usuário com e-mail e senha, módulos, permissões, perfis, grupos, liberação de módulos, planos, licenças, pagamentos, funções de acesso e verificação de integridade entre usuários.

## Módulos

| Cód. | Módulo | Processos (permissões) | Liberação de partida |
|---|---|---|---|
| M1 | Acesso e usuários | cadastrar, ver e editar usuário; gerenciar perfis; gerenciar grupos | Todos |
| M2 | Idiomas e países | gerenciar catálogo de países e idiomas | Todos |
| M3 | Licenças e cobrança | ver licença; conceder licença; ver pagamentos; gerenciar planos e preços | Todos |
| M4 | Finanças | gerenciar contas; ver e lançar receitas e despesas; orçamentos e metas | Plano |
| M5 | Saúde | ver e gerenciar medicamentos; consultas; indicadores; exames e documentos | Plano |
| M6 | Agenda e compromissos | ver e gerenciar compromissos; tarefas; lembretes | Plano |
| M7 | Painel Hoje e relatórios | ver painel Hoje; exportar relatórios | Plano |
| M8 | Sincronização | sincronizar dados entre aparelho e servidor | Plano |
| M9 | Administração | cadastrar módulos; liberar módulos para usuários, grupos e planos | Todos (restrito por permissão) |

## Visão geral das fases

| Fase | Período | Duração | Módulos | Entrega principal | Situação |
|---|---|---|---|---|---|
| 0. Base | 19/10 a 30/10/2026 | 2 sem | Escopo, banco, esqueleto | Banco testado, app com 4 telas locais, scripts | Em fechamento |
| 1. Acesso | 02/11 a 20/11/2026 | 3 sem | M1, M2, M9 (parte) | API com cadastro e login; telas de login em vários idiomas | A fazer |
| 2. Módulos e liberação | 23/11 a 04/12/2026 | 2 sem | M9 | Telas do administrador; app mostra só módulos liberados; banco local criptografado | A fazer |
| 3. Finanças | 07/12 a 24/12/2026 | 3 sem | M4 | Contas, lançamentos, a pagar, orçamentos e metas | Esqueleto pronto |
| Folga de fim de ano | 28/12/2026 a 01/01/2027 | 1 sem | | Recesso e margem para atrasos | |
| 4. Saúde | 04/01 a 22/01/2027 | 3 sem | M5 | Medicamentos, consultas, indicadores, documentos | Esqueleto pronto |
| 5. Agenda | 25/01 a 05/02/2027 | 2 sem | M6 | Compromissos, tarefas, lembretes, ligação com consultas | Esqueleto pronto |
| 6. Painel e relatórios | 08/02 a 19/02/2027 | 2 sem | M7 | Tela Hoje completa, relatórios, exportação | A fazer |
| 7. Sincronização | 22/02 a 12/03/2027 | 3 sem | M8 | Envio e recebimento, conflitos, uso sem internet | A fazer |
| 8. Licenças e cobrança | 15/03 a 09/04/2027 | 4 sem | M3 | Planos, Pix e cartão, cobrança ligável | Banco pronto |
| 9. Publicação | 12/04 a 30/04/2027 | 3 sem | Todos | Testes finais, contas de desenvolvedor, lojas | A fazer |

Pontos de atenção de calendário: o Carnaval (08 a 10/02/2027) cai na fase 6, e o Natal e o Ano Novo ficam entre as fases 3 e 4.

## Detalhe por fase

### Fase 0. Base (19/10 a 30/10/2026) — em fechamento

- [x] Escopo, esquema do banco e esqueleto do app Flutter
- [x] Scripts de instalar, iniciar, parar e testar
- [x] Testes do banco: 108 de 108 passando (20/10)
- [x] Correções da revisão: cursor de sincronização, e-mail reaproveitável, integridade entre usuários, saldo, valores digitados, id de notificação
- [ ] Rodar `.\testar.ps1` no PC e confirmar os testes do app e do banco (21/10)
- [ ] Recriar o banco do Docker com o schema novo: `.\parar.ps1 -ApagarDados` e `.\iniciar.ps1` (21/10)
- [ ] Abrir o app no emulador e passar pelas 4 telas (22/10 a 23/10)
- [x] Definir o **contrato de sincronização**: formato dos ids (UUID desde o primeiro uso, trocando `conta-padrao` e `local`), tipos (centavos, horários, tags) e ordem das tabelas. Escrito em `contrato-sincronizacao.md` (26/10)
- [x] Decidir API própria (Node.js) ou Supabase: **API própria em Node.js** (26/10)
- [x] Iniciar o repositório Git (26/10): commit `70ff56b`, `.env` e arquivos gerados fora do repositório

**Pronto quando:** o app abre no emulador, os testes passam no PC e o contrato de sincronização está escrito.

### Fase 1. Acesso (02/11 a 20/11/2026)

- Semana 1 (02 a 06/11): API Node.js base, conexão com o papel `app_api`, rotas de cadastro e login que chamam `cadastrar_usuario` e `buscar_login`, hash de senha (argon2id), emissão de token. **Adiantado em 26/10:** feito e testado (22 testes), além de `/me`, `GET /usuarios`, `PATCH /usuarios/:id` e o comando `promover`. **Telas de login e cadastro no app (26/10):** feitas e testadas (sessão guardada no Keystore/Keychain, "usar sem conta", sair). Falta renovar o token (hoje dura 1 h e depois pede login). **Cadastro com CPF, telefone e endereço, e administração de usuários (plano, perfil, módulos liberados) no app e na API (26/10):** feitos; falta rodar os testes do app no PC. **Perfis, grupos e exceções de permissão por usuário (26/10):** API (54 testes) e telas do app feitas; falta rodar os testes do app no PC
- Semana 2 (09 a 13/11): bloqueio após 5 erros (`registrar_login`), modo administrador só depois de conferir permissão, regra "nunca montar SQL com texto do usuário", rotas de perfis, grupos e permissões
- Semana 3 (16 a 20/11): telas de login e cadastro no app, escolha de país e idioma, textos em pt-BR, pt-PT, en e es, testes da API

**Pronto quando:** uma pessoa se cadastra, entra, e o app mostra o idioma do país escolhido.

### Fase 2. Módulos e liberação (23/11 a 04/12/2026)

- Semana 1 (23 a 27/11): telas do administrador para cadastrar módulos e liberar para usuário, grupo ou plano; rota `modulos_do_usuario` no app
- Semana 2 (30/11 a 04/12): app mostra só os módulos liberados; **banco local criptografado (SQLCipher)** com chave no Keychain/Keystore; bloqueio por biometria

**Pronto quando:** liberar ou bloquear um módulo muda o que aparece no app, e o arquivo do banco local não abre sem a chave.

### Fase 3. Finanças (07/12 a 24/12/2026)

- Semana 1 (07 a 11/12): contas e carteiras, categorias e subcategorias, tags, ligação com as permissões
- Semana 2 (14 a 18/12): contas a pagar e a receber, recorrência, parcelamento, alerta de vencimento
- Semana 3 (21 a 24/12): orçamento mensal com aviso em 80% e 100%, metas e reserva, transferência entre contas (com conta de destino)

**Pronto quando:** dá para controlar o mês inteiro só pelo app, com saldo por conta.

### Folga de fim de ano (28/12/2026 a 01/01/2027)

Recesso. Se a fase 3 atrasar, a semana serve para terminar.

### Fase 4. Saúde (04/01 a 22/01/2027)

- Semana 1 (04 a 08/01): medicamentos com horários, lembretes diários e registro de tomada ("tomei" ou "pulei" na notificação)
- Semana 2 (11 a 15/01): estoque com alerta de reposição, consultas e exames com preparo, ligação com a agenda e com o custo da consulta
- Semana 3 (18 a 22/01): indicadores (peso, pressão, glicemia, sono, água) com gráfico, perfil de saúde, documentos (fotos e PDFs)

**Pronto quando:** a pessoa recebe o lembrete, confirma a tomada e vê o histórico de adesão.

### Fase 5. Agenda (25/01 a 05/02/2027)

- Semana 1 (25 a 29/01): eventos, visões de dia, semana, mês e lista, recorrência, lembretes antecipados
- Semana 2 (01 a 05/02): tarefas ligadas a eventos, detecção de conflitos (inclusive evento contra horário de remédio), ligação com consultas

**Pronto quando:** um compromisso que colide com um remédio gera aviso.

### Fase 6. Painel Hoje e relatórios (08/02 a 19/02/2027)

- Semana 1 (08 a 12/02, com Carnaval): linha do tempo do dia, pendências, resumo financeiro
- Semana 2 (15 a 19/02): relatórios (gasto por categoria, receita contra despesa, fluxo de caixa projetado), exportação em CSV e PDF, busca global

**Pronto quando:** a tela Hoje mostra compromissos, remédios, consultas e vencimentos em ordem de horário.

### Fase 7. Sincronização (22/02 a 12/03/2027)

- Semana 1 (22 a 26/02): envio de alterações (`atualizado_em` maior que o último envio), conversão de tipos entre app e servidor, envio em ordem de dependência (lembretes depois dos alvos)
- Semana 2 (01 a 05/03): recebimento, regra de conflito (a última edição vence), exclusão lógica, margem de segurança de 2 minutos no cursor
- Semana 3 (08 a 12/03): uso sem internet, reenvio automático, testes com dois aparelhos, teste de carga com dados reais

**Pronto quando:** uma alteração feita offline no celular A aparece no celular B depois que A volta à internet.

### Fase 8. Licenças e cobrança (15/03 a 09/04/2027)

- Semana 1 (15 a 19/03): escolha do provedor de pagamento (decidida até 01/03, ver abaixo), definição de preços por moeda
- Semana 2 (22 a 26/03): planos mensal, anual e vitalício, concessão de licença, pagamento por Pix
- Semana 3 (29/03 a 02/04): pagamento por cartão (guardando só os 4 últimos dígitos e a bandeira), confirmação por retorno do provedor
- Semana 4 (05 a 09/04): ligar `cobranca_ativa`, regra para quem usou o período gratuito, avisos de vencimento, testes completos de cobrança

**Pronto quando:** uma compra de teste libera os módulos e o vencimento da licença os bloqueia.

### Fase 9. Publicação (12/04 a 30/04/2027)

- Semana 1 (12 a 16/04): testes finais em aparelhos reais, correções, política de privacidade e termos
- Semana 2 (19 a 23/04): contas de desenvolvedor (Google Play e Apple), fichas das lojas, capturas de tela, teste fechado no Google Play
- Semana 3 (26 a 30/04): envio para revisão, ajustes pedidos pelas lojas, publicação

**Pronto quando:** o app está disponível nas lojas.

## Decisões e prazos

| Decisão | Prazo | Por quê |
|---|---|---|
| API própria (Node.js) ou Supabase | 28/10/2026 | Define toda a fase 1 e a fase 7 |
| Serviço de envio de e-mail (confirmação de cadastro e recuperação de senha) | 13/11/2026 | Necessário na fase 1 |
| Provedor de pagamento (Pix e cartão) | 01/03/2027 | Define a fase 8 |
| Preços de mensal, anual e vitalício por moeda | 15/03/2027 | Entram na tabela `plano_preco` |
| Quem usou o período gratuito mantém acesso ou passa a pagar | 26/03/2027 | Hoje o banco assume que passa a pagar |
| Compras dentro do app: regras do Google Play e da Apple para vender licença | 01/03/2027 | Podem exigir o pagamento deles e mudar a fase 8 |
| Mac e conta de desenvolvedor da Apple para o iPhone | 01/03/2027 | O iOS só compila em um Mac, e a conta leva dias para ser aprovada |
| Conta de desenvolvedor do Google Play | 01/03/2027 | Contas pessoais novas costumam exigir um período de teste fechado com testadores antes de publicar; confirmar a regra atual no Play Console |

## Riscos que podem mexer no cronograma

- **Sincronização (fase 7):** é a parte mais difícil. A fase 0 já define o contrato para reduzir o risco, mas se os conflitos ficarem complicados, pode pedir mais uma semana (use a folga de fim de ano ou corte itens da fase 6).
- **Lojas (fase 9):** a revisão da Apple e do Google pode levar dias e pedir correções. Por isso as contas e a ficha da loja entram na semana 2, antes do envio.
- **Pagamentos (fase 8):** a integração depende do provedor escolhido e de testes com dinheiro real em ambiente de teste. A decisão em 01/03 deixa duas semanas de margem.
- **iOS:** sem um Mac, o iPhone não compila. Se não houver Mac até março, a versão iOS sai depois da Android.
- **Uma pessoa só:** férias, doença ou outro projeto empurram tudo. A folga de fim de ano é a única margem fixa.
