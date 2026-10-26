# Rotina padrao: 1) backup local completo em backups\  2) commit pendente  3) envio ao GitHub.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& "$PSScriptRoot\backup.ps1"
if (git status --porcelain) { git add -A; git commit -m ("Atualizacao " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) }
if (-not (git remote get-url origin 2>$null)) { git remote add origin https://github.com/valdeiramaral/controle.pessoal.git }
git push -u origin main
Write-Host 'Publicado em https://github.com/valdeiramaral/controle.pessoal' -ForegroundColor Green
