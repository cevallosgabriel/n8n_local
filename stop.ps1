<#
.SYNOPSIS
    Detiene el stack de n8n preservando los datos.
#>
Set-Location -Path $PSScriptRoot

Write-Host ">>> Deteniendo n8n..." -ForegroundColor Yellow
docker compose down

Write-Host ">>> Contenedores detenidos con exito. Todos tus flujos y credenciales permanecen intactos en el volumen persistente." -ForegroundColor Green
