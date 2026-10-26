@echo off
rem Atalho para duplo clique: roda iniciar.ps1 e mantem a janela aberta.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar.ps1" %*
echo.
pause
