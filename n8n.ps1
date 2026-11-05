param(
    [ValidateSet("menu", "docker-local", "docker-tunnel", "node-local", "node-tunnel", "stop", "status")]
    [string]$Action = "menu",
    [string]$Port = "5678"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
    }
}

if (-not (Test-Path "local-files")) {
    New-Item -ItemType Directory -Path "local-files" -Force | Out-Null
}

if (-not (Test-Path "data")) {
    New-Item -ItemType Directory -Path "data" -Force | Out-Null
}

function Get-EnvVar([string]$key, [string]$default = "") {
    if (Test-Path ".env") {
        foreach ($line in (Get-Content ".env")) {
            if ($line -match "^\s*$key\s*=\s*(.*)$") {
                return $matches[1].Trim().Trim('"').Trim("'")
            }
        }
    }
    return $default
}

function Set-EnvFileVar([string]$key, [string]$val) {
    if (Test-Path ".env") {
        $lines = Get-Content ".env"
        $found = $false
        $newLines = foreach ($line in $lines) {
            if ($line -match "^\s*#?\s*$key\s*=.*$") {
                $found = $true
                "$key=$val"
            } else {
                $line
            }
        }
        if (-not $found) {
            $newLines += "$key=$val"
        }
        $newLines | Set-Content ".env" -Encoding utf8
    }
}

function Load-EnvToProcess {
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
                $parts = $line.Split("=", 2)
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
            }
        }
    }
}

function Get-DockerExecutable {
    $cmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe",
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-NodeExecutable {
    $cmd = Get-Command "node" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-CloudflaredExecutable {
    $cmd = Get-Command "cloudflared" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $p = "$env:LOCALAPPDATA\Programs\Cloudflared\cloudflared.exe"
    if (Test-Path $p) { return $p }
    return $null
}

function Install-Cloudflared {
    $destDir = "$env:LOCALAPPDATA\Programs\Cloudflared"
    $destExe = "$destDir\cloudflared.exe"
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Host "[*] Descargando Cloudflare Tunnel portable..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    (New-Object Net.WebClient).DownloadFile("https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe", $destExe)
    Write-Host "[OK] Cloudflare Tunnel descargado." -ForegroundColor Green
    return $destExe
}

function Start-CloudflareTunnel([string]$localPort) {
    $cfExe = Get-CloudflaredExecutable
    if (-not $cfExe) {
        $cfExe = Install-Cloudflared
    }
    $logFile = "$PSScriptRoot\.cloudflare.log"
    if (Test-Path $logFile) { Remove-Item $logFile -Force }
    
    Write-Host "[*] Levantando Cloudflare Quick Tunnel..." -ForegroundColor Cyan
    Start-Process -FilePath $cfExe -ArgumentList "--logfile `"$logFile`" tunnel --url http://localhost:$localPort" -WindowStyle Hidden
    
    $timeout = 20
    $elapsed = 0
    $tunnelUrl = $null
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $elapsed++
        if (Test-Path $logFile) {
            $raw = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($raw -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                $tunnelUrl = $matches[1]
                break
            }
        }
        Write-Host "." -NoNewline
    }
    Write-Host ""
    if ($tunnelUrl) {
        $tunnelUrl = "$tunnelUrl/"
        Set-Content -Path "$PSScriptRoot\.cloudflare.url" -Value $tunnelUrl
        Write-Host "[OK] URL Publica HTTPS generada: $tunnelUrl" -ForegroundColor Green
        return $tunnelUrl
    } else {
        Write-Host "[!] No se pudo obtener la URL de Cloudflare en 20s. Continuando..." -ForegroundColor Yellow
        return $null
    }
}

function Start-DockerMode([bool]$useTunnel) {
    $dockerExe = Get-DockerExecutable
    if (-not $dockerExe) {
        Write-Host "[ERROR] Docker Desktop no esta instalado en este sistema." -ForegroundColor Red
        Write-Host "Usa la opcion de Node.js o instala Docker Desktop." -ForegroundColor Yellow
        return
    }

    $dockerReady = $false
    try {
        $null = docker info 2>$null
        if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
    } catch {}

    if (-not $dockerReady) {
        Write-Host "[*] Iniciando Docker Desktop..." -ForegroundColor Cyan
        try {
            $null = wmic process call create "`"$dockerExe`""
        } catch {
            Start-Process -FilePath $dockerExe
        }
        $timeout = 60
        $elapsed = 0
        Write-Host "[*] Esperando a que el daemon de Docker responda..." -NoNewline -ForegroundColor Yellow
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
    }

    $envPort = Get-EnvVar "N8N_PORT" "5678"
    if ($useTunnel) {
        $tUrl = Start-CloudflareTunnel $envPort
        if ($tUrl) {
            Set-EnvFileVar "WEBHOOK_URL" $tUrl
        }
    }

    Write-Host "[*] Levantando contenedor n8n con docker compose..." -ForegroundColor Cyan
    docker compose up -d
    Write-Host "[OK] Contenedor n8n activo en http://localhost:$envPort" -ForegroundColor Green
    Start-Process "http://localhost:$envPort"
}

function Start-NodeMode([bool]$useTunnel) {
    $nodeExe = Get-NodeExecutable
    if (-not $nodeExe) {
        Write-Host "[ERROR] Node.js no esta instalado. Instala Node.js v20 o v24 para usar este modo." -ForegroundColor Red
        return
    }

    $n8nCmd = Get-Command "n8n" -ErrorAction SilentlyContinue
    if (-not $n8nCmd) {
        Write-Host "[*] Instalando n8n globalmente con npm..." -ForegroundColor Cyan
        cmd.exe /c "npm install -g n8n --legacy-peer-deps --omit=optional"
        $n8nCmd = Get-Command "n8n" -ErrorAction SilentlyContinue
        if (-not $n8nCmd) {
            Write-Host "[ERROR] No se pudo encontrar n8n tras la instalacion." -ForegroundColor Red
            return
        }
    }

    Load-EnvToProcess
    $envPort = [Environment]::GetEnvironmentVariable("N8N_PORT")
    if (-not $envPort) { $envPort = "5678" }

    $env:N8N_USER_FOLDER = Join-Path $PSScriptRoot "data"
    $env:N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true"
    $env:N8N_SSRF_PROTECTION_ENABLED = "false"

    if ($useTunnel) {
        $tUrl = Start-CloudflareTunnel $envPort
        if ($tUrl) {
            $env:WEBHOOK_URL = $tUrl
            Set-EnvFileVar "WEBHOOK_URL" $tUrl
        }
    }

    Write-Host "[*] Iniciando n8n Server nativo..." -ForegroundColor Cyan
    $n8nScript = "title n8n Server (Node.js) && n8n start"
    Start-Process cmd.exe -ArgumentList "/c $n8nScript"

    Write-Host "[*] Esperando a que n8n responda..." -NoNewline -ForegroundColor Yellow
    $ready = $false
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
        try {
            $res = Invoke-WebRequest -Uri "http://localhost:$envPort" -UseBasicParsing -TimeoutSec 2 2>$null
            if ($res.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
    }
    Write-Host ""
    Write-Host "[OK] n8n nativo esta listo en http://localhost:$envPort" -ForegroundColor Green
    Start-Process "http://localhost:$envPort"
}

function Stop-AllServices {
    Write-Host "[*] Deteniendo servicios..." -ForegroundColor Yellow
    try { docker compose down 2>$null } catch {}
    Stop-Process -Name "cloudflared" -Force -ErrorAction SilentlyContinue
    
    Get-Process -Name "node" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.MainWindowTitle -match "n8n") { Stop-Process -Id $_.Id -Force }
        } catch {}
    }
    taskkill /F /FI "WINDOWTITLE eq n8n Server*" 2>$null | Out-Null
    
    if (Test-Path "$PSScriptRoot\.cloudflare.url") { Remove-Item "$PSScriptRoot\.cloudflare.url" -Force }
    if (Test-Path "$PSScriptRoot\.cloudflare.log") { Remove-Item "$PSScriptRoot\.cloudflare.log" -Force }
    Write-Host "[OK] Todos los servicios detenidos." -ForegroundColor Green
}

function Show-Status {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "                  Estado del Sistema                      " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    
    $port = Get-EnvVar "N8N_PORT" "5678"
    $httpOk = $false
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$port" -UseBasicParsing -TimeoutSec 2 2>$null
        if ($r.StatusCode -eq 200) { $httpOk = $true }
    } catch {}

    $statusMsg = if ($httpOk) { "EN LINEA (200 OK)" } else { "DETENIDO" }
    Write-Host "Panel Local:   http://localhost:$port -> $statusMsg"
    
    $cfProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($cfProc -and (Test-Path "$PSScriptRoot\.cloudflare.url")) {
        $url = Get-Content "$PSScriptRoot\.cloudflare.url" -Raw
        Write-Host "Túnel Publico: $url (Activo)" -ForegroundColor Green
    } else {
        Write-Host "Túnel Publico: Inactivo" -ForegroundColor Gray
    }
    
    $dockerPs = docker ps --filter "name=n8n" --format "{{.Names}} ({{.Status}})" 2>$null
    if ($dockerPs) {
        Write-Host "Docker:        $dockerPs" -ForegroundColor Green
    } else {
        Write-Host "Docker:        Sin contenedores n8n activos" -ForegroundColor Gray
    }
    Write-Host "==========================================================" -ForegroundColor Cyan
}

switch ($Action) {
    "docker-local"   { Start-DockerMode $false }
    "docker-tunnel"  { Start-DockerMode $true }
    "node-local"     { Start-NodeMode $false }
    "node-tunnel"    { Start-NodeMode $true }
    "stop"           { Stop-AllServices }
    "status"         { Show-Status }
    "menu" {
        Clear-Host
        $hasDocker = [bool](Get-DockerExecutable)
        $hasNode = [bool](Get-NodeExecutable)
        $cpuVt = $false
        try {
            $cpuVt = [bool]((Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled)
        } catch {}

        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "               n8n Unified Stack Manager                  " -ForegroundColor Cyan
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "Entorno detectado:" -ForegroundColor White
        Write-Host "  * Docker:         $(if ($hasDocker) { 'Disponible' } else { 'No instalado' })"
        Write-Host "  * Virtualización: $(if ($cpuVt) { 'Habilitada' } else { 'Deshabilitada (Recomendado usar Node.js)' })"
        Write-Host "  * Node.js:        $(if ($hasNode) { 'Disponible' } else { 'No instalado' })"
        Write-Host "----------------------------------------------------------" -ForegroundColor Gray
        Write-Host "Opciones:" -ForegroundColor White
        Write-Host "  [1] Iniciar con Docker (Localhost)"
        Write-Host "  [2] Iniciar con Docker + Cloudflare Tunnel (Webhook Publico)"
        Write-Host "  [3] Iniciar con Node.js (Localhost - Ligero, ideal para 8GB RAM)"
        Write-Host "  [4] Iniciar con Node.js + Cloudflare Tunnel (Ligero + Webhook)"
        Write-Host "  [5] Detener todos los servicios"
        Write-Host "  [6] Ver estado"
        Write-Host "  [0] Salir"
        Write-Host "==========================================================" -ForegroundColor Cyan
        
        $opt = Read-Host "Selecciona una opción (0-6)"
        switch ($opt) {
            "1" { Start-DockerMode $false }
            "2" { Start-DockerMode $true }
            "3" { Start-NodeMode $false }
            "4" { Start-NodeMode $true }
            "5" { Stop-AllServices }
            "6" { Show-Status }
            default { Write-Host "Operación cancelada." }
        }
    }
}
