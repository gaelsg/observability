# observability

Prometheus + Grafana + Alertmanager para el homelab "Modo Ingeniería", con triage automático por IA cuando dispara una alerta real. Idea 3 de un roadmap de 6 (IaC → Secretos → **Observabilidad** → CI/CD → Evals de RAG → Kubernetes).

Documentación formal bajo `docs/29110/` (Perfil Básico ISO/IEC 29110), incluyendo los 3 incidentes reales de esta implementación; `docs/bitacora/` es el diario de implementación.

## Arquitectura

Corre como Docker Compose dentro del LXC `observability` (192.168.8.90, provisionado vía [`proxmox-iac`](https://github.com/gaelsg/proxmox-iac)):

- **Prometheus** — scrapea Proxmox (`pve-exporter`), Vault (métricas nativas), y el propio LXC (`node-exporter`).
- **Grafana** — datasource y dashboard 100% provisionados por archivo, password generado (no `admin`/`admin`).
- **Alertmanager** — agrupa alertas y las manda a un webhook.
- **Jaeger** (Idea 7, post-roadmap) — backend de tracing distribuido para el sistema de agentes de [`devops-multiagent`](https://github.com/gaelsg/devops-multiagent). v2 (v1 está EOL desde dic-2025), storage en memoria. UI: http://192.168.8.90:16686/, OTLP en los puertos 4317 (gRPC) / 4318 (HTTP).

El webhook es un servicio nuevo en [`devops-multiagent`](https://github.com/gaelsg/devops-multiagent) (`devops-agent webhook`, puerto 8090, LAN) que activa al Diagnostician para explicar la alerta en lenguaje natural y la manda por Telegram — mismo canal que el watcher de un roadmap anterior, pero disparado por una alerta real de Prometheus, no por polling.

## Secretos: 100% Vault desde el día uno

A diferencia de proyectos migrados retroactivamente, este nació después de que Vault ya existía — su token de Proxmox, password de Grafana, y el shared secret del webhook nunca tocaron un archivo versionado. `scripts/render-secrets.sh` los trae de `secret/observability` (vía un AppRole dedicado) a un `.env`/`alertmanager.yml` locales, gitignored, justo antes de desplegar.

## Setup

```bash
# Secretos (requiere .observability-approle, ver vault-secrets)
bash scripts/render-secrets.sh

# Copiar al LXC y levantar
scp -i ~/.ssh/id_ed25519_iac -r docker-compose.yml .env prometheus alertmanager grafana \
  root@192.168.8.90:/opt/observability/
ssh -i ~/.ssh/id_ed25519_iac root@192.168.8.90 "cd /opt/observability && docker compose up -d"
```

Grafana: http://192.168.8.90:3001/ · Prometheus: http://192.168.8.90:9090/ · Alertmanager: http://192.168.8.90:9093/

## Sobrevive un reboot sin unidad systemd extra

Los contenedores usan `restart: unless-stopped` y el daemon de Docker está `enabled` en el LXC — a diferencia del error de Qdrant en la Idea 1 del roadmap anterior (un `podman run` sin política de reinicio), aquí quedó bien desde el primer despliegue.

## Pendiente
- Diferenciar el mensaje de Telegram entre alerta disparada y resuelta.
- Métricas de contenedores Docker de LXC 101 vía cAdvisor (fuera de alcance v1).
