# 🚀 n8n Universal Local Stack

[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-Community%20Edition-EA4B71.svg)](https://n8n.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)]()

Entorno de automatización profesional basado en **n8n Community Edition (100% Gratis)**, diseñado con enfoque **DevOps de despliegue en un clic**, sin datos hardcodeados, con persistencia garantizada, compatible con IA (Gemini, OpenAI, Anthropic), bases de datos locales y preparado para recibir webhooks mediante túneles seguros (**Cloudflare** / **Ngrok**).

---

## ✨ Características Principales

* 🔒 **Seguridad y Privacidad Garantizada:** Cero filtración de datos sensibles. El archivo `.env`, tokens, base de datos interna y archivos locales están rigurosamente excluidos en `.gitignore`.
* 🧩 **Cero Datos Hardcodeados:** Todo el stack se parametriza mediante variables de entorno y rutas relativas dinámicas. Funciona en cualquier máquina o sistema operativo.
* ⚡ **Detección Automática de Dependencias:** El script de inicio detecta automáticamente si falta el archivo `.env`, si Docker Desktop está instalado/apagado, y ofrece enlaces directos o instalación asistida con un solo clic.
* 🌐 **Soporte de Webhooks Públicos:** Soporte nativo para exponer tus webhooks a internet mediante **Cloudflare Tunnel** (sin costo) o **Ngrok**.
* 🐬 **Conexión Directa a Bases de Datos del Host:** Configurado con `host.docker.internal:host-gateway` para conectarse a tus bases de datos locales (MySQL, PostgreSQL, SQL Server, MongoDB, Redis) sin errores de red.
* 🛡️ **SSRF Configurable:** Pre-ajustado para desarrollo local para evitar el bloqueo de peticiones a `127.0.0.1` o APIs locales.

---

## 📁 Estructura del Repositorio

```text
n8n-local-stack/
├── .env.example             # Plantilla de configuración segura con valores por defecto
├── .gitignore               # Exclusión estricta de credenciales, datos y logs
├── docker-compose.yml       # Definición modular del servicio n8n y túneles
├── start.ps1                # Lanzador inteligente para Windows (PowerShell)
├── stop.ps1                 # Parada segura para Windows
├── start.sh                 # Lanzador para Linux y macOS
├── stop.sh                  # Parada para Linux y macOS
├── local-files/             # Carpeta montada en el contenedor (/files) para entrada/salida
└── README.md                # Documentación técnica
```

---

## 🚀 Inicio Rápido (Zero-Config)

### En Windows (PowerShell):
```powershell
# Iniciar n8n estándar:
.\start.ps1

# O iniciar n8n + Túnel de Cloudflare automático:
.\start.ps1 -Tunnel cloudflare

# O iniciar n8n + Túnel de Ngrok automático:
.\start.ps1 -Tunnel ngrok
```

### En Linux / macOS (Terminal):
```bash
chmod +x start.sh stop.sh
./start.sh
```

El script se encargará automáticamente de:
1. Crear tu archivo `.env` a partir de `.env.example` si no existe.
2. Comprobar que Docker esté instalado (si no lo tienes, te ofrece la descarga o instalación).
3. Levantar Docker si está apagado.
4. Desplegar los contenedores en segundo plano.
5. Abrir automáticamente tu navegador en **`http://localhost:5678`**.

Para detener el stack en cualquier momento:
```powershell
# Windows:
.\stop.ps1

# Linux / macOS:
./stop.sh
```

---

## ⚙️ Configuración (.env)

El archivo `.env` contiene toda la personalización sin tocar el código fuente:

| Variable | Valor por Defecto | Descripción |
| :--- | :--- | :--- |
| `N8N_PORT` | `5678` | Puerto HTTP donde escuchará n8n |
| `GENERIC_TIMEZONE` | `America/Bogota` | Zona horaria para flujos basados en tiempo (Cron) |
| `TZ` | `America/Bogota` | Zona horaria del sistema del contenedor |
| `N8N_SSRF_PROTECTION_ENABLED` | `false` | `false` para permitir peticiones a localhost/APIs locales |
| `WEBHOOK_URL` | *(Vacío)* | URL pública HTTPS para webhooks externos |
| `CONTAINER_NAME` | `n8n_production` | Nombre del contenedor Docker |
| `DATA_VOLUME_NAME` | `n8n_storage_data` | Nombre del volumen persistente de Docker |

---

## 🌐 Configuración de Webhooks Externos (Túneles)

Cuando conectas servicios externos como **Telegram, WhatsApp, Stripe o GitHub**, necesitas una URL pública con HTTPS.

### Opción 1: Cloudflare Tunnel (100% Gratis y Estable)
1. Con el comando integrado:
   ```powershell
   .\start.ps1 -Tunnel cloudflare
   ```
2. Cloudflare te entregará una URL como: `https://xxxx.trycloudflare.com`
3. En tu `.env`, configura:
   ```env
   WEBHOOK_URL=https://xxxx.trycloudflare.com/
   ```
4. Aplica los cambios: `docker compose up -d`

### Opción 2: Ngrok
1. Con el comando integrado:
   ```powershell
   .\start.ps1 -Tunnel ngrok
   ```
2. Copia la URL generada (`https://xxxx.ngrok-free.app`) y colócala en tu `.env` bajo `WEBHOOK_URL`.
3. Aplica los cambios: `docker compose up -d`

---

## 🐬 Conexión a Bases de Datos en la Máquina Anfitriona (Host)

Si tienes bases de datos corriendo en tu mismo sistema operativo fuera de Docker:

* **Host:** `host.docker.internal`
* **Puertos estándar:**
  * MySQL / MariaDB: `3306`
  * PostgreSQL: `5432`
  * SQL Server: `1433`
  * Redis: `6379`
  * MongoDB: `27017`

> **Importante para MySQL:** Asegúrate de que el usuario tenga permisos para conectarse desde cualquier host (`'usuario'@'%'`), no solo desde `localhost`.

---

## 🔒 Buenas Prácticas de Seguridad al Subir a GitHub

1. **Nunca hagas commit del archivo `.env`**: Ya está protegido en `.gitignore`.
2. **Usa siempre `.env.example`** para documentar nuevas variables sin poner contraseñas reales.
3. Si cambias de máquina, solo necesitas clonar el repositorio y ejecutar `.\start.ps1` (o `./start.sh`); todo se autoconfigurará sin errores.
