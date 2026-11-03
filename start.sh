#!/usr/bin/env bash
# ==============================================================================
# Script de inicio universal para Linux y macOS
# ==============================================================================
set -e

cd "$(dirname "$0")"

echo "=========================================================="
echo "       n8n Universal Local Stack - Inicializador (Unix)   "
echo "=========================================================="

# 1. Detección automática de .env
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "[INFO] Archivo .env no encontrado. Generando desde .env.example..."
        cp .env.example .env
        echo "[OK] .env creado."
    else
        echo "[ERROR] No se encontró .env ni .env.example."
        exit 1
    fi
fi

mkdir -p local-files

# Leer puerto configurado o 5678
PORT=$(grep -E '^\s*N8N_PORT=' .env | cut -d '=' -f2 | tr -d ' ' || echo "5678")
PORT=${PORT:-5678}

# 2. Detección de Docker
if ! command -v docker &> /dev/null; then
    echo "[ERROR] Docker no está instalado."
    echo "Descárgalo aquí: https://docs.docker.com/get-docker/"
    exit 1
fi

# 3. Comprobar daemon
if ! docker info &> /dev/null; then
    echo "[ERROR] El daemon de Docker no está corriendo. Inícialo y vuelve a ejecutar."
    exit 1
fi

# 4. Desplegar
echo "[INFO] Desplegando n8n con docker compose..."
docker compose up -d

echo ""
echo "=========================================================="
echo "   n8n desplegado exitosamente!"
echo "   Panel Local: http://localhost:$PORT"
echo "=========================================================="

# Intentar abrir navegador según OS
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:$PORT"
elif command -v open &> /dev/null; then
    open "http://localhost:$PORT"
fi
