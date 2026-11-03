#!/usr/bin/env bash
cd "$(dirname "$0")"
echo ">>> Deteniendo n8n..."
docker compose down
echo ">>> n8n detenido con éxito."
