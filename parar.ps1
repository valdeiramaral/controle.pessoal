<#
.SYNOPSIS
  Para o banco PostgreSQL do app.
.EXAMPLE
  .\parar.ps1                # para o banco; os dados continuam guardados
  .\parar.ps1 -ApagarDados   # para e APAGA todos os dados do banco local
#>
param([switch]$ApagarDados)

$ErrorActionPreference = "Stop"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker nao encontrado; nada para parar." -ForegroundColor Yellow
    exit 0
}
Push-Location $PSScriptRoot
try {
    if ($ApagarDados) {
        $r = Read-Host "Isto apaga TODOS os dados do banco local. Digite SIM para confirmar"
        if ($r -ne "SIM") { Write-Host "Cancelado."; exit 0 }
        docker compose down -v
    } else {
        docker compose down
    }
} finally { Pop-Location }
