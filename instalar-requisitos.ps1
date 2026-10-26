<#
.SYNOPSIS
  Instala tudo o que o app precisa para rodar no Windows.

.DESCRIPTION
  Instala e configura, pulando o que ja existir:
    1. Git
    2. Flutter (em C:\src\flutter) e o PATH
    3. Modo desenvolvedor do Windows (exigido pelos plugins do Flutter)
    4. Android Studio, Android SDK, licencas e (opcional) um emulador
    5. Docker Desktop (para o banco PostgreSQL)
  Pede permissao de administrador (aceite a janela do Windows).
  Grava um registro em instalar-requisitos.log, nesta pasta.

.EXAMPLE
  .\instalar-requisitos.ps1                 # instala tudo
  .\instalar-requisitos.ps1 -SemEmulador    # nao baixa nem cria o emulador Android
  .\instalar-requisitos.ps1 -SemDocker      # nao instala o Docker Desktop
#>
param(
    [switch]$SemDocker,
    [switch]$SemEmulador
)

$ErrorActionPreference = "Continue"
$pastaScript = $PSScriptRoot

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ------------------------------------------------ Pede administrador
if (-not (Test-Admin)) {
    Write-Host "Pedindo permissao de administrador. Aceite a janela do Windows que vai abrir..." -ForegroundColor Yellow
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SemDocker) { $argumentos += " -SemDocker" }
    if ($SemEmulador) { $argumentos += " -SemEmulador" }
    Start-Process powershell -Verb RunAs -ArgumentList $argumentos -Wait
    exit
}

Start-Transcript -Path (Join-Path $pastaScript "instalar-requisitos.log") -Force | Out-Null

$avisos = New-Object System.Collections.Generic.List[string]
function Passo($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "    OK: $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "    AVISO: $t" -ForegroundColor Yellow; $avisos.Add($t) }
function Tem($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Atualizar-Path {
    $m = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $u = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$m;$u"
}

function Adicionar-PathUsuario($pasta) {
    $atual = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($null -eq $atual) { $atual = "" }
    $itens = @($atual.Split(";") | Where-Object { $_ -ne "" })
    if ($itens -notcontains $pasta) {
        [Environment]::SetEnvironmentVariable("Path", (($itens + $pasta) -join ";"), "User")
    }
    if (@($env:Path.Split(";")) -notcontains $pasta) { $env:Path = "$env:Path;$pasta" }
}

function Winget-Instalar($id, $nome) {
    Write-Host "    Instalando $nome (pode demorar)..."
    winget install -e --id $id --silent --accept-package-agreements --accept-source-agreements | Out-Host
    # 0 = instalado; -1978335189 = ja instalado / sem atualizacao
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Aviso "winget retornou codigo $LASTEXITCODE ao instalar $nome."
        return $false
    }
    Atualizar-Path
    return $true
}

try {
    # ------------------------------------------------ 0. winget
    Passo "Conferindo o winget (instalador de programas do Windows)"
    if (-not (Tem "winget")) {
        Write-Host "ERRO: winget nao encontrado. Instale 'Instalador de Aplicativo' na Microsoft Store e rode de novo." -ForegroundColor Red
        return
    }
    Ok "winget encontrado"

    # ------------------------------------------------ 1. Git
    Passo "Git"
    if (Tem "git") { Ok "ja instalado" } else { Winget-Instalar "Git.Git" "Git" | Out-Null }
    if (-not (Tem "git")) {
        $gitExe = "C:\Program Files\Git\cmd"
        if (Test-Path $gitExe) { $env:Path = "$env:Path;$gitExe" }
    }
    if (-not (Tem "git")) { Write-Host "ERRO: Git nao ficou disponivel. Abra um novo terminal e rode de novo." -ForegroundColor Red; return }

    # ------------------------------------------------ 2. Flutter
    Passo "Flutter"
    $flutterRaiz = "C:\src\flutter"
    $flutterBin = Join-Path $flutterRaiz "bin"
    if (-not (Tem "flutter") -and -not (Test-Path (Join-Path $flutterBin "flutter.bat"))) {
        New-Item -ItemType Directory -Force -Path "C:\src" | Out-Null
        Write-Host "    Baixando o Flutter (canal stable) para $flutterRaiz ..."
        git clone --depth 1 -b stable https://github.com/flutter/flutter.git $flutterRaiz
        if ($LASTEXITCODE -ne 0) { Write-Host "ERRO: nao foi possivel baixar o Flutter. Veja a conexao com a internet." -ForegroundColor Red; return }
    }
    if (Test-Path (Join-Path $flutterBin "flutter.bat")) {
        # Evita o aviso "dubious ownership" do Git quando o Flutter roda sem administrador.
        git config --global --add safe.directory "C:/src/flutter"
        Adicionar-PathUsuario $flutterBin
    }
    if (-not (Tem "flutter")) { Write-Host "ERRO: Flutter nao ficou disponivel." -ForegroundColor Red; return }
    Write-Host "    Preparando o Flutter (baixa o Dart na primeira vez)..."
    flutter --version
    flutter config --no-analytics | Out-Null
    Ok "Flutter pronto"

    # ------------------------------------------------ 3. Modo desenvolvedor
    Passo "Modo desenvolvedor do Windows (necessario para os plugins do Flutter)"
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "ativado" } else { Aviso "Nao foi possivel ativar o modo desenvolvedor. Ative em Configuracoes > Para desenvolvedores." }

    # ------------------------------------------------ 4. Android
    Passo "Android Studio e Android SDK"
    $studioDir = "C:\Program Files\Android\Android Studio"
    if (Test-Path (Join-Path $studioDir "bin\studio64.exe")) { Ok "Android Studio ja instalado" }
    else { Winget-Instalar "Google.AndroidStudio" "Android Studio" | Out-Null }

    $sdk = $env:ANDROID_HOME
    if (-not $sdk -or -not (Test-Path $sdk)) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null

    # Java para o sdkmanager: usa o que vem com o Android Studio (JBR).
    $jbr = Join-Path $studioDir "jbr"
    if (Test-Path (Join-Path $jbr "bin\java.exe")) {
        $env:JAVA_HOME = $jbr
    } elseif (-not (Tem "java")) {
        Winget-Instalar "Microsoft.OpenJDK.17" "JDK 17" | Out-Null
        $jdk = Get-ChildItem "C:\Program Files\Microsoft" -Directory -Filter "jdk-17*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
    }

    $sdkmanager = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path $sdkmanager)) {
        Write-Host "    Baixando as ferramentas de linha de comando do Android..."
        $zip = Join-Path $env:TEMP "cmdline-tools.zip"
        $tmp = Join-Path $env:TEMP "cmdline-tools-extraido"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Force -Path (Join-Path $sdk "cmdline-tools") | Out-Null
        $destino = Join-Path $sdk "cmdline-tools\latest"
        if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
        Move-Item (Join-Path $tmp "cmdline-tools") $destino
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $sdkmanager) {
        Write-Host "    Aceitando as licencas do Android..."
        $sim = 1..80 | ForEach-Object { "y" }
        $sim | & $sdkmanager "--sdk_root=$sdk" --licenses | Out-Null

        $pacotes = @("platform-tools", "platforms;android-35", "build-tools;35.0.0")
        if (-not $SemEmulador) { $pacotes += @("emulator", "system-images;android-35;google_apis;x86_64") }
        Write-Host "    Instalando pacotes do Android SDK (pode demorar bastante)..."
        & $sdkmanager "--sdk_root=$sdk" @pacotes
        if ($LASTEXITCODE -ne 0) { Aviso "O sdkmanager terminou com codigo $LASTEXITCODE. Veja a mensagem acima." }

        [Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
        $env:ANDROID_HOME = $sdk
        Adicionar-PathUsuario (Join-Path $sdk "platform-tools")
        flutter config --android-sdk $sdk | Out-Null
        if (Test-Path (Join-Path $jbr "bin\java.exe")) { flutter config --jdk-dir $jbr | Out-Null }
        Ok "Android SDK configurado em $sdk"
    } else {
        Aviso "sdkmanager nao encontrado. Abra o Android Studio uma vez para concluir a instalacao do SDK."
    }

    # ------------------------------------------------ Emulador
    if (-not $SemEmulador -and (Test-Path $sdkmanager)) {
        Passo "Emulador Android (controle_pessoal)"
        $feat = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction SilentlyContinue
        if ($feat -and $feat.State -ne "Enabled") {
            Write-Host "    Ativando a Plataforma de Hipervisor do Windows (acelera o emulador)..."
            Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Aviso "A Plataforma de Hipervisor foi ativada: reinicie o Windows antes de abrir o emulador."
        }
        $avdmanager = Join-Path $sdk "cmdline-tools\latest\bin\avdmanager.bat"
        if (Test-Path $avdmanager) {
            "no" | & $avdmanager create avd --force -n controle_pessoal -k "system-images;android-35;google_apis;x86_64" -d pixel_7 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "emulador 'controle_pessoal' criado" } else { Aviso "Nao foi possivel criar o emulador. Crie um pelo Android Studio (Device Manager)." }
        }
    }

    Write-Host "    Aceitando licencas pelo Flutter..."
    $sim2 = 1..80 | ForEach-Object { "y" }
    $sim2 | flutter doctor --android-licenses | Out-Null

    # ------------------------------------------------ 5. Docker Desktop
    Passo "Docker Desktop (banco PostgreSQL)"
    if ($SemDocker) { Write-Host "    Pulado (-SemDocker)." }
    elseif (Tem "docker") { Ok "ja instalado" }
    elseif (Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe") { Ok "ja instalado (abra o Docker Desktop)" }
    else {
        if (Winget-Instalar "Docker.DockerDesktop" "Docker Desktop") {
            Aviso "Docker Desktop instalado: REINICIE o Windows e abra o Docker Desktop uma vez (aceite os termos) antes de usar o banco."
        }
    }

    # ------------------------------------------------ Resumo
    Passo "Conferencia final (flutter doctor)"
    flutter doctor -v

    Write-Host ""
    Write-Host "================ RESUMO ================" -ForegroundColor Cyan
    if ($avisos.Count -eq 0) { Write-Host "Tudo instalado sem avisos." -ForegroundColor Green }
    else { Write-Host "Atencao:" -ForegroundColor Yellow; $avisos | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow } }
    Write-Host ""
    Write-Host "Proximo passo: feche este terminal, abra um NOVO e rode  .\iniciar.ps1  (ou duplo clique em iniciar.bat)."
    Write-Host "Observacao: o iOS so compila em um Mac. Neste PC o app roda no Android."
}
catch {
    Write-Host "ERRO inesperado: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Stop-Transcript | Out-Null
    Write-Host ""
    Read-Host "Pressione Enter para fechar"
}
