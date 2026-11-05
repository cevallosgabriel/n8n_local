#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

ACTION="${1:-menu}"

[ ! -f ".env" ] && [ -f ".env.example" ] && cp .env.example .env
mkdir -p local-files data

get_env() {
    grep -E "^\s*$1=" .env | cut -d '=' -f2 | tr -d ' ' || echo "$2"
}

PORT=$(get_env "N8N_PORT" "5678")
PORT=${PORT:-5678}

start_docker() {
    USE_TUNNEL=$1
    if ! command -v docker &> /dev/null; then
        echo "[ERROR] Docker no está instalado."
        exit 1
    fi
    if [ "$USE_TUNNEL" = "true" ]; then
        echo "[*] Levantando Cloudflare Quick Tunnel..."
        nohup cloudflared --logfile .cloudflare.log tunnel --url "http://localhost:$PORT" > /dev/null 2>&1 &
        sleep 4
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .cloudflare.log | head -n 1)
        if [ -n "$URL" ]; then
            echo "$URL/" > .cloudflare.url
            sed -i "s|^#\?WEBHOOK_URL=.*|WEBHOOK_URL=$URL/|" .env
            echo "[OK] URL Pública: $URL/"
        fi
    fi
    docker compose up -d
    echo "[OK] n8n activo en http://localhost:$PORT"
}

start_node() {
    USE_TUNNEL=$1
    if ! command -v node &> /dev/null; then
        echo "[ERROR] Node.js no está instalado."
        exit 1
    fi
    if ! command -v n8n &> /dev/null; then
        echo "[*] Instalando n8n globalmente..."
        npm install -g n8n --legacy-peer-deps --omit=optional
    fi
    export N8N_USER_FOLDER="$(pwd)/data"
    export N8N_PORT="$PORT"
    export N8N_SSRF_PROTECTION_ENABLED="false"
    if [ "$USE_TUNNEL" = "true" ]; then
        echo "[*] Levantando Cloudflare Quick Tunnel..."
        nohup cloudflared --logfile .cloudflare.log tunnel --url "http://localhost:$PORT" > /dev/null 2>&1 &
        sleep 4
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .cloudflare.log | head -n 1)
        if [ -n "$URL" ]; then
            echo "$URL/" > .cloudflare.url
            export WEBHOOK_URL="$URL/"
            echo "[OK] URL Pública: $URL/"
        fi
    fi
    nohup n8n start > .n8n.log 2>&1 &
    echo "[OK] n8n activo en segundo plano (PID: $!). Revisa .n8n.log"
}

stop_all() {
    echo "[*] Deteniendo servicios..."
    docker compose down 2>/dev/null || true
    pkill -f "cloudflared" 2>/dev/null || true
    pkill -f "n8n" 2>/dev/null || true
    rm -f .cloudflare.url .cloudflare.log
    echo "[OK] Todos los servicios detenidos."
}

show_status() {
    echo "=========================================="
    echo "            Estado del Sistema            "
    echo "=========================================="
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" | grep -q "200"; then
        echo "Local:   http://localhost:$PORT -> EN LÍNEA (200 OK)"
    else
        echo "Local:   http://localhost:$PORT -> DETENIDO"
    fi
    if [ -f ".cloudflare.url" ]; then
        echo "Túnel:   $(cat .cloudflare.url) (Activo)"
    else
        echo "Túnel:   Inactivo"
    fi
    echo "=========================================="
}

case "$ACTION" in
    docker-local)   start_docker false ;;
    docker-tunnel)  start_docker true ;;
    node-local)     start_node false ;;
    node-tunnel)    start_node true ;;
    stop)           stop_all ;;
    status)         show_status ;;
    menu|*)
        clear
        echo "=========================================="
        echo "        n8n Unified Stack Manager         "
        echo "=========================================="
        echo "  [1] Docker  - Localhost"
        echo "  [2] Docker  - Cloudflare Tunnel"
        echo "  [3] Node.js - Localhost (Ligero, 8GB RAM)"
        echo "  [4] Node.js - Cloudflare Tunnel"
        echo "  [5] Detener todos los servicios"
        echo "  [6] Ver estado"
        echo "  [0] Salir"
        echo "=========================================="
        read -p "Opción: " opt
        case "$opt" in
            1) start_docker false ;;
            2) start_docker true ;;
            3) start_node false ;;
            4) start_node true ;;
            5) stop_all ;;
            6) show_status ;;
            *) exit 0 ;;
        esac
        ;;
esac
