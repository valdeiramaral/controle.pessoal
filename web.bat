@echo off
rem Abre o app no navegador (versao web). Duplo clique.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0web.ps1" %*
echo.
pause
