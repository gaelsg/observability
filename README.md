# observability

Prometheus + Grafana + Alertmanager para el homelab "Modo Ingeniería", con triage automático por IA cuando dispara una alerta real. Idea 3 de un roadmap de 6 (IaC → Secretos → **Observabilidad** → CI/CD → Evals de RAG → Kubernetes).

Documentación formal bajo `docs/29110/` (Perfil Básico ISO/IEC 29110), incluyendo los 3 incidentes reales de esta implementación; `docs/bitacora/` es el diario de implementación.

## Arquitectura

Corre como Docker Compose dentro del LXC `observability` (192.168.8.90, provisionado vía [`proxmox-iac`](https://github.com/gaelsg/proxmox-iac)):

- **Prometheus** — scrapea Proxmox (`pve-exporter`), Vault (métricas nativas), y el propio LXC (`node-exporter`).
- **Grafana** — datasource y dashboard 100% provisionados por archivo, password generado (no `admin`/`admin`).
- **Alertmanager** — agrupa alertas y las manda a un webhook.

**Jaeger ya no corre acá.** Migró al cluster k3s (Idea 9, post-roadmap) — ver sección propia más abajo. `gitops/jaeger/` en este mismo repo describe su estado deseado; el LXC `observability` sigue siendo la fuente de verdad para Prometheus/Grafana/Alertmanager (Docker Compose), no para Jaeger (Kubernetes + ArgoCD).

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

## Escaneo semanal de imágenes de terceros (Idea 8, post-roadmap)

`scripts/scan-images.sh` + `systemd/image-scan.timer` (semanal, workstation) — escanea con Trivy las 7 imágenes de terceros que corren en este stack (más Qdrant, de `rag-mcp-server`) y manda un resumen por Telegram. Línea base real: Qdrant con 3 CRITICAL sin fix disponible todavía en Debian (documentado, no ignorado), Grafana con 164 HIGH, el resto entre 0 y 14. Ver [`k8s-mcp-server`](https://github.com/gaelsg/k8s-mcp-server#supply-chain-build-scan-sbom-firma) para el pipeline completo de build+scan+SBOM+firma de una imagen propia.

## Jaeger sobre k3s, gestionado por GitOps (Idea 9, post-roadmap)

`gitops/jaeger/` — manifiestos de Kubernetes (namespace, deployment, services, ingress) para Jaeger, sincronizados al cluster k3s ([`k8s-mcp-server`](https://github.com/gaelsg/k8s-mcp-server)) por [ArgoCD](https://argo-cd.readthedocs.io/), instalado en el propio cluster. `syncPolicy.automated` con `selfHeal: true` — no es solo "desplegar una vez desde YAML", es GitOps de verdad: un cambio manual al cluster (probado en real, escalando el deployment a 3 réplicas a mano) se revierte solo en ~1 segundo para volver a coincidir con lo que dice el repo.

- **UI:** expuesta vía el Traefik que k3s ya trae desde la Idea 6 (sin uso hasta ahora) — `Ingress` con host `jaeger.homelab.local` → `192.168.8.92`. Sin una entrada DNS/hosts real todavía (agregar un rewrite en AdGuard Home o una línea en `/etc/hosts` es un paso manual pendiente); mientras tanto, accesible con `curl -H "Host: jaeger.homelab.local" http://192.168.8.92/`.
- **OTLP (4317 gRPC, 4318 HTTP):** vía `LoadBalancer` directo, no Ingress — es tráfico de ingesta entre servicios, no de navegador, Traefik no aporta nada ahí. k3s le asigna la IP del propio nodo (`192.168.8.92`).
- **Storage:** sigue en memoria, mismo criterio que en Docker Compose (Idea 7) — no justifica la complejidad de configurar persistencia en Jaeger v2 para datos de traces.

`OTEL_EXPORTER_OTLP_ENDPOINT` actualizado de `192.168.8.90` a `192.168.8.92` en los 4 repos que mandan traces (`devops-multiagent`, `proxmox-mcp-server`, `rag-mcp-server`, `k8s-mcp-server`).

## Policy-as-code con OPA Gatekeeper (Idea 10, post-roadmap)

`gitops/policies/` — 4 políticas reales, exigidas por el cluster en el momento de crear un Pod, no solo documentadas:

- **`require-non-root`** — todo contenedor debe correr con `runAsNonRoot: true`.
- **`require-resources`** — todo contenedor debe declarar `requests`/`limits` de CPU y memoria.
- **`disallow-latest-tag`** — ningún contenedor puede usar la tag `:latest` (mismo criterio que fijar las actions de CI por SHA, Idea 8).
- **`require-drop-capabilities`** — todo contenedor debe dropear `ALL` capabilities y no correr `privileged`.

Excluyen `kube-system`/`gatekeeper-system`/`argocd` a propósito — son infraestructura de plataforma, no cargas de aplicación (verificado: los pods oficiales de ArgoCD no cumplirían estas políticas).

**Verificado con un rechazo real, no solo "el YAML parece correcto":**

```
$ kubectl apply -f pod-sin-cumplir.yaml
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
[require-non-root] el contenedor 'test' debe correr con runAsNonRoot: true...
[require-drop-capabilities] el contenedor 'test' no dropea ninguna capability...
[require-resources] el contenedor 'test' no tiene resources.limits.memory...
[disallow-latest-tag] el contenedor 'test' usa la tag ':latest'...
```

Un pod que sí cumple se acepta sin fricción; el `deployment` de Jaeger (desplegado antes de estas políticas) siguió `Synced`/`Healthy` sin cambios — las políticas no rompieron nada ya desplegado, porque ya cumplía desde el diseño original (Idea 9).

**Dos incidentes reales de implementación, ambos de GitOps + Gatekeeper, no de las políticas en sí:** un `ConstraintTemplate` con un error real de sintaxis Rego (`in` sin el import necesario), y un problema de orden — los `Constraint` no se pueden aplicar en la misma sincronización que los `ConstraintTemplate` que los definen (el CRD se registra de forma asíncrona); los `sync-wave` de ArgoCD no alcanzan para resolverlo, hizo falta separar en dos `Application` independientes. Detalle completo en `docs/29110/idea10-policy-as-code/`.

## Pendiente
- Entrada DNS real para `jaeger.homelab.local` (AdGuard Home rewrite) — hoy solo accesible con `Host:` header manual.
- Métricas de contenedores Docker de LXC 101 vía cAdvisor (fuera de alcance v1).
