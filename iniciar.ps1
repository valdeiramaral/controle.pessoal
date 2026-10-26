<#
.SYNOPSIS
  Prepara e inicia tudo o que o app de controle pessoal precisa.

.DESCRIPTION
  1. Confere os programas (Flutter e Docker).
  2. Cria o arquivo .env com senhas aleatorias (so na primeira vez).
  3. Sobe o banco PostgreSQL no Docker e espera ele ficar pronto.
  4. Na primeira vez, gera as pastas android/ e ios/ do app e ajusta as
     permissoes de lembretes do Android.
  5. Baixa os pacotes, gera o codigo do banco local e abre o app.

.EXAMPLE
  .\iniciar.ps1                              # banco + app (Flutter pergunta o dispositivo)
  .\iniciar.ps1 -Dispositivo emulator-5554   # escolhe o dispositivo
  .\iniciar.ps1 -SemBanco                    # so o app (o app usa banco local no aparelho)
  .\iniciar.ps1 -SoPreparar                  # prepara tudo, mas nao abre o app
  .\iniciar.ps1 -ListarDispositivos          # mostra emuladores e aparelhos
#>
param(
    [string]$Dispositivo = "",
    [switch]$SemBanco,
    [switch]$SoPreparar,
    [switch]$ListarDispositivos
)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot
$app = Join-Path $raiz "app"

function Passo($texto) { Write-Host ""; Write-Host "==> $texto" -ForegroundColor Cyan }
function Falha($texto) { Write-Host "ERRO: $texto" -ForegroundColor Red; exit 1 }
function Tem($comando) { return [bool](Get-Command $comando -ErrorAction SilentlyContinue) }
function Conferir($texto) { if ($LASTEXITCODE -ne 0) { Falha $texto } }

function Gravar-Texto($caminho, $texto) {
    [System.IO.File]::WriteAllText($caminho, $texto, (New-Object System.Text.UTF8Encoding($false)))
}

function Senha-Aleatoria {
    $letras = [char[]]"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return -join (1..24 | ForEach-Object { $letras | Get-Random })
}

# Permissoes e receivers que o pacote flutter_local_notifications exige no Android.
function Ajustar-Android {
    $manifest = Join-Path $app "android\app\src\main\AndroidManifest.xml"
    if (Test-Path $manifest) {
        $xml = Get-Content $manifest -Raw
        $mudou = $false
        if ($xml -notmatch "POST_NOTIFICATIONS") {
            $perm = "`r`n    <uses-permission android:name=`"android.permission.POST_NOTIFICATIONS`"/>" +
                    "`r`n    <uses-permission android:name=`"android.permission.SCHEDULE_EXACT_ALARM`"/>" +
                    "`r`n    <uses-permission android:name=`"android.permission.RECEIVE_BOOT_COMPLETED`"/>"
            $xml = [regex]::Replace($xml, "(<manifest[^>]*>)", { param($m) $m.Groups[1].Value + $perm }, 1)
            $mudou = $true
        }
        if ($xml -notmatch "ScheduledNotificationReceiver") {
            $rec = "    <receiver android:exported=`"false`" android:name=`"com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver`" />`r`n" +
                   "    <receiver android:exported=`"false`" android:name=`"com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver`">`r`n" +
                   "      <intent-filter>`r`n" +
                   "        <action android:name=`"android.intent.action.BOOT_COMPLETED`"/>`r`n" +
                   "        <action android:name=`"android.intent.action.MY_PACKAGE_REPLACED`"/>`r`n" +
                   "      </intent-filter>`r`n" +
                   "    </receiver>`r`n    "
            $xml = $xml.Replace("</application>", $rec + "</application>")
            $mudou = $true
        }
        if ($mudou) { Gravar-Texto $manifest $xml; Write-Host "AndroidManifest.xml ajustado (permissoes e receivers de lembretes)." }
    }

    # Core library desugaring (exigido pelo flutter_local_notifications).
    foreach ($nome in "build.gradle.kts", "build.gradle") {
        $gradle = Join-Path $app "android\app\$nome"
        if (-not (Test-Path $gradle)) { continue }
        $txt = Get-Content $gradle -Raw
        if ($txt -match "desugar_jdk_libs") { break }
        if ($nome -like "*.kts") {
            $txt = [regex]::Replace($txt, "(compileOptions\s*\{)", { param($m) $m.Groups[1].Value + "`r`n        isCoreLibraryDesugaringEnabled = true" }, 1)
            $txt += "`r`ndependencies {`r`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`r`n}`r`n"
        } else {
            $txt = [regex]::Replace($txt, "(compileOptions\s*\{)", { param($m) $m.Groups[1].Value + "`r`n        coreLibraryDesugaringEnabled true" }, 1)
            $txt += "`r`ndependencies {`r`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`r`n}`r`n"
        }
        Gravar-Texto $gradle $txt
        Write-Host "$nome ajustado (core library desugaring)."
        break
    }
}

# ---------------------------------------------------------------- 1. Programas
Passo "Conferindo os programas necessarios"
if (-not (Tem "flutter")) {
    # Instalacao padrao do instalar-requisitos.ps1 (o PATH pode ainda nao ter sido atualizado neste terminal)
    $flutterBin = "C:\src\flutter\bin"
    if (Test-Path (Join-Path $flutterBin "flutter.bat")) { $env:Path = "$env:Path;$flutterBin" }
}
if (-not (Tem "flutter")) { Falha "Flutter nao encontrado. Rode primeiro o instalar-requisitos.bat (duplo clique) e depois abra um novo terminal." }
if ($ListarDispositivos) { flutter devices; exit 0 }
if (-not $SemBanco -and -not (Tem "docker")) { Falha "Docker nao encontrado. Instale o Docker Desktop ou rode com -SemBanco." }
Write-Host "OK"

# ---------------------------------------------------------------- 2. .env
$arquivoEnv = Join-Path $raiz ".env"
if (-not (Test-Path $arquivoEnv)) {
    Passo "Criando o arquivo .env com senhas aleatorias"
    $modelo = Get-Content (Join-Path $raiz ".env.example") -Raw
    $modelo = $modelo.Replace("troque-esta-senha-da-api", (Senha-Aleatoria))
    $modelo = $modelo.Replace("troque-esta-senha", (Senha-Aleatoria))
    Gravar-Texto $arquivoEnv $modelo
    Write-Host ".env criado. Guarde esse arquivo: ele tem as senhas do banco."
}

# ---------------------------------------------------------------- 3. Banco
if (-not $SemBanco) {
    Passo "Subindo o banco PostgreSQL (Docker)"
    Push-Location $raiz
    try {
        docker compose up -d --wait db
        $bancoOk = ($LASTEXITCODE -eq 0)
    } finally { Pop-Location }
    if ($bancoOk) {
        Write-Host "Banco pronto em localhost (porta do .env, padrao 5432)."
    } else {
        Write-Host "AVISO: o banco PostgreSQL nao subiu (o Docker Desktop esta aberto?)." -ForegroundColor Yellow
        Write-Host "O app ainda usa so o banco local do aparelho, entao vou continuar sem ele." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- 4. App
Push-Location $app
try {
    if (-not (Test-Path "android") -or -not (Test-Path "ios")) {
        Passo "Gerando as pastas android/ e ios/ (so na primeira vez)"
        flutter create . --org br.com.controlepessoal --project-name controle_pessoal
        Conferir "O comando flutter create falhou."
    }
    Passo "Ajustando o Android para os lembretes"
    Ajustar-Android

    Passo "Baixando os pacotes (flutter pub get)"
    flutter pub get
    Conferir "flutter pub get falhou. Confira a conexao com a internet."

    Passo "Gerando o codigo do banco local (build_runner)"
    dart run build_runner build --delete-conflicting-outputs
    Conferir "build_runner falhou. Veja a mensagem acima."

    if ($SoPreparar) {
        Passo "Tudo preparado. Para abrir o app: .\iniciar.ps1"
        exit 0
    }

    Passo "Abrindo o app"
    if ($Dispositivo -ne "") { flutter run -d $Dispositivo } else { flutter run }
} finally {
    Pop-Location
}
