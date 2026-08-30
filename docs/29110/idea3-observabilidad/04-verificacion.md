# Verificación — Idea 3: Observabilidad + AIOps

Según proceso **SI.5** del Perfil Básico ISO/IEC 29110. Casos mapeados a los criterios de aceptación del [plan de proyecto](01-plan-proyecto.md).

| # | Caso de prueba | Resultado |
|---|---|---|
| 1 | Prometheus scrapeando los 3+ targets con `up == 1` | ✅ 4 targets (`prometheus`, `node-exporter`, `pve`, `vault`), todos `health: up` vía `/api/v1/targets`. |
| 2 | Grafana accesible con password real, dashboard con datos reales | ✅ Login vía API con el password generado (no `admin`/`admin`). Dashboard "Homelab — batman01" provisionado automáticamente, verificado que sus paneles devuelven datos reales consultando el datasource proxy directamente (`pve_cpu_usage_ratio{id="node/batman01"}` → valor real, no vacío). |
| 3 | Una alerta de prueba **real** dispara el webhook, el Diagnostician explica, llega a Telegram | ✅ Se detuvo `node-exporter` de verdad (no una simulación de payload) durante ~4 minutos; `TargetDown` pasó a `firing` en Prometheus, Alertmanager la despachó al webhook real, `devops-multiagent webhook` la recibió (`200 OK` en logs), generó diagnóstico, y llegaron ambos mensajes a Telegram. Confirmado por el usuario. |
| 4 | El secreto de Prometheus para Proxmox nunca en texto plano en archivo versionado | ✅ Token de `prometheus@pve` escrito directo en `secret/observability` de Vault; el único lugar donde existe en texto plano es el `.env` local generado por `render-secrets.sh`, gitignored. |

## Incidentes durante la implementación

**Regla de alerta `VaultSealed` basada en una métrica que no existe.** Se planeó `vault_core_unsealed`; al revisar el output real de `/v1/sys/metrics` con `curl` no aparecía. Corregido eliminando la regla dedicada (queda cubierta por `TargetDown` en la práctica, no verificado empíricamente por evitar sellar Vault solo para probarlo — ver diseño).

**`/v1/sys/metrics` de Vault protegido por token, no anticipado en el plan.** Requirió `listener.telemetry.unauthenticated_metrics_access = true` en `vault.hcl`. A diferencia del cambio de la Idea 2 (`enable_unauthenticated_access`, sí reloadable por SIGHUP), este vive dentro del bloque `listener` y **no** se recarga en caliente — hizo falta `systemctl restart vault` y un unseal manual normal (3 llaves, sin ceremonia de root).

**Firewall del workstation bloqueaba el webhook.** `ufw` estaba activo y no dejaba pasar conexiones entrantes al puerto 8090 desde el LXC — la primera alerta real quedó "activa" en Alertmanager pero sin poder entregarse (confirmado con un `curl` directo desde el LXC al puerto del webhook: timeout). Resuelto con `sudo ufw allow from 192.168.8.0/24 to any port 8090 proto tcp`; Alertmanager reintentó automáticamente sin necesidad de reiniciar nada, y la entrega se completó.

**Codename de Ubuntu 26.04 ("resolute") no soportado directo por el apt repo de Docker.** Se resolvió usando el script de instalación oficial (`get.docker.com`) en vez de armar el repo APT a mano — más robusto ante distribuciones muy nuevas.

## Conclusión
Los 4 criterios de aceptación se cumplen, incluyendo la prueba más exigente (alerta real de infraestructura, no simulada, de punta a punta hasta Telegram). Tres incidentes reales documentados, ninguno bloqueante — el patrón de "verificar contra el sistema real antes de asumir" (confirmar métricas con `curl`, confirmar conectividad con un `curl` directo desde el otro lado) volvió a pagar, igual que en las Ideas 1 y 2.
