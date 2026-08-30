# Especificación de Requisitos — Idea 3: Observabilidad

Según proceso **SI.2** del Perfil Básico ISO/IEC 29110.

## Requisitos funcionales

| ID | Requisito |
|---|---|
| RF1 | Prometheus debe scrapear métricas reales de Proxmox (nodo, VMs, LXCs), Vault, y el propio LXC de observabilidad. |
| RF2 | Grafana debe mostrar al menos un dashboard funcional con datos reales de esos targets, con datasource provisionado automáticamente (no configurado a mano en la UI). |
| RF3 | Alertmanager debe tener al menos 2 reglas de alerta reales (ej. nodo/target caído, Vault sellado) y un receiver que llame a un webhook HTTP. |
| RF4 | El webhook debe activar al Diagnostician (`devops-multiagent`) con el contenido real de la alerta, y el resultado debe llegar a Telegram — mismo canal que el watcher existente. |

## Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF1 | El secreto de Prometheus para Proxmox (token dedicado) debe vivir en Vault desde su creación — nunca debe existir en texto plano en un `.env` ni en un archivo versionado, ni siquiera transitoriamente. |
| RNF2 | El password de Grafana debe ser generado (no el default `admin`/`admin`), y almacenado en Vault, no en el `docker-compose.yml` ni en ningún archivo versionado. |
| RNF3 | El endpoint de webhook en `devops-multiagent` debe distinguir una alerta real de Alertmanager (firma/formato esperado) — no debe poder dispararse con cualquier POST arbitrario sin estructura reconocible. |
| RNF4 | La configuración de Prometheus/Alertmanager/Grafana debe ser 100% declarativa (archivos versionados) — ninguna configuración hecha a mano en las UIs que se pierda al recrear los contenedores. |

## Trazabilidad
RNF1-RNF2 son la primera aplicación real de Vault ([[project-vault-secrets]]) a un proyecto que nace *después* de que Vault ya existe — a diferencia de `proxmox-mcp-server` (migrado retroactivamente), aquí el secreto nunca debería tocar un `.env`. RNF4 sigue el mismo principio de "todo declarativo" de la Idea 1 (IaC), aplicado ahora a configuración de aplicación, no de infraestructura.
