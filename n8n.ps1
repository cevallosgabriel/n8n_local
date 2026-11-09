param(
    [ValidateSet("menu", "docker-local", "docker-tunnel", "node-local", "node-tunnel", "stop", "status")]
    [string]$Action = "menu",
    [string]$Port = "5678"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

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
        if (-not $found) { $newLines += "$key=$val" }
        $newLines | Set-Content ".env" -Encoding utf8
    }
}

function Initialize-Environment {
    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.example") {
            Copy-Item ".env.example" ".env"
        } else {
            New-Item -ItemType File -Path ".env" -Force | Out-Null
        }
    }
    if (-not (Test-Path "local-files")) { New-Item -ItemType Directory -Path "local-files" -Force | Out-Null }
    if (-not (Test-Path "data")) { New-Item -ItemType Directory -Path "data" -Force | Out-Null }

    $userFolder = Get-EnvVar "N8N_USER_FOLDER" ""
    if (-not $userFolder) {
        Set-EnvFileVar "N8N_USER_FOLDER" "./data"
    }

    $perm = Get-EnvVar "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS" ""
    if ($perm -ne "false") {
        Set-EnvFileVar "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS" "false"
    }

    $unverified = Get-EnvVar "N8N_UNVERIFIED_PACKAGES_ENABLED" ""
    if (-not $unverified) {
        Set-EnvFileVar "N8N_UNVERIFIED_PACKAGES_ENABLED" "true"
    }

    $runners = Get-EnvVar "N8N_RUNNERS_ENABLED" ""
    if (-not $runners) {
        Set-EnvFileVar "N8N_RUNNERS_ENABLED" "false"
    }

    Sync-EncryptionKey | Out-Null

    $dataDb = Join-Path $PSScriptRoot "data\database.sqlite"
    $homeDb = Join-Path $env:USERPROFILE ".n8n\database.sqlite"
    if (-not (Test-Path $dataDb) -and (Test-Path $homeDb)) {
        Write-Host "[*] Detectada configuracion previa en $env:USERPROFILE\.n8n. Migrando datos a data/..." -ForegroundColor Cyan
        Copy-Item "$env:USERPROFILE\.n8n\*" -Destination (Join-Path $PSScriptRoot "data") -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Datos previos migrados a data/ exitosamente." -ForegroundColor Green
    }
}

function Sync-EncryptionKey {
    $configPath = Join-Path $PSScriptRoot "data\config"
    $keyFromConfig = $null

    if (Test-Path $configPath) {
        try {
            $rawConfig = Get-Content $configPath -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if ($rawConfig -match '"encryptionKey"\s*:\s*"([^"]+)"') {
                $keyFromConfig = $matches[1].Trim()
            }
        } catch {}
    }

    $keyFromEnv = Get-EnvVar "N8N_ENCRYPTION_KEY" ""

    if ($keyFromConfig) {
        if ($keyFromEnv -ne $keyFromConfig) {
            Write-Host "[*] Sincronizando N8N_ENCRYPTION_KEY con clave existente de data/config..." -ForegroundColor Cyan
            Set-EnvFileVar "N8N_ENCRYPTION_KEY" $keyFromConfig
        }
        $finalKey = $keyFromConfig
    } elseif ($keyFromEnv) {
        if (-not (Test-Path "data")) { New-Item -ItemType Directory -Path "data" -Force | Out-Null }
        $jsonStr = "{`n`t`"encryptionKey`": `"$keyFromEnv`"`n}"
        [System.IO.File]::WriteAllText($configPath, $jsonStr, [System.Text.UTF8Encoding]::new($false))
        $finalKey = $keyFromEnv
    } else {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $newKey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
        Set-EnvFileVar "N8N_ENCRYPTION_KEY" $newKey
        if (-not (Test-Path "data")) { New-Item -ItemType Directory -Path "data" -Force | Out-Null }
        $jsonStr = "{`n`t`"encryptionKey`": `"$newKey`"`n}"
        [System.IO.File]::WriteAllText($configPath, $jsonStr, [System.Text.UTF8Encoding]::new($false))
        $finalKey = $newKey
    }

    [Environment]::SetEnvironmentVariable("N8N_ENCRYPTION_KEY", $finalKey, "Process")
    $env:N8N_ENCRYPTION_KEY = $finalKey
    return $finalKey
}

function Load-EnvToProcess {
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
                $parts = $line.Split("=", 2)
                $k = $parts[0].Trim()
                $v = $parts[1].Trim().Trim('"').Trim("'")
                [Environment]::SetEnvironmentVariable($k, $v, "Process")
                Set-Item "env:$k" $v
            }
        }
    }

    $userFolder = [Environment]::GetEnvironmentVariable("N8N_USER_FOLDER")
    if (-not $userFolder -or $userFolder -eq "./data" -or $userFolder -eq "data") {
        $userFolder = Join-Path $PSScriptRoot "data"
    } elseif ($userFolder.StartsWith(".")) {
        $userFolder = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $userFolder))
    }
    [Environment]::SetEnvironmentVariable("N8N_USER_FOLDER", $userFolder, "Process")
    $env:N8N_USER_FOLDER = $userFolder

    $env:N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "false"
    [Environment]::SetEnvironmentVariable("N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS", "false", "Process")
    $env:N8N_SSRF_PROTECTION_ENABLED = "false"
    [Environment]::SetEnvironmentVariable("N8N_SSRF_PROTECTION_ENABLED", "false", "Process")

    $proxyHops = [Environment]::GetEnvironmentVariable("N8N_PROXY_HOPS")
    if (-not $proxyHops) {
        $env:N8N_PROXY_HOPS = "1"
        [Environment]::SetEnvironmentVariable("N8N_PROXY_HOPS", "1", "Process")
    }

    $env:N8N_UNVERIFIED_PACKAGES_ENABLED = "true"
    [Environment]::SetEnvironmentVariable("N8N_UNVERIFIED_PACKAGES_ENABLED", "true", "Process")

    $env:N8N_RUNNERS_ENABLED = "false"
    [Environment]::SetEnvironmentVariable("N8N_RUNNERS_ENABLED", "false", "Process")

    # Limpiar variable obsoleta WEBHOOK_URL para evitar advertencia de deprecación
    if ($env:WEBHOOK_URL) {
        if (-not $env:N8N_WEBHOOK_URL) {
            $env:N8N_WEBHOOK_URL = $env:WEBHOOK_URL
            [Environment]::SetEnvironmentVariable("N8N_WEBHOOK_URL", $env:WEBHOOK_URL, "Process")
        }
        $env:WEBHOOK_URL = $null
        [Environment]::SetEnvironmentVariable("WEBHOOK_URL", $null, "Process")
    }
}

function Get-DockerExecutable {
    $cmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe",
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
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

function Get-N8nExecutable {
    $cmd = (Get-Command "n8n.cmd" -ErrorAction SilentlyContinue).Source
    if ($cmd -and (Test-Path $cmd) -and $cmd -notmatch [regex]::Escape($PSScriptRoot)) { return $cmd }
    
    $paths = @(
        "$env:APPDATA\npm\n8n.cmd",
        "$env:ProgramFiles\nodejs\n8n.cmd",
        "${env:ProgramFiles(x86)}\nodejs\n8n.cmd",
        "$env:LOCALAPPDATA\Programs\nodejs\n8n.cmd"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    try {
        $npmPrefix = (& npm.cmd config get prefix 2>$null)
        if ($npmPrefix) {
            $p = Join-Path $npmPrefix.Trim() "n8n.cmd"
            if (Test-Path $p) { return $p }
        }
    } catch {}
    return $null
}

function Get-CloudflaredExecutable {
    $cmd = Get-Command "cloudflared" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Cloudflared\cloudflared.exe",
        "$PSScriptRoot\tools\cloudflared.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
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

    Stop-Process -Name "cloudflared" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300

    $logFile = "$PSScriptRoot\.cloudflare.log"
    if (Test-Path $logFile) {
        try {
            Remove-Item $logFile -Force -ErrorAction Stop
        } catch {
            try { Clear-Content $logFile -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    
    Write-Host "[*] Levantando Cloudflare Quick Tunnel..." -ForegroundColor Cyan
    $cfCmdLine = "`"$cfExe`" --logfile `"$logFile`" tunnel --url http://127.0.0.1:$localPort"
    try {
        $null = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine = $cfCmdLine}
    } catch {
        Start-Process -FilePath $cfExe -ArgumentList "--logfile `"$logFile`" tunnel --url http://127.0.0.1:$localPort" -WindowStyle Hidden
    }
    
    $timeout = 25
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
        Set-Content -Path "$PSScriptRoot\.cloudflare.url" -Value $tunnelUrl -Encoding utf8
        Write-Host "[OK] URL Publica HTTPS generada: $tunnelUrl" -ForegroundColor Green
        return $tunnelUrl
    } else {
        Write-Host "[!] No se pudo obtener la URL de Cloudflare en 25s. Continuando..." -ForegroundColor Yellow
        return $null
    }
}

function Start-DockerMode([bool]$useTunnel) {
    $dockerExe = Get-DockerExecutable
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue

    if (-not $dockerExe -and -not $dockerCmd) {
        Write-Host "`n[ERROR] Docker Desktop no esta instalado en este sistema." -ForegroundColor Red
        Write-Host "Sugerencia: Usa la opcion de Node.js (opciones 3 o 4) para ejecutar n8n sin Docker." -ForegroundColor Yellow
        return
    }

    $dockerReady = $false
    if ($dockerCmd) {
        try {
            $null = docker info 2>$null
            if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
        } catch {}
    }

    if (-not $dockerReady -and $dockerExe) {
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
            if (Get-Command "docker" -ErrorAction SilentlyContinue) {
                try {
                    $null = docker info 2>$null
                    if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
                } catch {}
            }
            Write-Host "." -NoNewline
        }
        Write-Host ""
    }

    if (-not $dockerReady) {
        Write-Host "[ERROR] El motor de Docker no respondio. Verifica si Docker Desktop esta abierto." -ForegroundColor Red
        return
    }

    Load-EnvToProcess
    $envPort = [Environment]::GetEnvironmentVariable("N8N_PORT")
    if (-not $envPort) { $envPort = "5678" }

    if ($useTunnel) {
        $tUrl = Start-CloudflareTunnel $envPort
        if ($tUrl) {
            Set-EnvFileVar "N8N_WEBHOOK_URL" $tUrl
            $env:N8N_WEBHOOK_URL = $tUrl
            [Environment]::SetEnvironmentVariable("N8N_WEBHOOK_URL", $tUrl, "Process")
            $env:WEBHOOK_URL = $null
            [Environment]::SetEnvironmentVariable("WEBHOOK_URL", $null, "Process")
        }
    }

    Write-Host "[*] Levantando contenedor n8n con docker compose..." -ForegroundColor Cyan
    docker compose up -d
    Write-Host "[OK] Contenedor n8n activo en http://localhost:$envPort" -ForegroundColor Green
    Start-Process "http://localhost:$envPort"
}

function Start-NodeMode([bool]$useTunnel) {
    Load-EnvToProcess
    $envPort = [Environment]::GetEnvironmentVariable("N8N_PORT")
    if (-not $envPort) { $envPort = "5678" }

    # Comprobar si n8n ya está activo y respondiendo
    $isN8nRunning = $false
    try {
        $curlCheck = (& curl.exe -s "http://127.0.0.1:$envPort/healthz" 2>$null)
        if ($curlCheck -match '"status":"ok"') { $isN8nRunning = $true }
    } catch {}

    if ($isN8nRunning) {
        Write-Host "[OK] n8n ya se encuentra en ejecucion en el puerto $envPort." -ForegroundColor Green
        if ($useTunnel) {
            Write-Host "[*] Reconectando unicamente Cloudflare Quick Tunnel..." -ForegroundColor Cyan
            $tUrl = Start-CloudflareTunnel $envPort
            if ($tUrl) {
                $env:N8N_WEBHOOK_URL = $tUrl
                Set-EnvFileVar "N8N_WEBHOOK_URL" $tUrl
                [Environment]::SetEnvironmentVariable("N8N_WEBHOOK_URL", $tUrl, "Process")
                $env:WEBHOOK_URL = $null
                [Environment]::SetEnvironmentVariable("WEBHOOK_URL", $null, "Process")
                Write-Host "[OK] Tunel de Cloudflare reconectado exitosamente sin reiniciar n8n." -ForegroundColor Green
                Write-Host "[OK] URL Publica: $tUrl" -ForegroundColor Green
            }
        } else {
            Write-Host "[*] Abriendo panel de n8n en el navegador..." -ForegroundColor Cyan
            Start-Process "http://localhost:$envPort"
        }
        return
    }

    $nodeExe = Get-NodeExecutable
    if (-not $nodeExe) {
        Write-Host "`n[ERROR] Node.js no esta instalado en este equipo." -ForegroundColor Red
        Write-Host "Instala Node.js v20 o v24 LTS para usar este modo: https://nodejs.org/" -ForegroundColor Yellow
        return
    }

    $n8nBin = Get-N8nExecutable
    if (-not $n8nBin) {
        Write-Host "[*] Instalando n8n globalmente con npm..." -ForegroundColor Cyan
        cmd.exe /c "npm.cmd install -g n8n --legacy-peer-deps --omit=optional"
        $n8nBin = Get-N8nExecutable
        if (-not $n8nBin) {
            Write-Host "[ERROR] No se pudo encontrar n8n tras la instalacion." -ForegroundColor Red
            return
        }
    }

    if ($useTunnel) {
        $tUrl = Start-CloudflareTunnel $envPort
        if ($tUrl) {
            $env:N8N_WEBHOOK_URL = $tUrl
            Set-EnvFileVar "N8N_WEBHOOK_URL" $tUrl
            [Environment]::SetEnvironmentVariable("N8N_WEBHOOK_URL", $tUrl, "Process")
            $env:WEBHOOK_URL = $null
            [Environment]::SetEnvironmentVariable("WEBHOOK_URL", $null, "Process")
        }
    }

    Sync-EncryptionKey | Out-Null

    Write-Host "[*] Iniciando n8n Server nativo..." -ForegroundColor Cyan
    $n8nCmdLine = "title n8n Server (Node.js) && `"$n8nBin`" start"
    Start-Process cmd.exe -ArgumentList "/k `"$n8nCmdLine`"" -WorkingDirectory $PSScriptRoot

    Write-Host "[*] Esperando a que n8n responda..." -NoNewline -ForegroundColor Yellow
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
        try {
            $curlOut = (& curl.exe -s "http://127.0.0.1:$envPort/healthz" 2>$null)
            if ($curlOut -match '"status":"ok"') { $ready = $true; break }
        } catch {}
    }
    Write-Host ""
    if ($ready) {
        Write-Host "[OK] n8n nativo esta listo en http://localhost:$envPort" -ForegroundColor Green
        Start-Process "http://localhost:$envPort"
    } else {
        Write-Host "[!] El servidor inicio. Abre tu navegador en: http://localhost:$envPort" -ForegroundColor Yellow
    }
}

function Stop-AllServices {
    Write-Host "[*] Deteniendo todos los servicios..." -ForegroundColor Yellow
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        try { docker compose down 2>$null } catch {}
    }
    Stop-Process -Name "cloudflared" -Force -ErrorAction SilentlyContinue
    
    $port = Get-EnvVar "N8N_PORT" "5678"
    $listeningPids = (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($p in $listeningPids) {
        try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {}
    }

    Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -match "n8n") {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    taskkill /F /FI "WINDOWTITLE eq n8n Server*" 2>$null | Out-Null
    
    if (Test-Path "$PSScriptRoot\.cloudflare.url") { Remove-Item "$PSScriptRoot\.cloudflare.url" -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$PSScriptRoot\.cloudflare.log") {
        try { Remove-Item "$PSScriptRoot\.cloudflare.log" -Force -ErrorAction Stop }
        catch { Clear-Content "$PSScriptRoot\.cloudflare.log" -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "[OK] Todos los servicios han sido detenidos." -ForegroundColor Green
}

function Test-InternetConnection([int]$timeoutMs = 1200) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("1.1.1.1", 443, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs)
        if ($ok -and $client.Connected) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
    } catch {}
    return $false
}

function Show-Status {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "                  Estado del Sistema                      " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    
    $isInternetUp = Test-InternetConnection
    if ($isInternetUp) {
        Write-Host "Conexion Red:  CONECTADO (Internet OK)" -ForegroundColor Green
    } else {
        Write-Host "Conexion Red:  DESCONECTADO (Sin acceso a Internet)" -ForegroundColor Red
    }

    $port = Get-EnvVar "N8N_PORT" "5678"
    $httpOk = $false
    try {
        $curlOut = (& curl.exe -s "http://127.0.0.1:$port/healthz" 2>$null)
        if ($curlOut -match '"status":"ok"') { $httpOk = $true }
    } catch {}
    if (-not $httpOk) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/healthz" -UseBasicParsing -TimeoutSec 2 2>$null
            if ($r.StatusCode -eq 200) { $httpOk = $true }
        } catch {}
    }

    $statusMsg = if ($httpOk) { "EN LINEA (200 OK)" } else { "DETENIDO" }
    Write-Host "Panel Local:   http://localhost:$port -> $statusMsg"
    
    $cfProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($cfProc -and (Test-Path "$PSScriptRoot\.cloudflare.url")) {
        $url = (Get-Content "$PSScriptRoot\.cloudflare.url" -Raw).Trim()
        $cleanUrl = $url.TrimEnd('/')
        if (-not $isInternetUp) {
            Write-Host "Tunel Publico: $cleanUrl/ -> DESCONECTADO (Sin conexion a Internet)" -ForegroundColor Red
        } else {
            $tunnelProbeOk = $false
            try {
                $probe = (& curl.exe -s --connect-timeout 4 --max-time 5 "$cleanUrl/healthz" 2>$null)
                if ($probe -match '"status":"ok"') { $tunnelProbeOk = $true }
            } catch {}

            if ($tunnelProbeOk) {
                Write-Host "Tunel Publico: $cleanUrl/ -> EN LINEA (Accesible desde Internet)" -ForegroundColor Green
            } else {
                Write-Host "Tunel Publico: $cleanUrl/ -> RECONECTANDO (Esperando enlace de Cloudflare...)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Tunel Publico: Inactivo" -ForegroundColor Gray
    }

    $nodePids = @()
    $portProcId = (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
    if ($portProcId) {
        $proc = Get-Process -Id $portProcId -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -match "node") {
            $nodePids += $portProcId
        }
    }
    Get-Process -Name "node" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.MainWindowTitle -match "n8n" -and $nodePids -notcontains $_.Id) {
            $nodePids += $_.Id
        }
    }
    if ($nodePids.Count -gt 0) {
        $pidStr = $nodePids -join ", "
        Write-Host "Motor Node.js: Activo (PID: $pidStr)" -ForegroundColor Green
    } else {
        Write-Host "Motor Node.js: Inactivo" -ForegroundColor Gray
    }
    
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        try {
            $dockerPs = & docker ps --filter "name=n8n" --format "{{.Names}} ({{.Status}})" 2>$null
            if ($dockerPs) {
                Write-Host "Motor Docker:  Activo ($dockerPs)" -ForegroundColor Green
            } else {
                Write-Host "Motor Docker:  Instalado (Sin contenedores n8n activos)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Motor Docker:  Instalado (Daemon detenido)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Motor Docker:  No instalado en el equipo" -ForegroundColor Gray
    }

    $dataDb = Join-Path $PSScriptRoot "data\database.sqlite"
    $encKey = Get-EnvVar "N8N_ENCRYPTION_KEY" ""
    Write-Host "----------------------------------------------------------" -ForegroundColor Gray
    if (Test-Path $dataDb) {
        $dbSize = [math]::Round(((Get-Item $dataDb).Length / 1KB), 1)
        Write-Host "Base de Datos: Inicializada ($dataDb - ${dbSize} KB)" -ForegroundColor Green
    } else {
        Write-Host "Base de Datos: Pendiente de primer inicio (se creara en data/)" -ForegroundColor Yellow
    }
    if ($encKey) {
        $maskedKey = $encKey.Substring(0, 4) + "..." + $encKey.Substring($encKey.Length - 4)
        Write-Host "Clave Encript: Persistente en .env ($maskedKey)" -ForegroundColor Green
    } else {
        Write-Host "Clave Encript: No definida en .env" -ForegroundColor Yellow
    }
    Write-Host "==========================================================" -ForegroundColor Cyan
}

Initialize-Environment

switch ($Action) {
    "docker-local"   { Start-DockerMode $false }
    "docker-tunnel"  { Start-DockerMode $true }
    "node-local"     { Start-NodeMode $false }
    "node-tunnel"    { Start-NodeMode $true }
    "stop"           { Stop-AllServices }
    "status"         { Show-Status }
    "menu" {
        while ($true) {
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
            Write-Host "  * Virtualizacion: $(if ($cpuVt) { 'Habilitada' } else { 'Deshabilitada (Usa Node.js)' })"
            Write-Host "  * Node.js:        $(if ($hasNode) { 'Disponible' } else { 'No instalado' })"
            Write-Host "----------------------------------------------------------" -ForegroundColor Gray
            Write-Host "Opciones:" -ForegroundColor White
            Write-Host "  [1] Iniciar con Docker (Localhost)"
            Write-Host "  [2] Iniciar con Docker + Cloudflare Tunnel (Webhook Publico)"
            Write-Host "  [3] Iniciar con Node.js (Localhost - Ligero, ideal para 8GB RAM)"
            Write-Host "  [4] Iniciar / Reconectar Node.js + Cloudflare Tunnel (Inteligente)"
            Write-Host "  [5] Detener todos los servicios"
            Write-Host "  [6] Ver estado"
            Write-Host "  [0] Salir"
            Write-Host "==========================================================" -ForegroundColor Cyan
            
            $opt = Read-Host "Selecciona una opcion (0-6)"
            switch ($opt) {
                "1" { Start-DockerMode $false; Read-Host "`nPresiona Enter para volver al menu..." }
                "2" { Start-DockerMode $true; Read-Host "`nPresiona Enter para volver al menu..." }
                "3" { Start-NodeMode $false; Read-Host "`nPresiona Enter para volver al menu..." }
                "4" { Start-NodeMode $true; Read-Host "`nPresiona Enter para volver al menu..." }
                "5" { Stop-AllServices; Read-Host "`nPresiona Enter para volver al menu..." }
                "6" { Show-Status; Read-Host "`nPresiona Enter para volver al menu..." }
                "0" { Write-Host "Saliendo..."; exit 0 }
                default { Write-Host "Opcion no valida."; Start-Sleep -Seconds 1 }
            }
        }
    }
}
