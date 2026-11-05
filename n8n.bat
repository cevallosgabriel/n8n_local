@echo off
setlocal
cd /d "%~dp0"
title n8n Unified Manager
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0n8n.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Ocurrio un error al ejecutar el gestor de n8n.
    pause
)
