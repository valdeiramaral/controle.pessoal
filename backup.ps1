# Backup completo: codigo (git bundle + zip), banco (pg_dump custom + SQL), docs, checksums e manifesto.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$carimbo = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$dest = Join-Path $PSScriptRoot "backups\$carimbo"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$manifesto = @("Backup $carimbo")

# 1) Codigo: historico git completo
git bundle create "$dest\codigo.bundle" --all
$manifesto += "git: " + (git rev-parse --short HEAD) + " (" + (git rev-list --count HEAD) + " commits)"
if (git status --porcelain) { $manifesto += "AVISO: ha alteracoes nao commitadas (entram no codigo.zip, nao no bundle)" }

# 2) Codigo: zip dos fontes (sem dependencias/build/segredos)
$tmp = Join-Path $env:TEMP "bkp_$carimbo"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
robocopy $PSScriptRoot $tmp /E /XD node_modules build .dart_tool .git backups .gradle .idea /XF .env *.log '~$*' /NFL /NDL /NJH /NJS /NP | Out-Null
Compress-Archive -Path "$tmp\*" -DestinationPath "$dest\codigo.zip" -Force
Remove-Item -Recurse -Force $tmp
Compress-Archive -Path "$PSScriptRoot\docs\*" -DestinationPath "$dest\docs.zip" -Force

# 3) Banco de dados (precisa do Docker e do servico db no ar)
try {
  docker compose ps db *> $null
  docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' | Set-Content -Encoding Byte "$dest\banco.dump"
  docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' | Out-File -Encoding utf8 "$dest\banco.sql"
  $manifesto += "banco: dump custom + SQL gerados"
} catch {
  $manifesto += "AVISO: banco NAO salvo ($($_.Exception.Message)). Suba o Docker (preparar.bat) e rode de novo."
  Write-Warning $manifesto[-1]
}

# 4) Checksums e manifesto
Get-ChildItem $dest -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Name
} | Set-Content "$dest\SHA256SUMS.txt"
$manifesto | Set-Content "$dest\manifesto.txt"
Write-Host "Backup concluido em $dest" -ForegroundColor Green
Get-ChildItem $dest | Select-Object Name, @{n='KB';e={[int]($_.Length/1KB)}}
