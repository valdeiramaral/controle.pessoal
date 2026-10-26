@echo off
rem Atalho para duplo clique: roda testar.ps1 (que grava testar.log) e mantem a janela aberta.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0testar.ps1" %*
echo.
pause
