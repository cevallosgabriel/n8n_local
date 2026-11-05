# 🚀 n8n Unified Local Stack

[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)
[![Node.js](https://img.shields.io/badge/Node.js-Ready-green.svg)](https://nodejs.org/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-orange.svg)](https://www.cloudflare.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)]()

Gestor de automatización unificado para **n8n Community Edition**. Diseñado para adaptarse dinámicamente a cualquier entorno: funciona tanto con **Docker** como de forma nativa con **Node.js** (ideal para equipos con 8 GB de RAM o sin virtualización activada en BIOS), con soporte integrado para **Cloudflare Tunnel** (URLs públicas HTTPS inmediatas sin abrir puertos).

---

## 💻 Requisitos y Compatibilidad

| Entorno | RAM Mínima | Virtualización (VT-x / AMD-V) | Recomendado para |
| :--- | :--- | :--- | :--- |
| **Modo Docker** | 8 GB | Requerida | Entornos con Docker Desktop ya operativo |
| **Modo Node.js** | 4 GB - 8 GB | **No requerida** | Equipos de 8GB RAM, Windows modificado o sin virtualización |

---

## 🚀 Inicio en 1 Clic

### En Windows:
Haz doble clic en **`n8n.bat`** o ejecuta en PowerShell:
```powershell
.\n8n.ps1
```

Aparecerá el menú interactivo:

```text
==========================================================
               n8n Unified Stack Manager                  
==========================================================
Entorno detectado:
  * Docker:         Disponible / No instalado
  * Virtualización: Habilitada / Deshabilitada (Usa Node.js)
  * Node.js:        Disponible / No instalado
----------------------------------------------------------
Opciones:
  [1] Iniciar con Docker (Localhost)
  [2] Iniciar con Docker + Cloudflare Tunnel (Webhook Público)
  [3] Iniciar con Node.js (Localhost - Ligero, ideal para 8GB RAM)
  [4] Iniciar con Node.js + Cloudflare Tunnel (Ligero + Webhook)
  [5] Detener todos los servicios
  [6] Ver estado
  [0] Salir
==========================================================
```

### Ejecución directa por comando (CLI):
```powershell
.\n8n.ps1 -Action docker-local     # Docker en http://localhost:5678
.\n8n.ps1 -Action docker-tunnel    # Docker + URL pública Cloudflare
.\n8n.ps1 -Action node-local       # Node.js nativo (Bajo consumo de RAM)
.\n8n.ps1 -Action node-tunnel      # Node.js + URL pública Cloudflare
.\n8n.ps1 -Action stop             # Detener todo
.\n8n.ps1 -Action status           # Ver estado del sistema
```

### En Linux / macOS:
```bash
chmod +x n8n.sh
./n8n.sh
```

---

## 🌐 Webhooks con Cloudflare Tunnel

Si seleccionas cualquiera de las opciones con túnel (Opción 2 o 4):
1. El script descarga e inicia `cloudflared` de forma automática y transparente.
2. Genera una URL pública segura del tipo `https://xxxx.trycloudflare.com/`.
3. Inyecta automáticamente dicha URL en `WEBHOOK_URL` para que nodos como **Telegram, WhatsApp, Stripe o GitHub** funcionen al instante.

---

## 📁 Persistencia de Datos

* **Modo Docker:** Los datos se almacenan en el volumen de Docker configurado en `docker-compose.yml`.
* **Modo Node.js:** Los datos se guardan de forma persistente dentro de la carpeta local `data/` del proyecto.
* Ningún dato sensible, flujo o credencial se sube a GitHub gracias al `.gitignore`.

---

## 📄 Licencia y Descargo Legal

Este proyecto es una herramienta comunitaria de orquestación bajo licencia **[MIT](LICENSE)**.

* **n8n** es una marca registrada de **n8n GmbH**. El uso de n8n está regido por su [Sustainable Use License](https://docs.n8n.io/sustainable-use-license/). Este repositorio no modifica, redistribuye ni comercializa el código fuente ni los binarios de n8n, ni cuenta con patrocinio o afiliación oficial con n8n GmbH.
* **Docker** y **Cloudflare** son marcas registradas de sus respectivos titulares.
