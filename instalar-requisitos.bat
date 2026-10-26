@echo off
rem Instala Git, Flutter, Android SDK/emulador e Docker Desktop (pede administrador).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-requisitos.ps1" %*
