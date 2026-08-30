# Diseño — Idea 3: Observabilidad + AIOps

Según proceso **SI.3** del Perfil Básico ISO/IEC 29110.

## Arquitectura

```
observability/                    (LXC 102, 192.168.8.90, provisionado en la Idea 1)
├── docker-compose.yml            → prometheus, pve-exporter, node-exporter, alertmanager, grafana
├── prometheus/
│   ├── prometheus.yml            → scrape configs (pve, vault, node-exporter, self)
│   ├── alert-rules.yml           → TargetDown, HighCPU, LowDiskSpace
│   └── vault-ca.pem              → CA de vault-secrets, para verificar TLS al scrapear Vault
├── alertmanager/
│   └── alertmanager.yml.template → receiver webhook, secreto como placeholder
├── grafana/
│   ├── provisioning/             → datasource + dashboard providers, 100% declarativo
│   └── dashboards/homelab.json   → CPU/memoria del nodo, estado VMs/LXCs, disco, Vault activo
└── scripts/render-secrets.sh     → Vault (AppRole) -> .env + alertmanager.yml locales, gitignored

devops-multiagent/
└── src/devops_multiagent/webhook.py   → nuevo servicio FastAPI, "devops-agent webhook"
```

## Flujo de una alerta

1. Prometheus evalúa `alert-rules.yml` cada `evaluation_interval` contra los 4 targets reales.
2. Si una regla se cumple por su `for`, pasa a Alertmanager.
3. Alertmanager agrupa (`group_wait: 30s`) y llama al webhook `http://<workstation>:8090/webhook/alertmanager?token=...`.
4. `devops-multiagent webhook` valida el shared secret + la forma del payload, manda la alerta cruda a Telegram, invoca al Diagnostician con el contexto real de la alerta, y manda el diagnóstico como segundo mensaje.
5. Al resolverse (`send_resolved: true`), Alertmanager vuelve a llamar al webhook con `status: resolved` por cada alerta — hoy se trata igual que cualquier otra alerta (mismo flujo de Telegram + Diagnostician), no hay lógica especial todavía para distinguir resuelto de disparado en el mensaje.

## Decisiones técnicas

**Servicio de webhook separado del dashboard existente, no el mismo proceso.** `devops-multiagent serve` (Idea 4 del roadmap anterior) está deliberadamente en `127.0.0.1` sin auth. Alertmanager corre en otro LXC y necesita alcanzar el webhook por LAN — en vez de aflojar esa decisión ya tomada, se creó un servicio nuevo (`devops-agent webhook`, puerto 8090, bind `0.0.0.0`) con su propia superficie mínima: un solo endpoint, protegido por un shared secret que vive en Vault, sin panel ni ninguna otra capacidad expuesta.

**Autenticación del webhook: shared secret, no firma criptográfica.** Alertmanager no firma sus webhooks nativamente. La defensa real es el `token` en la query string (generado con `openssl rand -hex 24`, en Vault, nunca en un archivo versionado) más un chequeo de forma del payload (RNF3) — insuficiente para internet abierto, razonable para LAN-only, documentado como el límite real de esta versión.

**Todos los secretos de este proyecto nacen en Vault, nunca tocan un `.env` versionado.** A diferencia de `proxmox-mcp-server` (migrado retroactivamente en la Idea 2), este es el primer proyecto que nace *después* de Vault existir: el token de `prometheus@pve` se escribió directo en `secret/observability` sin pasar por un archivo local salvo el `.env` gitignored que `render-secrets.sh` genera bajo demanda.

**Password de Grafana generado, no `admin`/`admin`.** `openssl rand -base64 24`, guardado en Vault junto con el resto de los secretos de este proyecto.

**Métricas de Vault requieren un cambio de config no anticipado.** `/v1/sys/metrics` está protegido por token por defecto; hace falta `listener.telemetry.unauthenticated_metrics_access = true` en `vault.hcl`. A diferencia de `enable_unauthenticated_access` (Idea 2, sí reloadable por SIGHUP), este es un cambio dentro del bloque `listener`, que **no** se recarga en caliente — requirió `systemctl restart vault` y volver a desellar (3 llaves, sin ceremonia de root esta vez, ya no hacía falta).

**Regla de alerta para "Vault sellado" no implementada como se planeó.** No existe una métrica `vault_core_unsealed` (se confirmó con `curl` contra el exporter real antes de escribir la regla, no se asumió). Un Vault sellado probablemente deja de responder `/v1/sys/metrics` del todo, lo que ya lo cubriría `TargetDown` — pero esto no se verificó empíricamente porque hacerlo requería sellar Vault de nuevo solo para la prueba, y la política `admin-limited` (Idea 2) no tiene permiso `sys/seal` a propósito. Documentado como pendiente de confirmar la próxima vez que ocurra de forma natural.

## Fuera de diseño (explícitamente)
- Métricas de contenedores Docker de LXC 101 (`docker-host`) vía cAdvisor.
- Retirar el watcher de `devops-multiagent` — sigue corriendo en paralelo.
- Diferenciar el mensaje de Telegram entre alerta disparada y resuelta (hoy usan el mismo formato).
