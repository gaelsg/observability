# Especificación de Requisitos — Idea 9: GitOps sobre k3s

Según proceso **SI.2** del Perfil Básico ISO/IEC 29110.

## Requisitos funcionales

| ID | Requisito |
|---|---|
| RF1 | ArgoCD sincroniza automáticamente los manifiestos de `gitops/jaeger/` al cluster, sin intervención manual por recurso. |
| RF2 | Un cambio manual al estado del cluster que contradiga el repo se revierte automáticamente (`selfHeal`). |
| RF3 | La UI de Jaeger es alcanzable vía Traefik, ruteada por hostname (`jaeger.homelab.local`), no solo por IP directa. |
| RF4 | Los puertos OTLP (gRPC 4317, HTTP 4318) son alcanzables desde la LAN sin pasar por Traefik. |
| RF5 | Un recurso eliminado del repo se elimina del cluster (`prune`), no queda huérfano. |

## Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF1 | ArgoCD y Jaeger juntos no superan una fracción razonable de la RAM del LXC (4GB total, otros procesos del cluster ya usan parte). |
| RNF2 | El repo de manifiestos (`observability`, público) no requiere credenciales para que ArgoCD lo lea — sin secretos de git que administrar. |
| RNF3 | La migración de Jaeger no deja el servicio corriendo duplicado (Docker Compose + Kubernetes a la vez) más que el tiempo mínimo de la migración. |
| RNF4 | Los 4 repos que mandan traces siguen funcionando sin cambios de código, solo de configuración (`OTEL_EXPORTER_OTLP_ENDPOINT`). |

## Fuera de alcance
- Autenticación en la UI de Jaeger o en ArgoCD mismo (mismo modelo de confianza de LAN interna que el resto del stack de observabilidad).
- DNS real para el hostname de Ingress.
- Migrar cualquier otro componente de `observability` a Kubernetes.
