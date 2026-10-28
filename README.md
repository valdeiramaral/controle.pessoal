# Projeto IA Pessoal - App de controle pessoal

App para controlar finanças, saúde e compromissos no Android e no iOS.

## Conteúdo da pasta

| Caminho | O que é |
| --- | --- |
| `escopo-app-controle-pessoal.md` | Escopo completo: módulos, requisitos, stack, modelo de dados, roadmap, riscos |
| `banco/schema.sql` | Esquema PostgreSQL do servidor: 14 tabelas, índices de sincronização, triggers e segurança por linha |
| `banco/testes/test_schema.py` | 118 testes do esquema (restrições, triggers, ligações entre módulos, isolamento entre usuários, integridade entre usuários) |
| `instalar-requisitos.bat` | Instala Git, Flutter, Android SDK/emulador e Docker Desktop (uma vez) |
| `iniciar.ps1`, `parar.ps1`, `testar.ps1` (e `.bat` de duplo clique) | Iniciam, param e testam tudo (ver Início rápido) |
| `docker-compose.yml`, `.env.example`, `banco/init/` | Banco PostgreSQL e API no Docker; o banco nasce com o schema e o papel `app_api` |
| `api/` | API Node.js (fase 1): cadastro, login, perfil `/me` e administração de usuários. Ver a seção API |
| `app/` | Esqueleto do app Flutter (banco local, 4 telas, lembretes locais, sincronização em esboço) |
| `contrato-sincronizacao.md` | Contrato entre app e API: ids, tipos, ordem das tabelas, protocolo e regra de conflito |
| `fontes/diagrama-arquitetura.jsx` | Fonte do diagrama de arquitetura do documento de escopo |

## Estado atual (fase 0 em fechamento, fase 1 iniciada)

**Banco: testado.** O `schema.sql` foi carregado em um PostgreSQL 16 real e passa nos 118 testes de `banco/testes/test_schema.py` (rodado de novo em 20/10/2026, depois das correções da revisão: cursor de sincronização com hora real, e-mail reaproveitável após exclusão, referências entre usuários e lembretes validadas, fuso e moeda validados). Os testes acharam e corrigiram dois defeitos na segurança por linha (erro em conexão reaproveitada e tabela `usuario` sem isolamento).

**App Flutter: 35 testes passando no seu PC (26/10/2026).** Cobrem banco local, saldo, valores digitados, id de notificação, cliente da API, sessão e telas de login/cadastro. Falta abrir o app no emulador.

O que o esqueleto já faz:

- **Hoje:** compromissos do dia, contas a pagar nos próximos 7 dias e remédios.
- **Finanças:** lançamentos (receita e despesa), saldo dos itens pagos, marcar como pago, excluir deslizando.
- **Saúde:** medicamentos com horários e notificação diária no aparelho.
- **Agenda:** compromissos com lembrete 30 minutos antes.
- Banco local com as 14 entidades (valores em centavos, UUID, exclusão lógica).
- Dois testes do banco em `app/test/`.

**API (fase 1, semana 1): testada.** 40 testes em `api/teste/`, contra um PostgreSQL 16 real, cobrindo cadastro, login, bloqueio após 5 erros, `/me`, permissões e o modo administrador. Os testes da API já rodam no Docker do seu PC (40 passando; rodar de novo após a mudança). Neste PC a porta 5432 é bloqueada pelo Windows; a porta do banco é `POSTGRES_PORT` no `.env` (está em 5440).

O que falta (fases seguintes do roadmap):

- Banco local criptografado (SQLCipher) e biometria.
- Sincronização com o servidor: `app/lib/data/sync/` é só o esboço, sem rede (regras em `contrato-sincronizacao.md`).
- Telas de login e cadastro no app, perfis, grupos e liberação de módulos na API (restante da fase 1 e fase 2).
- Cartão de crédito, orçamento, metas, relatórios, indicadores de saúde, documentos.
- Sincronização de calendário e integração com Apple Health e Health Connect.

## Início rápido (Windows)

### 1. Instalar os programas (uma vez só)

Dê duplo clique em `instalar-requisitos.bat` e aceite a janela de permissão de administrador do Windows. Ele instala e configura, pulando o que já existir:

- Git e Flutter (em `C:\src\flutter`, já no PATH);
- modo desenvolvedor do Windows (exigido pelos plugins do Flutter);
- Android Studio, Android SDK, licenças e um emulador chamado `controle_pessoal`;
- Docker Desktop, para o banco PostgreSQL.

Opções: `.\instalar-requisitos.ps1 -SemEmulador` (não baixa o emulador, por exemplo se você usar um celular com depuração USB) e `-SemDocker`. O registro da instalação fica em `instalar-requisitos.log`. Depois, **reinicie o Windows** se o script avisar (Docker e aceleração do emulador pedem), abra o Docker Desktop uma vez e abra um terminal novo. O iOS só compila em um Mac; neste PC o app roda no Android.

### 2. Iniciar o app

Dê duplo clique em `iniciar.bat` ou rode no PowerShell, dentro desta pasta:

```powershell
.\iniciar.ps1                              # banco + app (o Flutter pergunta o dispositivo)
.\iniciar.ps1 -ListarDispositivos          # mostra emuladores e aparelhos disponíveis
.\iniciar.ps1 -Dispositivo emulator-5554   # escolhe o dispositivo
.\iniciar.ps1 -SemBanco                    # só o app, sem subir o banco
.\iniciar.ps1 -SoPreparar                  # prepara tudo, mas não abre o app
.\testar.ps1                               # roda os testes do banco e do app
.\parar.ps1                                # para o banco (os dados ficam guardados)
.\parar.ps1 -ApagarDados                   # para e apaga os dados do banco local
```

O `iniciar.ps1` faz, nesta ordem:

1. Confere se Flutter e Docker estão instalados.
2. Cria o `.env` com senhas aleatórias (só na primeira vez; guarde esse arquivo).
3. Sobe o PostgreSQL no Docker e espera ele ficar pronto. Na primeira vez o banco é criado com o `banco/schema.sql` e com o papel `app_api`, que a API usará.
4. Na primeira vez, gera as pastas `android/` e `ios/` do app e ajusta o Android para os lembretes (permissões, receivers e *core library desugaring*).
5. Baixa os pacotes, gera o código do banco local (`build_runner`) e abre o app.

**Importante:** hoje o app guarda tudo no banco local do próprio aparelho. O banco e a API sobem no Docker, mas nada no app se conecta a eles ainda: as telas de login e a sincronização vêm nas próximas fases (`app/lib/data/sync/` é só um esboço).

**O que foi e o que não foi testado:** o `docker-compose.yml` foi validado (`docker compose config`) e a configuração de primeira subida do banco foi simulada em um PostgreSQL real. Os scripts `.ps1` **não foram executados** (não havia Windows, PowerShell, Flutter nem Docker em funcionamento no ambiente onde foram escritos). Se algum passo falhar, a mensagem de erro indica qual; me mande o texto que eu corrijo.

## API (Node.js, fase 1)

Sobe sozinha com o `.\iniciar.ps1` (serviço `api` do Docker) e fica em `http://localhost:3000` (porta `API_PORTA` do `.env`). O `iniciar.ps1` acrescenta o `JWT_SECRET` ao seu `.env` se ele ainda não existir. Teste rápido: abra `http://localhost:3000/saude`.

| Rota | O que faz | Quem pode |
| --- | --- | --- |
| `GET /saude` | Confere se a API e o banco estão de pé | Todos |
| `POST /cadastro` | Cria o usuário (nome, e-mail, senha de 8+ caracteres, país e idioma opcionais). Senha guardada só como hash argon2id | Todos |
| `POST /login` | Devolve um token válido por 1 hora. 5 erros seguidos bloqueiam a conta por 15 minutos | Todos |
| `GET /me` | Dados do usuário, licença, módulos liberados e permissões | Logado |
| `GET /usuarios` | Lista os usuários | Permissão `acesso.usuario.ver` |
| `PATCH /usuarios/:id` | Ativa ou desativa um usuário (vale na hora, inclusive para o token que ele já tinha) | Permissão `acesso.usuario.editar` |

O primeiro administrador nasce fora da API, com o comando abaixo (depois de cadastrar o usuário):

```powershell
docker compose exec api node src/cli/promover.js seu-email@exemplo.com
```

Superusuário de testes (administrador, plano vitalício, todos os módulos liberados; a senha vem do ambiente, nunca fica no código):

```powershell
docker compose exec -e SUPER_EMAIL=voce@exemplo.com -e SUPER_SENHA=sua-senha api node src/cli/superusuario.js
```

Regras que valem para todo código novo da API:

- Todo acesso a dados de usuário passa por `comUsuario()` (`api/src/db.js`), que define `app.usuario_id` na transação para a segurança por linha do banco valer.
- O modo administrador (`admin: true`) só é ligado depois de conferir a permissão do usuário logado (`app.exigir('...')`).
- Nunca montar SQL juntando texto vindo do usuário: sempre parâmetros (`$1`, `$2`).

Ainda não existe: confirmação de e-mail, recuperação de senha, renovação de token, rotas de perfis, grupos e liberação de módulos (restante das fases 1 e 2).

## Como rodar o app (passo a passo manual)

Pré-requisito: [Flutter](https://docs.flutter.dev/get-started/install) instalado (Android Studio para Android, Xcode para iOS; o iOS exige um Mac).

```bash
cd app
flutter create . --org br.com.seudominio --project-name controle_pessoal   # gera as pastas android/ e ios/
flutter pub get
dart run build_runner build --delete-conflicting-outputs                    # gera lib/data/local/banco.g.dart
flutter test
flutter run
```

Depois do `flutter create .`, configure as permissões de lembretes:

**Android** (`android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>`):

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

Siga também o guia do pacote `flutter_local_notifications` para os receivers de notificação agendada e o desugaring do Java.

**iOS:** a permissão de notificação é pedida ao abrir o app; não precisa de ajuste no `Info.plist`.

## Cadastro, dados da pessoa e liberação de módulos

- **Cadastro (pessoa):** nome, e-mail, senha, **CPF** (validado) e **telefone** são obrigatórios; endereço completo e data de nascimento são opcionais. Só dígitos ficam guardados (a API tira máscaras).
- **Administrador:** em *Conta > Usuários e acessos* cadastra e edita usuários, informando os dados da pessoa, o **tipo de plano**, o **perfil** e **cada módulo** (Padrão do plano, Liberado ou Bloqueado para aquele usuário). Cada ação exige a sua permissão (`acesso.usuario.cadastrar`, `licencas.licenca.conceder`, `acesso.perfil.gerenciar`, `administracao.liberacao.gerenciar`).
- **Usuário comum:** em *Conta > Meus dados* vê o plano e os módulos liberados e atualiza telefone, nascimento e endereço. CPF e e-mail só o administrador altera.
- **Banco:** o `schema.sql` mudou (colunas em `usuario` e `cadastrar_usuario` com novos parâmetros). Para um banco já criado, rode `.\parar.ps1 -ApagarDados` e depois o `preparar.bat` (apaga os dados de teste).
- **Rotas novas da API:** `GET /catalogo`, `GET|POST /usuarios`, `GET|PATCH /usuarios/:id`, `PUT /usuarios/:id/plano|modulos|perfis`, `PATCH /me`.

### Perfis, grupos e permissões detalhadas

Menu da conta → **Perfis e grupos** (aparece para quem tem `acesso.perfil.gerenciar` ou `acesso.grupo.gerenciar`).

- **Perfil** = conjunto de permissões, marcadas por módulo. O perfil *Administrador* é fixo (todas as permissões, não pode ser mudado nem excluído); perfis do sistema não podem ser excluídos e perfil em uso não pode ser excluído.
- **Grupo** = perfis + membros. Quem está no grupo recebe as permissões dos perfis dele.
- **Exceções por usuário** (tela Editar usuário): para cada permissão, *Herdar* (vale o que vem dos perfis e grupos), *Permitir* ou *Negar*. Negar sempre vence. Ninguém consegue negar a si mesmo permissões de `acesso.*` ou `administracao.*`.
- API: `GET /permissoes`, `/perfis`, `/grupos` (CRUD), `PUT /usuarios/:id/grupos` e `PUT /usuarios/:id/permissoes`.

### Cadastro de módulos

Menu lateral → **Administração → Módulos** (permissão `administracao.modulo.gerenciar`). O administrador cria um módulo com nome, descrição, ícone, posição e liberação (para todos, ou só pelos planos escolhidos). Ao salvar, o módulo **aparece no menu** de quem tem acesso e abre uma tela própria (os recursos dele chegam nas próximas versões). Módulos de fábrica (Finanças, Saúde, Agenda...) podem ser renomeados, mas não excluídos nem desativados. Liberar ou bloquear para um usuário específico continua em *Usuários e acessos*.

**"Fixo" é escolhido por usuário.** Nenhum módulo é fixo automaticamente e o cadastro do módulo não tem mais "fixo para todos". Ao liberar o módulo para um usuário há a chave **"Fixo no menu"** (vem marcada): marcada, o módulo aparece no menu daquele usuário; desmarcada, ele continua liberado no cadastro, mas **oculto** do menu. Só o SuperUsuário altera o cadastro de módulos. O menu mostra só o que o usuário tem por liberação do plano ou liberação individual; o SuperUsuário vê todos os ativos. A **Agenda do Dia** (antes "Hoje") é sempre a primeira e a tela inicial após o login; depois os demais. Sem internet ou com a API fora do ar, o app usa os 4 módulos básicos. O menu lateral sempre inicia recolhido. Banco já criado: aplique `banco/migracoes/2026-10-29_modulos_fixos_opcionais.sql` e `banco/migracoes/2026-10-30_liberacao_fixo.sql` (mesmo comando acima, trocando o arquivo).

API: `GET|POST /modulos`, `GET|PUT|DELETE /modulos/:codigo` e `GET /meus-modulos` (os módulos do menu do usuário logado).

Banco já criado (sem apagar dados), no PowerShell: `Get-Content banco/migracoes/2026-10-26_modulo_menu.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'`

## Testar no navegador (sem emulador)

Dê dois cliques em `web.bat`. Ele sobe o banco e a API e abre o app no Chrome (porta 8081 ou a próxima livre; o endereço aparece na janela). Na web não há lembretes (notificações); o resto funciona. A API libera o navegador só para `localhost` (outras origens: `API_CORS_ORIGENS` no `.env`).

## Como rodar os testes

**Banco** (precisa do cliente `psql` e de um servidor PostgreSQL 13+ acessível; o teste cria e recria o banco `ctrl_teste`):

```bash
export PGHOST=localhost PGUSER=postgres      # ajuste conforme o seu servidor
python3 banco/testes/test_schema.py
```

**App** (depois de `flutter pub get` e do `build_runner`):

```bash
cd app && flutter test
```

**API** (o `.\testar.ps1` faz isso dentro do Docker; sem Docker, precisa de Node 20+ e de um PostgreSQL acessível):

```bash
cd api && npm install
export PGHOST=localhost PGUSER=postgres      # ajuste conforme o seu servidor
npm test
```

## Como criar o banco do servidor (sem Docker)

```bash
createdb controle_pessoal
psql -d controle_pessoal -f banco/schema.sql
```

O esquema usa segurança por linha: a API define o usuário da sessão com
`SELECT set_config('app.usuario_id', '<uuid>', true);`. No Supabase, troque `current_setting(...)` por `auth.uid()`.

## Decisões ainda em aberto

Estão no final do escopo. Duas afetam este código diretamente:

1. **Flutter ou GeneXus.** O esqueleto assume Flutter, conforme combinado.
2. **Servidor próprio ou Supabase.** Define como a sincronização será implementada.
