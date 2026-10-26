<#
.SYNOPSIS
  Roda os testes do projeto: banco (esquema SQL) e app (Flutter).

.DESCRIPTION
  - Testes do banco: precisam de Python, do cliente psql e do banco no ar
    (.\iniciar.ps1 sobe o banco). Se faltar algo, sao pulados com aviso.
  - Testes do app: flutter test (precisa do codigo gerado: rode antes
    .\iniciar.ps1 -SoPreparar).
#>
$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot
try { Start-Transcript -Path (Join-Path $raiz "testar.log") -Force | Out-Null } catch { }
$falhou = $false
function Tem($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# ---- Banco
Write-Host "==> Testes do banco" -ForegroundColor Cyan
$python = $null
if (Tem "python") { $python = "python" } elseif (Tem "py") { $python = "py" }
$envFile = Join-Path $raiz ".env"
if ($python -and (Tem "psql") -and (Test-Path $envFile)) {
    $cfg = @{}
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([A-Z_]+)\s*=\s*(.*)$") { $cfg[$Matches[1]] = $Matches[2].Trim() }
    }
    $env:PGHOST = "localhost"
    $env:PGPORT = if ($cfg["POSTGRES_PORT"]) { $cfg["POSTGRES_PORT"] } else { "5432" }
    $env:PGUSER = if ($cfg["POSTGRES_USER"]) { $cfg["POSTGRES_USER"] } else { "postgres" }
    $env:PGPASSWORD = $cfg["POSTGRES_PASSWORD"]
    & $python (Join-Path $raiz "banco\testes\test_schema.py")
    if ($LASTEXITCODE -ne 0) { $falhou = $true }
} else {
    Write-Host "PULADO (opcional): este teste precisa de Python, do cliente psql e do banco no ar (.\iniciar.ps1 cria o .env e sobe o banco)." -ForegroundColor Yellow
}

# ---- App
Write-Host ""
Write-Host "==> Testes do app (Flutter)" -ForegroundColor Cyan
if (-not (Tem "flutter") -and (Test-Path "C:\src\flutter\bin\flutter.bat")) { $env:Path = "$env:Path;C:\src\flutter\bin" }
if (Tem "flutter") {
    Push-Location (Join-Path $raiz "app")
    try {
        $pronto = $true
        # O codigo do banco local (banco.g.dart) e gerado, nao fica no repositorio.
        $gerado = "lib\data\local\banco.g.dart"
        $desatualizado = $true
        if (Test-Path $gerado) {
            $t = (Get-Item $gerado).LastWriteTime
            $desatualizado = ((Get-Item "lib\data\local\tabelas.dart").LastWriteTime -gt $t) -or ((Get-Item "lib\data\local\banco.dart").LastWriteTime -gt $t)
        }
        if ($desatualizado -or -not (Test-Path ".dart_tool\package_config.json")) {
            Write-Host "Preparando o app (primeira vez): baixando pacotes e gerando o codigo do banco local..."
            flutter pub get
            if ($LASTEXITCODE -ne 0) { $pronto = $false; $falhou = $true; Write-Host "flutter pub get falhou." -ForegroundColor Red }
            if ($pronto) {
                dart run build_runner build --delete-conflicting-outputs | Out-Host
                if ($LASTEXITCODE -ne 0) { $pronto = $false; $falhou = $true; Write-Host "build_runner falhou. Veja os erros acima." -ForegroundColor Red }
                # Se o codigo gerado nao mudou, o build_runner nao reescreve o arquivo e ele
                # continuaria "desatualizado" para sempre. Atualiza a data para nao refazer a etapa.
                elseif (Test-Path $gerado) { (Get-Item $gerado).LastWriteTime = Get-Date }
            }
        }
        if ($pronto) {
            # '| Out-Host' faz a saida dos testes aparecer tambem no testar.log.
            flutter test --reporter expanded | Out-Host
            if ($LASTEXITCODE -ne 0) { $falhou = $true }
        }
    } finally { Pop-Location }
} else {
    Write-Host "PULADO: Flutter nao encontrado. Rode o instalar-requisitos.bat." -ForegroundColor Yellow
}

if ($falhou) { Write-Host "`nHouve testes com falha." -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch { }; exit 1 }
Write-Host "`nTestes concluidos." -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
