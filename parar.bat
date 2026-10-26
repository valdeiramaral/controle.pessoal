@echo off
rem Atalho para duplo clique: roda parar.ps1 e mantem a janela aberta.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0parar.ps1" %*
echo.
pause
