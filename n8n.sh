#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

ACTION="${1:-menu}"

[ ! -f ".env" ] && [ -f ".env.example" ] && cp .env.example .env
mkdir -p local-files data

get_env() {
    grep -E "^\s*$1=" .env 2>/dev/null | cut -d '=' -f2 | tr -d ' ' | tr -d '"' | tr -d "'" || echo "$2"
}

set_env() {
    local key="$1"
    local val="$2"
    if grep -qE "^\s*#?\s*$key=" .env; then
        sed -i "s|^\s*#\?\s*$key=.*|$key=$val|" .env
    else
        echo "$key=$val" >> .env
    fi
}

sync_encryption_key() {
    local config_file="data/config"
    local config_key=""
    if [ -f "$config_file" ]; then
        config_key=$(grep -oE '"encryptionKey"\s*:\s*"[^"]+"' "$config_file" 2>/dev/null | cut -d '"' -f4)
    fi

    local env_key
    env_key=$(get_env "N8N_ENCRYPTION_KEY" "")

    if [ -n "$config_key" ]; then
        if [ "$env_key" != "$config_key" ]; then
            set_env "N8N_ENCRYPTION_KEY" "$config_key"
        fi
        export N8N_ENCRYPTION_KEY="$config_key"
    elif [ -n "$env_key" ]; then
        mkdir -p data
        printf '{\n\t"encryptionKey": "%s"\n}\n' "$env_key" > "$config_file"
        export N8N_ENCRYPTION_KEY="$env_key"
    else
        local new_key
        new_key=$(openssl rand -hex 32 2>/dev/null || od -vN 32 -An -tx1 /dev/urandom | tr -d ' \n')
        set_env "N8N_ENCRYPTION_KEY" "$new_key"
        mkdir -p data
        printf '{\n\t"encryptionKey": "%s"\n}\n' "$new_key" > "$config_file"
        export N8N_ENCRYPTION_KEY="$new_key"
    fi
}

# Ensure persistent key and safe permissions
[ -z "$(get_env "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS" "")" ] && set_env "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS" "false"
[ -z "$(get_env "N8N_USER_FOLDER" "")" ] && set_env "N8N_USER_FOLDER" "./data"
[ -z "$(get_env "N8N_UNVERIFIED_PACKAGES_ENABLED" "")" ] && set_env "N8N_UNVERIFIED_PACKAGES_ENABLED" "true"
[ -z "$(get_env "N8N_RUNNERS_ENABLED" "")" ] && set_env "N8N_RUNNERS_ENABLED" "false"
sync_encryption_key

PORT=$(get_env "N8N_PORT" "5678")
PORT=${PORT:-5678}

start_docker() {
    USE_TUNNEL=$1
    if ! command -v docker &> /dev/null; then
        echo "[ERROR] Docker no está instalado."
        return
    fi
    if [ "$USE_TUNNEL" = "true" ]; then
        echo "[*] Levantando Cloudflare Quick Tunnel..."
        pkill -f "cloudflared" 2>/dev/null || true
        rm -f .cloudflare.log .cloudflare.url
        nohup cloudflared --logfile .cloudflare.log tunnel --url "http://127.0.0.1:$PORT" > /dev/null 2>&1 &
        sleep 4
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .cloudflare.log 2>/dev/null | head -n 1)
        if [ -n "$URL" ]; then
            echo "$URL/" > .cloudflare.url
            set_env "N8N_WEBHOOK_URL" "$URL/"
            echo "[OK] URL Pública: $URL/"
        fi
    fi
    docker compose up -d
    echo "[OK] n8n activo en http://localhost:$PORT"
}

start_node() {
    USE_TUNNEL=$1

    # Comprobar si n8n ya está activo
    if curl -s "http://127.0.0.1:$PORT/healthz" 2>/dev/null | grep -q '"status":"ok"'; then
        echo "[OK] n8n ya se encuentra en ejecución en el puerto $PORT."
        if [ "$USE_TUNNEL" = "true" ]; then
            echo "[*] Reconectando únicamente Cloudflare Quick Tunnel..."
            pkill -f "cloudflared" 2>/dev/null || true
            rm -f .cloudflare.log .cloudflare.url
            nohup cloudflared --logfile .cloudflare.log tunnel --url "http://127.0.0.1:$PORT" > /dev/null 2>&1 &
            sleep 4
            URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .cloudflare.log 2>/dev/null | head -n 1)
            if [ -n "$URL" ]; then
                echo "$URL/" > .cloudflare.url
                export N8N_WEBHOOK_URL="$URL/"
                set_env "N8N_WEBHOOK_URL" "$URL/"
                echo "[OK] Túnel de Cloudflare reconectado exitosamente sin reiniciar n8n."
                echo "[OK] URL Pública: $URL/"
            fi
        fi
        return
    fi

    if ! command -v node &> /dev/null; then
        echo "[ERROR] Node.js no está instalado."
        return
    fi
    if ! command -v n8n &> /dev/null; then
        echo "[*] Instalando n8n globalmente..."
        npm install -g n8n --legacy-peer-deps --omit=optional
    fi
    export N8N_USER_FOLDER="$(pwd)/data"
    export N8N_PORT="$PORT"
    export N8N_SSRF_PROTECTION_ENABLED="false"
    export N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS="false"
    export N8N_PROXY_HOPS="1"
    export N8N_UNVERIFIED_PACKAGES_ENABLED="true"
    export N8N_RUNNERS_ENABLED="false"
    unset WEBHOOK_URL 2>/dev/null || true
    
    ENC=$(get_env "N8N_ENCRYPTION_KEY" "")
    [ -n "$ENC" ] && export N8N_ENCRYPTION_KEY="$ENC"

    if [ "$USE_TUNNEL" = "true" ]; then
        echo "[*] Levantando Cloudflare Quick Tunnel..."
        pkill -f "cloudflared" 2>/dev/null || true
        rm -f .cloudflare.log .cloudflare.url
        nohup cloudflared --logfile .cloudflare.log tunnel --url "http://127.0.0.1:$PORT" > /dev/null 2>&1 &
        sleep 4
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .cloudflare.log 2>/dev/null | head -n 1)
        if [ -n "$URL" ]; then
            echo "$URL/" > .cloudflare.url
            export N8N_WEBHOOK_URL="$URL/"
            set_env "N8N_WEBHOOK_URL" "$URL/"
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
    
    local is_net_up=false
    if nc -z -w 1 1.1.1.1 443 2>/dev/null || curl -s --connect-timeout 1 -I https://1.1.1.1 >/dev/null 2>&1; then
        is_net_up=true
        echo "Conexión: CONECTADO (Internet OK)"
    else
        echo "Conexión: DESCONECTADO (Sin acceso a Internet)"
    fi

    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/healthz" | grep -q "200"; then
        echo "Local:    http://localhost:$PORT -> EN LÍNEA (200 OK)"
    else
        echo "Local:    http://localhost:$PORT -> DETENIDO"
    fi

    if [ -f ".cloudflare.url" ] && pgrep -f "cloudflared" >/dev/null 2>&1; then
        local url clean_url
        url=$(cat .cloudflare.url)
        clean_url="${url%/}"
        if [ "$is_net_up" = "false" ]; then
            echo "Túnel:    $clean_url/ -> DESCONECTADO (Sin Internet)"
        elif curl -s --connect-timeout 4 --max-time 5 "$clean_url/healthz" 2>/dev/null | grep -q '"status":"ok"'; then
            echo "Túnel:    $clean_url/ -> EN LÍNEA (Accesible)"
        else
            echo "Túnel:    $clean_url/ -> RECONECTANDO..."
        fi
    else
        echo "Túnel:    Inactivo"
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
        while true; do
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
                1) start_docker false; read -p "Presiona Enter para volver...";;
                2) start_docker true; read -p "Presiona Enter para volver...";;
                3) start_node false; read -p "Presiona Enter para volver...";;
                4) start_node true; read -p "Presiona Enter para volver...";;
                5) stop_all; read -p "Presiona Enter para volver...";;
                6) show_status; read -p "Presiona Enter para volver...";;
                0) exit 0;;
                *) echo "Opción no válida."; sleep 1;;
            esac
        done
        ;;
esac
