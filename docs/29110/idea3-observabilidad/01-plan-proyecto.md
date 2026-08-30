# Plan de Proyecto — Idea 3: Observabilidad + AIOps

Según proceso **PM.1** del Perfil Básico ISO/IEC 29110.

## Objetivo
Reemplazar el monitoreo actual (el watcher de `devops-multiagent`, polling cada 15 min sin métricas reales) por un stack de observabilidad estándar de industria — Prometheus + Grafana + Alertmanager — con triage automático por IA cuando dispara una alerta real, no un simple diff de estado.

## Alcance

**Incluye:**
- Prometheus + Grafana + Alertmanager como contenedores Docker en el LXC `observability` (192.168.8.90, ya provisionado en la Idea 1, `nesting=true` habilitado para esto).
- Scrape targets v1: métricas de Proxmox (nodo, VMs, LXCs) vía `pve-exporter`, métricas nativas de Vault (`/v1/sys/metrics`), y auto-monitoreo del propio LXC (`node_exporter`).
- Reglas de alerta básicas (nodo caído, Vault sellado, uso de CPU/disco alto).
- Webhook de Alertmanager → nuevo endpoint en `devops-multiagent` (ya tiene al Diagnostician) que pide una explicación en lenguaje natural de la alerta y la manda por Telegram (reusa `notify.py` de un roadmap anterior) — mismo patrón que el watcher, pero disparado por una alerta real de Prometheus, no por polling.
- Credenciales de este proyecto nacen directo en Vault (Idea 2) — es el primer proyecto del roadmap que no pasa por un `.env` con secretos reales en ningún momento.

**No incluye (fuera de alcance v1):**
- Métricas de contenedores Docker dentro de LXC 101 (`docker-host`) vía cAdvisor — requeriría acceso SSH nuevo a un LXC gestionado a mano fuera de este roadmap. Documentado como extensión futura, no bloqueante.
- Retirar el watcher de `devops-multiagent` — sigue corriendo en paralelo por ahora; se evalúa más adelante si Prometheus lo vuelve redundante.
- Alta disponibilidad / retención larga de métricas — un solo nodo Prometheus, retención por defecto, suficiente para un homelab.

## Entregables
1. Repo `observability` — `docker-compose.yml`, configs de Prometheus/Alertmanager/Grafana, provisioning de datasource y dashboard.
2. Token dedicado de Proxmox (`prometheus@pve`, solo lectura) y su secreto migrado a Vault desde el día uno.
3. Endpoint nuevo en `devops-multiagent` para recibir webhooks de Alertmanager y disparar triage con el Diagnostician.
4. Esta serie de documentos 29110 + bitácora.

## Riesgos identificados
| Riesgo | Mitigación |
|---|---|
| Grafana con password por defecto (`admin`/`admin`) expuesto en LAN | Password generado al azar, guardado en Vault (`secret/observability`), nunca el valor por defecto. |
| El webhook de Alertmanager dispara triage en cascada si hay una tormenta de alertas | Alertmanager agrupa/limita por `group_wait`/`repeat_interval` antes de llegar al webhook — no es responsabilidad del receptor deduplicar. |
| El nuevo token de Proxmox para Prometheus queda con más permiso del necesario | Rol `PVEAuditor` (ya existe, mismo que `mcp-agent`), scope `/`, pero *usuario* distinto — mismo criterio de credenciales dedicadas por propósito, no por servicio compartido. |

## Criterios de aceptación
- Prometheus scrapeando los 3 targets (Proxmox, Vault, node_exporter local) con `up == 1`.
- Grafana accesible con password real (no default), con al menos un dashboard mostrando datos reales.
- Una alerta de prueba real (forzada, no simulada) dispara el webhook, el Diagnostician genera una explicación, y llega a Telegram.
- El secreto de Prometheus para Proxmox nunca existe en texto plano en un archivo versionado ni en un `.env` — nace y vive en Vault.
