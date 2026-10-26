# Projeto IA Pessoal - App de controle pessoal

App para controlar finanças, saúde e compromissos no Android e no iOS.

## Conteúdo da pasta

| Caminho | O que é |
| --- | --- |
| `escopo-app-controle-pessoal.md` | Escopo completo: módulos, requisitos, stack, modelo de dados, roadmap, riscos |
| `banco/schema.sql` | Esquema PostgreSQL do servidor: 14 tabelas, índices de sincronização, triggers e segurança por linha |
| `banco/testes/test_schema.py` | 108 testes do esquema (restrições, triggers, ligações entre módulos, isolamento entre usuários, integridade entre usuários) |
| `instalar-requisitos.bat` | Instala Git, Flutter, Android SDK/emulador e Docker Desktop (uma vez) |
| `iniciar.ps1`, `parar.ps1`, `testar.ps1` (e `.bat` de duplo clique) | Iniciam, param e testam tudo (ver Início rápido) |
| `docker-compose.yml`, `.env.example`, `banco/init/` | Banco PostgreSQL local no Docker, criado com o schema e o papel `app_api` |
| `app/` | Esqueleto do app Flutter (banco local, 4 telas, lembretes locais, sincronização em esboço) |
| `contrato-sincronizacao.md` | Contrato entre app e API: ids, tipos, ordem das tabelas, protocolo e regra de conflito |
| `fontes/diagrama-arquitetura.jsx` | Fonte do diagrama de arquitetura do documento de escopo |

## Estado atual (fase 0, fundação)

**Banco: testado.** O `schema.sql` foi carregado em um PostgreSQL 16 real e passa nos 108 testes de `banco/testes/test_schema.py` (rodado de novo em 20/10/2026, depois das correções da revisão: cursor de sincronização com hora real, e-mail reaproveitável após exclusão, referências entre usuários e lembretes validadas, fuso e moeda validados). Os testes acharam e corrigiram dois defeitos na segurança por linha (erro em conexão reaproveitada e tabela `usuario` sem isolamento).

**App Flutter: compila e roda os testes no seu PC.** Os testes de `app/test/` (banco local, saldo, valores digitados e id de notificação) foram escritos na revisão de 20/10/2026 e ainda precisam ser rodados com `.\testar.ps1`. Falta abrir o app no emulador.

O que o esqueleto já faz:

- **Hoje:** compromissos do dia, contas a pagar nos próximos 7 dias e remédios.
- **Finanças:** lançamentos (receita e despesa), saldo dos itens pagos, marcar como pago, excluir deslizando.
- **Saúde:** medicamentos com horários e notificação diária no aparelho.
- **Agenda:** compromissos com lembrete 30 minutos antes.
- Banco local com as 14 entidades (valores em centavos, UUID, exclusão lógica).
- Dois testes do banco em `app/test/`.

O que falta (fases seguintes do roadmap):

- Banco local criptografado (SQLCipher) e biometria.
- Sincronização com o servidor: `app/lib/data/sync/` é só o esboço, sem rede.
- Login, cartão de crédito, orçamento, metas, relatórios, indicadores de saúde, documentos.
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

**Importante:** hoje o app guarda tudo no banco local do próprio aparelho. O banco PostgreSQL do Docker já sobe e está pronto, mas nada no app se conecta a ele ainda, porque a API e a sincronização não existem (`app/lib/data/sync/` é só um esboço). Quando existir uma API, ela entra como um novo serviço no `docker-compose.yml` e uma nova etapa no `iniciar.ps1`.

**O que foi e o que não foi testado:** o `docker-compose.yml` foi validado (`docker compose config`) e a configuração de primeira subida do banco foi simulada em um PostgreSQL real. Os scripts `.ps1` **não foram executados** (não havia Windows, PowerShell, Flutter nem Docker em funcionamento no ambiente onde foram escritos). Se algum passo falhar, a mensagem de erro indica qual; me mande o texto que eu corrijo.

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
