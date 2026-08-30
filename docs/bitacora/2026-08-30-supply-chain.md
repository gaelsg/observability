# 2026-08-30 — Escaneo semanal de imágenes de terceros (Idea 8, post-roadmap)

Parte de la Idea 8 (ver `k8s-mcp-server/docs/29110/idea8-supply-chain/` para el detalle completo). Esta entrada es solo el lado de este repo.

## Cambio
- `scripts/scan-images.sh` (nuevo) — escanea con Trivy las 7 imágenes de terceros ya desplegadas (Prometheus, Grafana, Alertmanager, node-exporter, pve-exporter, Jaeger, y Qdrant via `rag-mcp-server`), y manda un resumen por Telegram.
- `systemd/image-scan.timer` (semanal, workstation) + `.service` — mismo patrón que `vault-backup.timer` de `vault-secrets`.
- `render-secrets.sh` — ahora también trae `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` desde `secret/observability`.

## Credencial de Telegram duplicada, no compartida entre AppRoles
El bot de Telegram ya se usa desde `devops-multiagent` (`secret/devops-multiagent`). En vez de que el AppRole de `observability` lea el secreto de otro proyecto (rompería el aislamiento de la Idea 2), se copió la credencial a `secret/observability` con un script puntual que la trae de un secreto y la escribe en el otro sin que el valor pase por la terminal del asistente en ningún momento — usando el AppRole `vault-admin`, revocado al terminar.

## Línea base real
Escaneadas las 7 imágenes: Qdrant con 3 CRITICAL (sin fix disponible en Debian todavía, no ignorados por comodidad) y 55 HIGH; Grafana con 164 HIGH; el resto entre 0 y 14 HIGH. Nada de esto se "arregló" ahora — es exactamente lo que este timer semanal existe para seguir monitoreando.

## Verificado
`bash scripts/scan-images.sh` corrido en real: mensaje de Telegram con el resumen de las 7 imágenes, confirmado recibido. Timer instalado y activo (`systemctl --user list-timers image-scan.timer`).
