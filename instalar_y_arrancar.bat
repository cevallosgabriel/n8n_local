@echo off
setlocal enabledelayedexpansion
title n8n Local - Instalador y Lanzador Universal

echo ==========================================================
echo       n8n Local - Instalador y Lanzador para Windows
echo ==========================================================
echo.

:: 1. Solicitar permisos de Administrador si no se tienen
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Solicitando permisos de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: 2. Configurar politica de ejecucion de PowerShell
echo [1/5] Habilitando ejecucion de scripts en PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" >nul 2>&1

:: 3. Verificar / Instalar Git
echo [2/5] Comprobando instalacion de Git...
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Git no esta instalado.
    echo Descargando instalador oficial de Git de 64 bits...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe' -OutFile '%TEMP%\git_installer.exe'"
    
    if exist "%TEMP%\git_installer.exe" (
        echo Instalando Git en modo silencioso (por favor espera)...
        "%TEMP%\git_installer.exe" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS
        del "%TEMP%\git_installer.exe" >nul 2>&1
        set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
        echo [OK] Git instalado exitosamente.
    ) else (
        echo [ERROR] No se pudo descargar Git automaticamente.
        start https://git-scm.com/download/win
    )
) else (
    echo [OK] Git ya esta instalado.
)

:: 4. Verificar / Instalar Docker Desktop
echo.
echo [3/5] Comprobando instalacion de Docker...
where docker >nul 2>&1
if %errorlevel% neq 0 (
    if not exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
        if not exist "%LOCALAPPDATA%\Programs\DockerDesktop\Docker Desktop.exe" (
            echo [!] Docker Desktop no esta instalado.
            echo Descargando instalador oficial de Docker Desktop (~500 MB)...
            powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('https://desktop.docker.com/win/main/amd64/Docker%%20Desktop%%20Installer.exe', '$env:TEMP\DockerDesktopInstaller.exe')"
            
            if exist "%TEMP%\DockerDesktopInstaller.exe" (
                echo Ejecutando instalador de Docker Desktop...
                start /wait "" "%TEMP%\DockerDesktopInstaller.exe" install --quiet
                del "%TEMP%\DockerDesktopInstaller.exe" >nul 2>&1
                echo.
                echo ==========================================================
                echo [ATENCION] Docker Desktop ha sido instalado.
                echo DEBES REINICIAR LA PC para que Windows active WSL2/Hyper-V.
                echo Despues de reiniciar, ejecuta este archivo .bat otra vez.
                echo ==========================================================
                pause
                exit /b
            ) else (
                echo [ERROR] No se pudo descargar Docker automaticamente.
                start https://www.docker.com/products/docker-desktop/
                pause
                exit /b
            )
        )
    )
)
echo [OK] Docker Desktop detectado.

:: 5. Descargar o actualizar el repositorio
echo.
echo [4/5] Preparando carpeta del proyecto...
set "TARGET_DIR=%USERPROFILE%\Desktop\n8n_local"

if not exist "%TARGET_DIR%" (
    echo Clonando repositorio desde GitHub en tu Escritorio...
    git clone https://github.com/cevallosgabriel/n8n_local.git "%TARGET_DIR%"
) else (
    echo Carpeta n8n_local ya existe en tu Escritorio.
)

:: 6. Iniciar n8n ejecutando el script PowerShell
echo.
echo [5/5] Iniciando n8n Local...
cd /d "%TARGET_DIR%"

if exist "start.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%TARGET_DIR%\start.ps1"
) else (
    docker compose up -d
    start http://localhost:5678
)

echo.
echo ==========================================================
echo   Instalacion y arranque completados exitosamente.
echo ==========================================================
pause
