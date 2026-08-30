# Verificación — Idea 9: GitOps sobre k3s

Según proceso **SI.5** del Perfil Básico ISO/IEC 29110. Casos mapeados a los criterios de aceptación del [plan de proyecto](01-plan-proyecto.md).

| # | Caso de prueba | Resultado |
|---|---|---|
| 1 | ArgoCD sincroniza automáticamente, sin `kubectl apply` manual por recurso | ✅ Tras aplicar solo la `Application` (un recurso), ArgoCD creó namespace, deployment, 2 services e ingress por su cuenta. `status.sync.status: Synced`, `status.health.status: Healthy`, ~15s después de aplicar. |
| 2 | Un cambio manual se revierte automáticamente | ✅ `kubectl scale deployment jaeger --replicas=3` a mano → réplicas de vuelta a 1 en el cluster real (`kubectl get deployment` confirmó), `operationState` de ArgoCD mostró `startedAt`/`finishedAt` con **1 segundo** de diferencia. |
| 3 | UI de Jaeger alcanzable por hostname vía Traefik, no solo IP | ✅ `curl -H "Host: jaeger.homelab.local" http://192.168.8.92/` → `200`. `curl http://192.168.8.92/` (sin el header) → `404` — confirma ruteo real por host, no un puerto simplemente abierto. |
| 4 | OTLP alcanzable sin pasar por Traefik | ✅ Puerto 4317 (gRPC) acepta conexión TCP real; puerto 4318 (HTTP) respondió `200` a un POST de prueba a `/v1/traces`. |
| 5 | Recurso eliminado del repo se elimina del cluster | No probado explícitamente en esta iteración (no se eliminó ningún recurso de `gitops/jaeger/` durante la implementación) — `prune: true` es la configuración estándar documentada de ArgoCD, no verificado empíricamente en este caso puntual. |

## Caso adicional verificado: trace real de punta a punta tras la migración

`uv run devops-agent diagnose "cual es el estado del nodo de proxmox"` desde `devops-multiagent`, con `OTEL_EXPORTER_OTLP_ENDPOINT` ya apuntando a `192.168.8.92:4317` (la nueva ubicación). Confirmado con `curl -H "Host: jaeger.homelab.local" http://192.168.8.92/api/services` → los 5 servicios esperados (`devops-multiagent`, `proxmox-mcp-server`, `rag-mcp-server`, `k8s-mcp-server`, `jaeger` mismo).

## Incidente durante la implementación

**CRD `applicationsets.argoproj.io` demasiado grande para `kubectl apply` normal.** `metadata.annotations: Too long: may not be more than 262144 bytes` — límite de la anotación `last-applied-configuration` que usa el apply del lado del cliente para calcular diffs. Resuelto con `kubectl apply --server-side --force-conflicts`, que no depende de esa anotación. El manifiesto oficial de instalación se había descargado y revisado (recuento de tipos de recursos) antes de aplicarlo, no aplicado a ciegas desde la URL — el error se encontró corriendo el comando real, no algo que se pudiera haber anticipado leyendo el YAML.

## Conclusión
4 de 5 criterios verificados contra infraestructura real, incluyendo el más exigente (self-heal probado con un drift real, no solo confiado en la documentación de ArgoCD). El quinto (`prune`) queda como comportamiento estándar documentado pero no ejercido en esta iteración — se marca explícitamente como no verificado en vez de asumido.
