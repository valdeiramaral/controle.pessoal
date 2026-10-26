# Operação e backup

## Rotina
- Subir tudo: `iniciar.bat`; só banco+API: `preparar.bat`; web: `web.bat`; parar: `parar.bat`; testes Flutter: `testar.bat`.
- Testes da API: `cd api && npm test` (exige PostgreSQL).
- Reconstruir API: `$env:DOCKER_BUILDKIT="0"; docker build -t controle-pessoal-api:latest ./api; docker compose up -d api`
- Migração: `Get-Content banco/migracoes/<arquivo>.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'`
- SuperUsuário: `docker compose exec -e SUPER_EMAIL=... -e SUPER_SENHA='...' api node src/cli/superusuario.js`

## Documentação gerada
```
docker compose exec -T api node src/cli/docs-api.js   > docs/04-api-rotas.md
docker compose exec -T api node src/cli/docs-banco.js > docs/05-banco-objetos.md
```
(o serviço da API precisa das variáveis `PG*` do compose; se faltar, use `npm run docs:banco` com `PGHOST` etc.)

## Backup completo
Rotina padrão (backup local + GitHub): `publicar.bat`. Só backup: `backup.bat`. na raiz. Cria `backups/<data-hora>/` com:
- `codigo.bundle` (histórico git completo) e `codigo.zip` (fontes sem node_modules/build);
- `banco.dump` (pg_dump formato custom) e `banco.sql` (SQL puro);
- `docs.zip`, `SHA256SUMS.txt` e `manifesto.txt`.

## Restauração
```
docker compose up -d db
Get-Content backups\<pasta>\banco.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
# ou: docker compose exec -T db pg_restore -U <usuario> -d <banco> --clean --if-exists < banco.dump
git clone backups\<pasta>\codigo.bundle projeto-restaurado
```
Guarde uma cópia da pasta `backups/` fora do computador (nuvem/HD externo). O arquivo `.env` **não** entra no backup de código por conter segredos; guarde-o à parte.
