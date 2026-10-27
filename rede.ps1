<#
.SYNOPSIS
  Deixa o sistema acessivel por outros computadores da MESMA rede (Wi-Fi/cabo de casa).

.DESCRIPTION
  1. Descobre o IP deste computador na rede.
  2. Libera a API na rede (API_BIND) e autoriza o app web dessa origem (API_CORS_ORIGENS) no .env.
  3. Cria regras no Firewall do Windows (rede Privada) para as portas da API e do app.
  4. Compila o app web apontando para a API deste computador e o serve na porta 8090.
  No outro notebook basta abrir o endereco mostrado no navegador. Nao precisa instalar nada.
  Execute como Administrador (clique direito > Executar como administrador). Tecle Ctrl+C para parar.
  Use so em rede de confianca: a conexao e HTTP, sem criptografia.
#>
param([int]$PortaApp = 8090)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "ERRO: execute este arquivo como Administrador (clique direito > Executar como administrador)." -ForegroundColor Red
    exit 1
}

# 1) IP na rede local (ignora loopback, WSL/Docker e enderecos 169.254).
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|VirtualBox|VMware' } |
    Sort-Object { if ($_.IPAddress -match '^192\.168\.') { 0 } elseif ($_.IPAddress -match '^10\.') { 1 } else { 2 } }
$ip = ($ips | Select-Object -First 1).IPAddress
if (-not $ip) { Write-Host "ERRO: nao achei o IP da rede. Conecte-se ao Wi-Fi/cabo." -ForegroundColor Red; exit 1 }
Write-Host "==> IP deste computador: $ip" -ForegroundColor Cyan

# 2) .env
$arqEnv = Join-Path $raiz ".env"
if (-not (Test-Path $arqEnv)) { Write-Host "ERRO: falta o .env. Rode o iniciar.bat antes." -ForegroundColor Red; exit 1 }
function Definir-Env($chave, $valor) {
    $linhas = @(Get-Content $arqEnv)
    $achou = $false
    $novas = foreach ($l in $linhas) {
        if ($l -match "^\s*$chave\s*=") { $achou = $true; "$chave=$valor" } else { $l }
    }
    if (-not $achou) { $novas = @($novas) + "$chave=$valor" }
    Set-Content -Path $arqEnv -Value $novas -Encoding UTF8
}
$portaApi = 3000
$m = Select-String -Path $arqEnv -Pattern '^\s*API_PORTA\s*=\s*(\d+)' | Select-Object -First 1
if ($m) { $portaApi = [int]$m.Matches[0].Groups[1].Value }
Definir-Env "API_BIND" "0.0.0.0"
Definir-Env "API_CORS_ORIGENS" "http://${ip}:$PortaApp"

Write-Host "==> Reiniciando a API para aceitar a rede" -ForegroundColor Cyan
Push-Location $raiz
docker compose up -d api
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO ao subir a API. Rode o iniciar.bat e tente de novo." -ForegroundColor Red; Pop-Location; exit 1 }
Pop-Location

# 3) Firewall (so rede Privada)
foreach ($p in @($portaApi, $PortaApp)) {
    $nome = "Controle Pessoal $p"
    if (-not (Get-NetFirewallRule -DisplayName $nome -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $nome -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Private | Out-Null
    }
}
Write-Host "==> Firewall: portas $portaApi e $PortaApp liberadas na rede Privada" -ForegroundColor Cyan

# 4) Compila o app web e serve
Push-Location (Join-Path $raiz "app")
try {
    dart run build_runner build --delete-conflicting-outputs
    if ($LASTEXITCODE -ne 0) { Write-Host "build_runner falhou." -ForegroundColor Red; exit 1 }
    flutter build web --release "--dart-define=API_URL=http://${ip}:$portaApi"
    if ($LASTEXITCODE -ne 0) { Write-Host "flutter build web falhou." -ForegroundColor Red; exit 1 }
} finally { Pop-Location }

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " No outro notebook, abra no navegador:  http://${ip}:$PortaApp" -ForegroundColor Green
Write-Host " (mesma rede Wi-Fi. Deixe esta janela aberta; Ctrl+C para parar)" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
node (Join-Path $raiz "servir-web.js") $PortaApp
