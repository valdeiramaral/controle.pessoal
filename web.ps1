<#
.SYNOPSIS
  Abre o app no navegador (versao web) para testar sem emulador.

.DESCRIPTION
  1. Prepara tudo (banco, API, pacotes) com o iniciar.ps1 -SoPreparar.
  2. Abre o app no Chrome (porta 8081, ou a proxima livre se estiver ocupada)
  Deixe esta janela aberta enquanto testa. Para fechar: tecle q aqui.
  Na web nao ha lembretes (notificacoes); o resto funciona.
#>
param([int]$Porta = 8081)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot

Write-Host "==> Preparando banco, API e pacotes" -ForegroundColor Cyan
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $raiz "iniciar.ps1") -SoPreparar
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO: a preparacao falhou. Veja a mensagem acima." -ForegroundColor Red; exit 1 }

# Procura uma porta livre a partir da informada (a 8081 pode estar em uso).
function Porta-Livre($inicio) {
    foreach ($p in $inicio..($inicio + 50)) {
        $l = $null
        try {
            $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $p)
            $l.Start(); $l.Stop()
            return $p
        } catch {
            if ($l) { try { $l.Stop() } catch {} }
        }
    }
    return $inicio
}
$Porta = Porta-Livre $Porta

Write-Host ""
Write-Host "==> Abrindo o app no navegador (http://localhost:$Porta)" -ForegroundColor Cyan
Push-Location (Join-Path $raiz "app")
try {
    flutter run -d chrome --web-port $Porta
} finally {
    Pop-Location
}
