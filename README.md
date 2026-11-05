# 🚀 n8n Local Automation Stack

[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-Community%20Edition-EA4B71.svg)](https://n8n.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)]()

Entorno de automatización local basado en **n8n Community Edition (Gratis)**. Listo para ejecutarse con persistencia de datos, soporte de túneles externos para webhooks y comunicación directa con servicios locales.

---

## 💻 Requisitos y Limitaciones de Hardware

| Componente | Requisito Mínimo | Recomendado |
| :--- | :--- | :--- |
| **Memoria RAM** | **8 GB** | **16 GB o más** |
| **CPU** | 2 núcleos | 4 núcleos |
| **Almacenamiento** | 5 GB libres | 10 GB o más |

> ⚠️ **Advertencia de rendimiento:**
> * Equipos con **menos de 8 GB de RAM** experimentarán fallos de memoria, lentitud extrema o cierres inesperados al utilizar Docker.
> * En equipos de 8 GB de RAM, se recomienda no mantener múltiples aplicaciones pesadas abiertas simultáneamente mientras Docker esté en ejecución.

---

## 🚀 Inicio Rápido

### En Windows (PowerShell):
```powershell
# Iniciar n8n:
.\start.ps1

# O iniciar con túnel público para webhooks:
.\start.ps1 -Tunnel cloudflare
# o bien:
.\start.ps1 -Tunnel ngrok
```

### En Linux / macOS (Terminal):
```bash
chmod +x start.sh stop.sh
./start.sh
```

El script se encargará automáticamente de:
1. Generar el archivo `.env` a partir de `.env.example` si no existe.
2. Comprobar que Docker esté instalado y en ejecución.
3. Desplegar los contenedores en segundo plano.
4. Abrir la interfaz web en **`http://localhost:5678`**.

Para detener el entorno:
```powershell
# Windows:
.\stop.ps1

# Linux / macOS:
./stop.sh
```

---

## ⚙️ Configuración (.env)

El archivo `.env` permite ajustar parámetros básicos sin modificar los contenedores:

| Variable | Valor por Defecto | Descripción |
| :--- | :--- | :--- |
| `N8N_PORT` | `5678` | Puerto de acceso a n8n |
| `GENERIC_TIMEZONE` | `America/Bogota` | Zona horaria para tareas programadas |
| `TZ` | `America/Bogota` | Zona horaria del contenedor |
| `N8N_SSRF_PROTECTION_ENABLED` | `false` | Permite o bloquea peticiones a direcciones locales |
| `WEBHOOK_URL` | *(Vacío)* | URL pública HTTPS si se utiliza un túnel o dominio |

---

## 🌐 Webhooks Públicos (Túneles)

Para recibir eventos desde servicios externos en internet (webhooks con HTTPS):

* **Cloudflare Tunnel:** `.\start.ps1 -Tunnel cloudflare`
* **Ngrok:** `.\start.ps1 -Tunnel ngrok`

Copia la URL pública generada, asígnala a `WEBHOOK_URL` en tu `.env` y reinicia con `docker compose up -d`.

---

## 🔌 Servicios y Bases de Datos Locales

Para conectar n8n con bases de datos o servicios que corren en la máquina anfitriona fuera de Docker:

* **Host a utilizar:** `host.docker.internal`
* **Puertos habituales:** MySQL (`3306`), PostgreSQL (`5432`), SQL Server (`1433`), MongoDB (`27017`), Redis (`6379`).

---

## 🔒 Privacidad y Seguridad

* El archivo `.env`, historiales de flujos y datos locales están ignorados en `.gitignore` para prevenir filtraciones accidentales.
* Usa siempre `.env.example` como plantilla base al compartir o clonar el proyecto.

---

## 📄 Licencia y Descargo Legal

Este proyecto es una herramienta comunitaria de orquestación y automatización de despliegue bajo licencia **[MIT](LICENSE)**.

* **Descargo sobre n8n:** n8n es una marca registrada de **n8n GmbH**. La imagen oficial de n8n se descarga directamente desde sus repositorios oficiales y su uso está regido por la [Sustainable Use License de n8n](https://docs.n8n.io/sustainable-use-license/). Este repositorio no modifica, redistribuye ni comercializa el código fuente ni los binarios de n8n, ni cuenta con patrocinio o afiliación oficial con n8n GmbH.
* **Descargo sobre Docker y Cloudflare:** Las marcas Docker y Cloudflare pertenecen a sus respectivos titulares. Todos los derechos reservados a sus autores originales.

