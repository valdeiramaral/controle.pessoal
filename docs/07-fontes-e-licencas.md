# Fontes e licenças

## Documentos do projeto
`escopo-app-controle-pessoal.md`, `contrato-sincronizacao.md`, `cronograma-desenvolvimento.md/.xlsx`, `fontes/diagrama-arquitetura.jsx`, `banco/schema.sql`.

## Bibliotecas (versões conforme `api/package.json` e `app/pubspec.yaml`)
| Componente | Uso | Licença (verificar no pacote) |
|---|---|---|
| Fastify ^5, @fastify/rate-limit | servidor HTTP | MIT |
| pg | cliente PostgreSQL | MIT |
| @node-rs/argon2 | hash de senha | MIT |
| jose ^6 | JWT | MIT |
| PostgreSQL 16 | banco | PostgreSQL License |
| Node.js 22, Docker | runtime | MIT / Apache-2.0 |
| Flutter / Dart | app | BSD-3-Clause |
| flutter_riverpod ^2.5.1 | estado | MIT |
| drift ^2.20, drift_flutter, drift_dev | SQLite local | MIT |
| uuid, timezone, intl, http | utilitários | MIT / BSD-3 |
| flutter_local_notifications ^17 | lembretes | BSD-3-Clause |
| flutter_secure_storage ^9 | token seguro | BSD-3-Clause |

## Ícones
Material Icons (Google) — Apache License 2.0, 91 ícones em `core/icones_modulo.dart`.

Licenças exatas: conferir `LICENSE` de cada pacote (`npm ls`, `flutter pub deps`).
- Logos dos bancos: ver docs/logos-bancos-aviso.md (marcas das instituicoes, uso nominativo).
