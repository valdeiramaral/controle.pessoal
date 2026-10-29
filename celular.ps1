<#
.SYNOPSIS
  Roda o app no celular Android (cabo USB com depuracao USB), falando com a API deste computador pelo Wi-Fi.

.DESCRIPTION
  Pre-requisitos (uma vez):
    - rede.bat executado como Administrador (libera a API na rede e o Firewall); depois pode fechar com Ctrl+C.
    - celular e computador no MESMO Wi-Fi (nao use rede de visitantes).
    - celular com Opcoes do desenvolvedor > Depuracao USB ligada, cabo USB, e "Permitir depuracao" aceito na tela do celular.
  O script descobre o IP do computador, confere a API, acha o celular e roda `flutter run` com API_URL.
  Com -Apk gera o arquivo app-debug.apk (para copiar e instalar no celular) em vez de rodar pelo cabo.
  A conexao e HTTP sem criptografia: use so em rede de confianca (a de casa).
#>
param([switch]$Apk, [string]$Dispositivo = "")

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot
function Falha($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

# 1) IP deste computador na rede local
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|VirtualBox|VMware' } |
    Sort-Object { if ($_.IPAddress -match '^192\.168\.') { 0 } elseif ($_.IPAddress -match '^10\.') { 1 } else { 2 } }
$ip = ($ips | Select-Object -First 1).IPAddress
if (-not $ip) { Falha "nao achei o IP da rede. Conecte o computador ao Wi-Fi/cabo." }
Write-Host "==> IP deste computador: $ip" -ForegroundColor Cyan

# 2) API liberada na rede e no ar
$arqEnv = Join-Path $raiz ".env"
if (-not (Test-Path $arqEnv)) { Falha "falta o .env. Rode o iniciar.bat antes." }
if (-not (Select-String -Path $arqEnv -Pattern '^\s*API_BIND\s*=\s*0\.0\.0\.0' -Quiet)) {
    Falha "a API ainda nao esta liberada na rede. Rode o rede.bat (clique direito > Executar como administrador), feche com Ctrl+C e rode este de novo."
}
$portaApi = 3000
$m = Select-String -Path $arqEnv -Pattern '^\s*API_PORTA\s*=\s*(\d+)' | Select-Object -First 1
if ($m) { $portaApi = [int]$m.Matches[0].Groups[1].Value }
try { Invoke-RestMethod "http://localhost:$portaApi/saude" -TimeoutSec 5 | Out-Null }
catch { Falha "a API nao respondeu em http://localhost:$portaApi. Rode o iniciar.bat." }
$url = "http://${ip}:$portaApi"
Write-Host "==> API: $url (no celular, abrir $url/saude no navegador deve mostrar uma resposta)" -ForegroundColor Cyan

Push-Location (Join-Path $raiz "app")
try {
    if ($Apk) {
        Write-Host "==> Gerando o APK (debug)..." -ForegroundColor Cyan
        flutter build apk --debug "--dart-define=API_URL=$url"
        if ($LASTEXITCODE -ne 0) { Falha "o build do APK falhou." }
        $arq = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-debug.apk"
        Write-Host "==> Pronto: $arq" -ForegroundColor Green
        Write-Host "    Copie para o celular (cabo, Drive, e-mail) e abra para instalar (permita 'fontes desconhecidas')."
        exit 0
    }

    # 3) Celular conectado
    $saida = flutter devices --machine
    $lista = @($saida | ConvertFrom-Json | Where-Object { $_.targetPlatform -like 'android*' -and -not $_.emulator })
    if ($Dispositivo) { $lista = @($lista | Where-Object { $_.id -eq $Dispositivo }) }
    if ($lista.Count -eq 0) {
        Falha "nao achei o celular. Ligue a Depuracao USB, conecte o cabo, aceite 'Permitir depuracao' no celular e rode 'flutter devices' para conferir."
    }
    $cel = $lista[0]
    Write-Host "==> Celular: $($cel.name) ($($cel.id))" -ForegroundColor Cyan

    # 4) Instala e abre (r = recarrega, q = sai)
    flutter run -d $cel.id "--dart-define=API_URL=$url"
}
finally { Pop-Location }
