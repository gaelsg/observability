# Diseño — Idea 9: GitOps sobre k3s

Según proceso **SI.3** del Perfil Básico ISO/IEC 29110.

## Componentes

```
observability (repo git, publico)
   │
   └── gitops/jaeger/  (namespace, deployment, service x2, ingress)
              │
              ▼ (leido directo, sin credenciales)
   ArgoCD (cluster k3s, namespace argocd)
   ├── application-controller  -- reconciliacion continua, detecta drift
   ├── repo-server             -- lee el repo git
   └── server                  -- API/UI de ArgoCD
              │
              ▼ syncPolicy.automated (prune + selfHeal)
   namespace "observability" (cluster k3s)
   ├── Deployment jaeger (1 replica, sin privilegios, limites de recursos)
   ├── Service jaeger-ui (ClusterIP)        ──► Ingress (Traefik, host jaeger.homelab.local)
   └── Service jaeger-otlp (LoadBalancer)   ──► IP del nodo directo (192.168.8.92:4317/4318)
```

## Decisiones de diseño

**Migrar un servicio real (Jaeger) en vez de desplegar algo nuevo descartable.** El cluster de la Idea 6 solo había corrido una carga de prueba (`nginxdemos/hello`) que se limpió al terminar de verificarlo — quedó "funciona pero no se usa". Migrar Jaeger le da un trabajo real y, de paso, usa el Traefik que viene instalado desde esa misma idea sin haber tenido ningún uso hasta ahora.

**Dos `Service` distintos para Jaeger, no uno solo.** `jaeger-ui` (`ClusterIP`, detrás de Ingress) para la UI, tráfico de navegador que se beneficia de ruteo por hostname. `jaeger-otlp` (`LoadBalancer`, directo) para OTLP — es tráfico de ingesta entre servicios (gRPC y HTTP de un protocolo de telemetría), no tiene sentido pasarlo por un Ingress HTTP pensado para navegadores; exponerlo directo con la IP del nodo es más simple y es exactamente el mismo patrón de exposición que tenía en Docker Compose (puerto directo).

**`kubectl apply --server-side` para el manifiesto de instalación de ArgoCD, no `apply` normal.** Encontrado en la práctica, no anticipado: el CRD `applicationsets.argoproj.io` es demasiado grande para la anotación `last-applied-configuration` que usa el `apply` del lado del cliente (límite de 256KB). Server-side apply no depende de esa anotación — usa field management gestionado por el propio API server. Mismo criterio de "verificar contra el sistema real, no asumir que el manifiesto oficial se aplica sin fricción" que ya apareció varias veces en el roadmap.

**`selfHeal: true`, no solo `prune: true`.** El objetivo explícito de esta idea es demostrar GitOps real, no solo "un deploy inicial declarativo" — sin `selfHeal`, un cambio manual al cluster quedaría sin corregir hasta el próximo sync manual, indistinguible en la práctica de no tener GitOps para nada. Se verificó con un drift real (`kubectl scale --replicas=3`), no se asumió que la opción funcionaría como dice la documentación.

**Manifiesto de la `Application` de ArgoCD aplicado una vez a mano, no sincronizado por GitOps de sí mismo.** Un patrón "app of apps" (una Application raíz que gestiona la Application de Jaeger) hubiera sido más "puro" pero es una capa de indirección innecesaria para un solo workload gestionado. El archivo vive versionado en el repo (`gitops/argocd-application.yaml`) para reproducibilidad y documentación, pero su aplicación inicial es un paso manual explícito — igual que la instalación de ArgoCD mismo.

**Repo público, sin credenciales de git para ArgoCD.** Consistente con el resto del roadmap (menor privilegio, menos credenciales de larga vida): como `observability` ya es público, ArgoCD lo lee sin necesitar un token de acceso ni una llave SSH — una credencial menos que rotar o filtrar.

**Storage de Jaeger en memoria, igual que en Docker Compose.** La decisión de la Idea 7 (persistencia en v2 requiere un `config.yaml` de pipeline propio, no justificado para datos de traces) no cambia por estar ahora en Kubernetes — se mantiene el mismo criterio, no se reabre la discusión sin una razón nueva.
