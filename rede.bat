@echo off
rem Libera o sistema para outro computador da mesma rede. Clique direito > Executar como administrador.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rede.ps1" %*
echo.
pause
