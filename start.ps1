<#
.SYNOPSIS
    Script universal de inicio automatizado para n8n en Windows.
.DESCRIPTION
    Detecta dependencias (Docker, .env), arranca el servicio, gestiona túneles opcionales
    (Cloudflare/Ngrok) y abre la interfaz web sin rutas hardcodeadas.
.PARAMETER Tunnel
    Opcional. Activa un túnel público para webhooks: 'cloudflare', 'ngrok' o 'none' (por defecto).
#>
param(
    [ValidateSet("none", "cloudflare", "ngrok")]
    [string]$Tunnel = "none"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       n8n Universal Local Stack - Inicializador          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. DETECCIÓN AUTOMÁTICA DE ARCHIVOS Y CONFIGURACIÓN (.env)
# ------------------------------------------------------------------------------
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Write-Host "[INFO] Archivo .env no encontrado. Generando automáticamente desde .env.example..." -ForegroundColor Yellow
        Copy-Item ".env.example" ".env"
        Write-Host "[OK] Archivo .env creado con configuraciones seguras por defecto." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] No se encontro ni .env ni .env.example." -ForegroundColor Red
        exit 1
    }
}

# Asegurar existencia de carpetas requeridas
if (-not (Test-Path "local-files")) {
    New-Item -ItemType Directory -Path "local-files" -Force | Out-Null
}

# Leer puerto configurado en .env (o 5678 por defecto)
$port = 5678
$envContent = Get-Content ".env" -ErrorAction SilentlyContinue
foreach ($line in $envContent) {
    if ($line -match "^\s*N8N_PORT\s*=\s*(\d+)") {
        $port = $matches[1]
        break
    }
}

# ------------------------------------------------------------------------------
# 2. DETECCIÓN DINÁMICA DE DOCKER DESKTOP
# ------------------------------------------------------------------------------
$searchPaths = @(
    "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe",
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
    "C:\Program Files\Docker\Docker\Docker Desktop.exe"
)

$dockerExe = $null
foreach ($p in $searchPaths) {
    if (Test-Path $p) {
        $dockerExe = $p
        break
    }
}

# Si no está en las rutas fijas, buscar en accesos directos o registro
if (-not $dockerExe) {
    $shortcuts = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk"
    )
    foreach ($s in $shortcuts) {
        if (Test-Path $s) {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $target = $sh.CreateShortcut($s).TargetPath
                if ($target -and (Test-Path $target)) {
                    $dockerExe = $target
                    break
                }
            } catch {}
        }
    }
}

# Si docker CLI no está en el PATH pero el ejecutable existe, agregarlo a la sesión actual
if ($dockerExe) {
    $dockerBin = Split-Path -Path $dockerExe
    $resourcesBin = Join-Path $dockerBin "resources\bin"
    if (Test-Path $resourcesBin) {
        $env:PATH = "$resourcesBin;$dockerBin;$env:PATH"
    } else {
        $env:PATH = "$dockerBin;$env:PATH"
    }
}

$dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue

if (-not $dockerCmd -and -not $dockerExe) {
    Write-Host "`n[ALERTA] No se detecto ninguna instalacion de Docker Desktop en el equipo." -ForegroundColor Yellow
    Write-Host "Abriendo sitio oficial de descarga directa..." -ForegroundColor Cyan
    Start-Process "https://www.docker.com/products/docker-desktop/"
    Write-Host "Instala Docker Desktop, reinicia tu equipo y vuelve a ejecutar este script." -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# 3. VERIFICACIÓN Y ARRANQUE DEL DAEMON DE DOCKER
# ------------------------------------------------------------------------------
$dockerReady = $false
try {
    $null = docker info 2>$null
    if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
} catch {
    $dockerReady = $false
}

if (-not $dockerReady) {
    Write-Host "[INFO] Docker Desktop no esta activo. Iniciando servicio..." -ForegroundColor Yellow
    
    if ($dockerExe) {
        Write-Host "[INFO] Iniciando Docker Desktop desde: $dockerExe" -ForegroundColor Cyan
        try {
            $null = wmic process call create "`"$dockerExe`""
        } catch {
            Start-Process -FilePath $dockerExe
        }
        
        Write-Host "[INFO] Esperando a que el motor de Docker responda..." -NoNewline -ForegroundColor Yellow
        $timeout = 90
        $elapsed = 0
        while (-not $dockerReady -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 3
            $elapsed += 3
            try {
                $null = docker info 2>$null
                if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
            } catch {}
            Write-Host "." -NoNewline
        }
        Write-Host ""
    } else {
        Write-Host "[ERROR] No se pudo encontrar el ejecutable de Docker Desktop." -ForegroundColor Red
        Write-Host "Por favor abre Docker Desktop manualmente desde tu menú Inicio y vuelve a ejecutar este script." -ForegroundColor Yellow
        exit 1
    }
}

if (-not $dockerReady) {
    Write-Host "[ERROR] El daemon de Docker no respondio tras 90 segundos." -ForegroundColor Red
    Write-Host "Verifica que la virtualizacion este habilitada en tu BIOS/Administrador de tareas." -ForegroundColor Yellow
    exit 1
}

# ------------------------------------------------------------------------------
# 4. GESTIÓN OPCIONAL DE TÚNELES (CLOUDFLARE / NGROK)
# ------------------------------------------------------------------------------
if ($Tunnel -eq "cloudflare") {
    $cfCmd = Get-Command "cloudflared" -ErrorAction SilentlyContinue
    if (-not $cfCmd) {
        Write-Host "`n[ALERTA] Cloudflared no esta instalado." -ForegroundColor Yellow
        $opt = Read-Host "¿Deseas instalarlo con winget ahora? (s/n)"
        if ($opt -match "^(s|y)") {
            winget install Cloudflare.cloudflared
        } else {
            Write-Host "Abriendo sitio oficial de Cloudflare Tunnel..." -ForegroundColor Cyan
            Start-Process "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
        }
    } else {
        Write-Host "[INFO] Iniciando Quick Tunnel de Cloudflare en segundo plano para el puerto $port..." -ForegroundColor Cyan
        Start-Process -FilePath "cloudflared" -ArgumentList "tunnel --url http://localhost:$port"
    }
} elseif ($Tunnel -eq "ngrok") {
    $ngCmd = Get-Command "ngrok" -ErrorAction SilentlyContinue
    if (-not $ngCmd) {
        Write-Host "`n[ALERTA] Ngrok no esta instalado." -ForegroundColor Yellow
        $opt = Read-Host "¿Deseas instalarlo con winget ahora? (s/n)"
        if ($opt -match "^(s|y)") {
            winget install ngrok.ngrok
        } else {
            Start-Process "https://ngrok.com/download"
        }
    } else {
        Write-Host "[INFO] Iniciando Ngrok en segundo plano para el puerto $port..." -ForegroundColor Cyan
        Start-Process -FilePath "ngrok" -ArgumentList "http $port"
    }
}

# ------------------------------------------------------------------------------
# 5. DESPLIEGUE DEL CONTENEDOR
# ------------------------------------------------------------------------------
Write-Host "`n[INFO] Desplegando n8n con docker compose..." -ForegroundColor Cyan
docker compose up -d

Write-Host "[INFO] Verificando estado del contenedor..." -ForegroundColor Cyan
docker compose ps

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   n8n desplegado exitosamente!" -ForegroundColor Green
Write-Host "   Panel Local: http://localhost:$port" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# Abrir el navegador en la URL local
Start-Process "http://localhost:$port"
