#!/usr/bin/env bash
# Escaneo periodico (Trivy) de las imagenes de terceros ya desplegadas en
# este stack -- no todo lo que corre en el homelab es codigo propio, y las
# ideas anteriores nunca auditaron lo que se pull de Docker Hub. Corre
# semanal via systemd --user timer en la workstation (mismo criterio que
# vault-backup.timer: la workstation tiene los binarios, el LXC no).
#
# Requiere TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID en .env (ver render-secrets.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

[ -f "$ENV_FILE" ] || { echo "Falta $ENV_FILE -- corre render-secrets.sh primero" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

IMAGES=(
  "docker.io/qdrant/qdrant:latest"
  "prom/prometheus:latest"
  "prom/node-exporter:latest"
  "prom/alertmanager:latest"
  "grafana/grafana:latest"
  "prompve/prometheus-pve-exporter:latest"
  "jaegertracing/jaeger:2.20.0"
)

REPORT="$REPO_ROOT/scan-report-$(date +%Y%m%d).txt"
: > "$REPORT"

SUMMARY=""
for img in "${IMAGES[@]}"; do
  COUNTS=$(trivy image --severity HIGH,CRITICAL --scanners vuln --quiet --format json "$img" 2>/dev/null \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
crit = high = 0
for r in d.get('Results') or []:
    for v in r.get('Vulnerabilities') or []:
        if v['Severity'] == 'CRITICAL':
            crit += 1
        elif v['Severity'] == 'HIGH':
            high += 1
print(f'{crit} {high}')
")
  read -r crit high <<< "$COUNTS"
  echo "$img: CRITICAL=$crit HIGH=$high" | tee -a "$REPORT"
  SUMMARY="${SUMMARY}${img}: ${crit} CRITICAL, ${high} HIGH\n"
done

echo "Reporte completo: $REPORT" >> "$REPORT"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d parse_mode="Markdown" \
  --data-urlencode text="🔍 *Scan semanal de imagenes (Trivy)*

$(echo -e "$SUMMARY")" \
  > /dev/null

echo "Enviado a Telegram. Reporte: $REPORT"
