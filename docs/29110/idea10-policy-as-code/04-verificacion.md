# Verificación — Idea 10: Policy-as-code con OPA Gatekeeper

Según proceso **SI.5** del Perfil Básico ISO/IEC 29110. Casos mapeados a los criterios de aceptación del [plan de proyecto](01-plan-proyecto.md).

| # | Caso de prueba | Resultado |
|---|---|---|
| 1 | Pod que viola las 4 políticas es rechazado, con mensaje específico por violación | ✅ `kubectl apply` de un pod con `nginx:latest`, sin `securityContext`, sin `resources` → `Forbidden`, 6 mensajes de violación (2 de `require-resources`, 1 de cada una de las otras 3), cada uno nombrando el contenedor y la política exacta. |
| 2 | Pod que cumple todas las políticas es aceptado sin fricción | ✅ Pod con `runAsNonRoot: true`, `capabilities.drop: [ALL]`, `resources.requests`/`limits` completos, tag `nginx:1.27.3` (no `:latest`) → creado sin error, `ContainerCreating` normal. |
| 3 | El workload ya desplegado (Jaeger) sigue `Synced`/`Healthy` tras activar las políticas | ✅ `kubectl get application jaeger -n argocd` → `Synced Healthy`, mismo pod (`jaeger-66fdf77757-rd9cj`), misma edad — sin reinicio ni disrupción. |
| 4 | Las políticas están gestionadas por GitOps, no aplicadas a mano | ✅ `policies-templates` y `policies-constraints`, ambas `Synced`/`Healthy` en ArgoCD, sincronizadas desde `gitops/policies/` del repo. |

## Incidentes reales durante la implementación

**1. Error de sintaxis Rego: `not "ALL" in drops`.** Encontrado en el `status` del propio `ConstraintTemplate` (`kubectl get constrainttemplate k8srequiredropcapabilities -o jsonpath='{.status}'`): `rego_parse_error: unexpected identifier token`. Causa real: el operador `in` de Rego requiere `import future.keywords.in`, no habilitado por defecto en la versión de OPA embebida en Gatekeeper v3.23.1. Corregido con el patrón clásico de pertenencia por indexación (`drops[_] == "ALL"`), que no depende de ese import.

**2. Orden de sincronización entre `ConstraintTemplate` y `Constraint`.** Primer intento (una sola `Application`, `Constraint` con `argocd.argoproj.io/sync-wave: "1"`) falló repetidamente: `failed to discover server resources for group version constraints.gatekeeper.sh/v1beta1: the server could not find the requested resource`, incluso con la anotación de wave puesta. Investigado en los logs del `argocd-application-controller`: ArgoCD valida la sincronización completa contra el esquema de la API *antes* de empezar a aplicar cualquier recurso — un CRD que todavía no existe (porque Gatekeeper tarda unos segundos en reconciliar el `ConstraintTemplate` y registrar el `Constraint` CRD correspondiente) hace fallar toda la operación, independientemente de en qué wave esté el recurso que lo necesita. Resuelto separando en dos `Application` (`policies-templates`, `policies-constraints`) — verificado que la segunda reintentó sola (mensajes `Retrying attempt #N`) hasta que el CRD faltante (`k8srequiredropcapabilities.constraints.gatekeeper.sh`) apareció, momento en el que sincronizó sin intervención manual adicional.

## Conclusión
4 de 4 criterios de aceptación verificados contra el cluster real, incluyendo el caso más importante (rechazo real de un pod no conforme, con mensajes específicos, no un experimento teórico). Los dos incidentes reales de esta idea fueron ambos de la integración GitOps+Gatekeeper (orden de sincronización, sintaxis del lenguaje de políticas), no de la lógica de las políticas en sí — consistente con el patrón de todo el roadmap: la parte "obvia" del diseño rara vez es donde aparece la fricción real.
