# Plan de Proyecto — Idea 9: GitOps sobre k3s

Según proceso **PM.1** del Perfil Básico ISO/IEC 29110. Tercera idea post-roadmap ([[project-roadmap2-bigtech]]).

## Objetivo
Darle un uso real al cluster k3s de la Idea 6 — hasta ahora solo corrió una carga de prueba descartable. Migrar un servicio real (Jaeger, de la Idea 7) desde Docker Compose al cluster, gestionado declarativamente por ArgoCD, con reconciliación automática de drift (GitOps de verdad, no solo "aplicar YAML una vez").

## Alcance

**Incluye:**
- ArgoCD instalado en el cluster k3s.
- Migración completa de Jaeger: Docker Compose (LXC `observability`) → Kubernetes (cluster k3s), manifiestos versionados en `gitops/jaeger/` de este repo.
- Exposición de la UI vía el Traefik que k3s ya trae (Ingress) y del OTLP vía `LoadBalancer` directo.
- Actualización de `OTEL_EXPORTER_OTLP_ENDPOINT` en los 4 repos que mandan traces.
- Verificación real de `selfHeal` (no solo documentado — probado con un drift manual).

**No incluye (fuera de alcance v1):**
- App-of-apps pattern (una sola `Application` para este único servicio, no vale la pena la capa extra de indirección con un solo workload gestionado).
- Migrar Prometheus/Grafana/Alertmanager a k3s también — quedan en Docker Compose, ningún motivo para migrarlos ahora.
- DNS real para `jaeger.homelab.local` (AdGuard Home rewrite) — acceso vía `Host:` header manual documentado como suficiente para v1.
- Multi-nodo / alta disponibilidad del cluster — sigue siendo el mismo cluster single-node de la Idea 6.

## Entregables
1. ArgoCD instalado y corriendo en el cluster k3s.
2. `gitops/jaeger/` (namespace, deployment, services, ingress, kustomization) + `gitops/argocd-application.yaml` en `observability`.
3. `OTEL_EXPORTER_OTLP_ENDPOINT` actualizado en 4 repos.
4. Jaeger dado de baja de `docker-compose.yml`.
5. Esta serie de documentos 29110 + bitácoras en los repos tocados.

## Riesgos identificados
| Riesgo | Mitigación |
|---|---|
| ArgoCD consume demasiada RAM en un LXC de 4GB ya compartido con k3s | Verificado antes de instalar (headroom de 3.3GB libres) y después (footprint real ~220MB). |
| Migrar Jaeger rompe el tracing de los 4 repos que ya lo usan | Migración con downtime mínimo (parar el viejo, levantar el nuevo, actualizar URLs), verificada con un trace real de punta a punta antes de dar la idea por cerrada. |
| `selfHeal: true` revierte cambios manuales legítimos sin avisar | Aceptado como el comportamiento correcto de GitOps -- si algo necesita cambiar, cambia en git, no a mano en el cluster. Documentado explícitamente, no una sorpresa. |
| Exponer OTLP via un `LoadBalancer` público en la LAN sin autenticación | Mismo modelo de confianza que la exposición anterior (Docker Compose, puertos directos) -- LAN interna, no expuesto a internet. |

## Criterios de aceptación
- ArgoCD sincroniza los manifiestos automáticamente al aplicar la `Application`, sin pasos manuales adicionales de `kubectl apply` por recurso.
- La UI de Jaeger es alcanzable a través de Traefik por hostname (no solo por IP/puerto directo).
- Un drift manual del estado del cluster se revierte solo, verificado con un caso real (no solo leído en la documentación de ArgoCD).
- Un trace real generado desde `devops-multiagent` llega a la nueva ubicación de Jaeger, confirmado con la API real.
