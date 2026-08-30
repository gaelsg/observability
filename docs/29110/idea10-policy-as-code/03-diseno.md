# Diseño — Idea 10: Policy-as-code con OPA Gatekeeper

Según proceso **SI.3** del Perfil Básico ISO/IEC 29110.

## Componentes

```
observability (repo git)
   │
   ├── gitops/policies/templates/   ── ArgoCD Application "policies-templates"
   │      4x ConstraintTemplate (Rego)
   │              │
   │              ▼ (Gatekeeper reconcilia, crea CRD dinamicamente -- asincrono)
   │      constraints.gatekeeper.sh/v1beta1 {K8sRequireNonRoot, K8sRequireResources, ...}
   │
   └── gitops/policies/constraints/  ── ArgoCD Application "policies-constraints"
          4x Constraint (instancias de los CRDs de arriba)
                  │
                  ▼
          Gatekeeper admission webhook (ValidatingWebhookConfiguration)
                  │
                  ▼
          kubectl apply -f pod.yaml ──► API server ──► webhook evalua ──► admite o rechaza
```

## Decisiones de diseño

**Verificar quién rompería las políticas antes de escribirlas, no después.** Se inspeccionaron los pods de ArgoCD (manifiesto oficial, ya desplegado) contra los 4 criterios planeados — ninguno declara `resources`, la mayoría no setea `runAsNonRoot`. En vez de descubrir esto activando las políticas y viendo ArgoCD marcado como no conforme (o peor, roto si se hubiera usado un modo mutante en vez de solo validación), se excluyeron `kube-system`/`gatekeeper-system`/`argocd` desde el diseño inicial — son infraestructura de plataforma que este proyecto no controla ni intenta gobernar con estas políticas.

**Rego escrito a mano para las 4 políticas, no la librería oficial de Gatekeeper (`gatekeeper-library`).** Existen `ConstraintTemplate` prearmados para patrones comunes como estos — usarlos hubiera sido más rápido, pero el objetivo de aprendizaje de esta idea es entender Rego, no solo aplicar plantillas. Efecto secundario real: se encontró y corrigió un error de sintaxis propio (`in` sin import), evidencia de que se estaba escribiendo Rego de verdad, no copiando algo ya probado.

**Dos `Application` de ArgoCD (`policies-templates`, `policies-constraints`), no una sola con `sync-wave`.** Intentado primero con `sync-wave` (mecanismo estándar de ArgoCD para ordenar recursos dentro de una sincronización) — falló. La razón real: ArgoCD valida todos los recursos de una sincronización contra el esquema de tipos descubierto de la API *antes* de empezar a aplicar nada, así que un `Constraint` cuyo CRD todavía no existe hace fallar toda la sincronización sin importar en qué wave esté. Separar en dos `Application` hace que cada una tenga su propio ciclo de sincronización/reintento independiente — la de `constraints` reintenta sola (política de reintento explícita, `selfHeal`) hasta que el CRD generado por Gatekeeper ya existe, sin intervención manual más allá del primer `kubectl apply` de ambas `Application`.

**Modo enforcement directo (deny), no dry-run/auditoría primero.** El cluster solo tenía un workload real (Jaeger, Idea 9), ya diseñado desde el principio siguiendo estas mismas prácticas — no había riesgo real de que activar las políticas en modo estricto rompiera algo ya desplegado. En un cluster con más carga de trabajo preexistente y desconocida, la secuencia correcta sería auditar primero (`enforcementAction: dryrun`) para medir el impacto antes de bloquear — documentado como el enfoque correcto para ese escenario, no aplicable acá.

**`failurePolicy: Ignore` en el webhook (heredado del manifiesto oficial, verificado no cambiado).** Si Gatekeeper cae, el cluster sigue admitiendo recursos en vez de bloquear todas las operaciones — un sistema de políticas que puede tumbar el cluster entero por su propia falla es peor que uno que ocasionalmente deja pasar algo no conforme durante una interrupción breve.
