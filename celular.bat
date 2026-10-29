@echo off
rem Instala e abre o app no celular Android ligado por cabo USB (depuracao USB), apontando para a API deste computador.
rem Antes, uma vez: rode o rede.bat como Administrador (libera a API na rede) e feche com Ctrl+C.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0celular.ps1" %*
echo.
pause
