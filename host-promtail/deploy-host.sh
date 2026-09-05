#!/usr/bin/env bash
# Correr como root en batman01, una sola vez. Instala Promtail desde el repo
# apt oficial de Grafana (paquete real, no un binario suelto bajado a mano) y
# lo apunta al Loki de la LXC observability.
set -euo pipefail

SRC="/root/host-promtail"
[ -f "$SRC/promtail-config.yml" ] || { echo "No encuentro $SRC/promtail-config.yml -- copia esta carpeta primero" >&2; exit 1; }

echo "== Agregando el repo apt de Grafana =="
apt-get install -y apt-transport-https gnupg2
mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list

echo "== Instalando promtail =="
apt-get update -qq
apt-get install -y promtail

echo "== Config =="
install -m 644 "$SRC/promtail-config.yml" /etc/promtail/config.yml
install -d -m 755 -o promtail -g nogroup /var/lib/promtail
usermod -aG systemd-journal promtail 2>/dev/null || true

echo "== Habilitando servicio =="
systemctl enable --now promtail
systemctl restart promtail

echo
echo "== Listo =="
systemctl status promtail --no-pager
