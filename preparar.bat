@echo off
rem Atalho para duplo clique: prepara tudo (.env, banco, API, pacotes do app) sem abrir o app.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar.ps1" -SoPreparar %*
echo.
pause
