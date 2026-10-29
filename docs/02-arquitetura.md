# Arquitetura

```
 App Flutter (Android/iOS/Web)            API Fastify 5 (Node 22)          PostgreSQL 16 (Docker)
 ┌───────────────────────────┐  HTTPS/JWT ┌────────────────────┐  pool   ┌──────────────────────┐
 │ Riverpod + Drift (SQLite) │──────────▶│ rotas/ auth, usuarios│────────▶│ schema controle, RLS │
 │ 1 arquivo de banco/usuário│           │ acesso, modulos      │ app.usuario_id │ funções SECURITY DEFINER│
 └───────────────────────────┘           └────────────────────┘          └──────────────────────┘
```

## Camadas
- **App** (`app/lib`): `core/` (tema, aparência, ícones), `data/api` (cliente HTTP), `data/local` (Drift), `features/*` (auth, nav, hoje, finanças, saúde, agenda, admin, aparência). Estado com Riverpod 2.
- **API** (`api/src`): `app.js` (plugins, `autenticar`, `exigir(perm)`, `ehSuperusuario`, `exigirSuper`), `rotas/*`, `admin.js`, `cli/*`.
- **Banco** (`banco/schema.sql`, `banco/migracoes/`): esquema `controle`, papel `app_api` sem BYPASSRLS.

## Fluxo de login
1. App sempre abre deslogado (só o e-mail lembrado é guardado). 2. `POST /login` → JWT. 3. `GET /me` traz permissões, superusuário e preferências. 4. App abre o banco local **do usuário** e a casca com menu (`/meus-modulos`).

## Isolamento
- **Servidor:** `comUsuario(pool, id, fn, {admin})` define `app.usuario_id` na transação; políticas RLS filtram por `usuario_id`. Modo admin (`app.admin='on'`) só para o SuperUsuário.
- **Dispositivo:** um arquivo Drift por usuário (`Banco({usuarioId})`); trocar de usuário troca de banco.

## Sincronização
Ver `contrato-sincronizacao.md` (seção 9, versão 2): UUID gerado no aparelho, cada registro vai como JSON para `sincronizacao_registro` via `POST /sincronizar`, a última edição vence, exclusão lógica (`excluido_em`). O cofre de senhas não sincroniza.

## Segurança
argon2id nas senhas; JWT (jose); rate-limit; validação ajv; credenciais de teste apenas em `.env` (ignorado pelo git).
