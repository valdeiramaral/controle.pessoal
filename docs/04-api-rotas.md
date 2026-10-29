# Rotas da API (gerado)

Gerado por `node src/cli/docs-api.js` a partir de `api/src/rotas/*.js`.

Legenda de acesso: **publica** = sem login; **login** = precisa de token; **permissao X** = login + permissao X;
**SuperUsuario** = so o SuperUsuario. Regras detalhadas em docs/03-regras-de-negocio.md.

## acesso.js

| Metodo | Caminho | Acesso |
|---|---|---|
| GET | `/permissoes` | permissao acesso.usuario.ver |
| GET | `/perfis` | permissao acesso.usuario.ver |
| GET | `/perfis/:id` | permissao acesso.usuario.ver |
| POST | `/perfis` | permissao acesso.perfil.gerenciar + SuperUsuario |
| PUT | `/perfis/:id` | permissao acesso.perfil.gerenciar + SuperUsuario |
| DELETE | `/perfis/:id` | permissao acesso.perfil.gerenciar + SuperUsuario |
| GET | `/grupos` | permissao acesso.usuario.ver |
| GET | `/grupos/:id` | permissao acesso.usuario.ver |
| POST | `/grupos` | permissao acesso.grupo.gerenciar + SuperUsuario |
| PUT | `/grupos/:id` | permissao acesso.grupo.gerenciar + SuperUsuario |
| DELETE | `/grupos/:id` | permissao acesso.grupo.gerenciar + SuperUsuario |

## auth.js

| Metodo | Caminho | Acesso |
|---|---|---|
| POST | `/cadastro` | publica |
| POST | `/login` | publica |
| GET | `/me` | login |
| PUT | `/me/preferencias` | login |
| PATCH | `/me` | login |
| PATCH | `/me/senha` | login (corpo: `senha_atual`, `senha_nova` 8–128; 204; 400 `senha_atual_incorreta` / `senha_nova_igual`) |

## modulos.js

| Metodo | Caminho | Acesso |
|---|---|---|
| GET | `/modulos` | SuperUsuario |
| GET | `/modulos/:codigo` | SuperUsuario |
| POST | `/modulos` | SuperUsuario |
| PUT | `/modulos/:codigo` | SuperUsuario |
| DELETE | `/modulos/:codigo` | SuperUsuario |
| GET | `/meus-modulos` | login |

## usuarios.js

| Metodo | Caminho | Acesso |
|---|---|---|
| GET | `/catalogo` | permissao acesso.usuario.ver |
| GET | `/usuarios` | permissao acesso.usuario.ver |
| GET | `/usuarios/:id` | permissao acesso.usuario.ver |
| POST | `/usuarios` | permissao acesso.usuario.cadastrar |
| PATCH | `/usuarios/:id` | permissao acesso.usuario.editar |
| PUT | `/usuarios/:id/plano` | permissao licencas.licenca.conceder |
| PUT | `/usuarios/:id/modulos` | permissao administracao.liberacao.gerenciar |
| DELETE | `/usuarios/:id` | permissao acesso.usuario.editar |
| PUT | `/usuarios/:id/grupos` | permissao acesso.grupo.gerenciar |
| PUT | `/usuarios/:id/permissoes` | permissao acesso.perfil.gerenciar |
| PUT | `/usuarios/:id/perfis` | permissao acesso.perfil.gerenciar |

Total: 33 rotas.

