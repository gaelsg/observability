# 2026-08-30 — Policy-as-code con OPA Gatekeeper (Idea 10, post-roadmap)

Cuarta idea después de cerrar el roadmap de 6 (ver `docs/29110/idea10-policy-as-code/` para el detalle formal). Continuación directa de la Idea 9: ArgoCD ya despliega Jaeger siguiendo buenas prácticas (sin privilegios, con límites de recursos) — pero eso era "me acordé de hacerlo bien", no algo que el cluster exigiera. Gatekeeper lo convierte en lo segundo.

## Gatekeeper instalado
Mismo criterio que ArgoCD: manifiesto oficial descargado y revisado (17 CRDs, 2 webhooks, 2 deployments — nada inesperado) antes de aplicar, con `--server-side` desde el arranque (aprendido de la Idea 9). `failurePolicy: Ignore` en el webhook — si Gatekeeper cae, deja pasar en vez de bloquear todo el cluster, verificado leyendo el manifiesto antes de instalar, no asumido. Footprint real: ~155MB.

## Antes de escribir las políticas: verificar quién las rompería
Se revisaron los pods de ArgoCD (manifiesto oficial) contra las 4 políticas planeadas — ninguno declara `resources`, la mayoría no setea `runAsNonRoot`. Decisión: excluir `kube-system`, `gatekeeper-system` y `argocd` de las políticas — son infraestructura de plataforma, no cargas de aplicación que este proyecto controla. Evitó descubrir esto de la peor forma (ArgoCD roto al aplicar las políticas).

## Dos incidentes reales, ninguno de las políticas en sí

**1. Error de sintaxis Rego real.** `not "ALL" in drops` — el operador `in` requiere `import future.keywords.in`, no habilitado por defecto en el OPA embebido en esta versión de Gatekeeper. Encontrado en el propio `status` del `ConstraintTemplate` (`rego_parse_error`), no en una prueba manual de Rego aparte. Corregido con el patrón clásico de pertenencia (`drops[_] == "ALL"`).

**2. Orden de sincronización entre `ConstraintTemplate` y `Constraint`.** Un `Constraint` (ej. `K8sRequireNonRoot`) es una instancia de un CRD que Gatekeeper crea dinámicamente al reconciliar el `ConstraintTemplate` correspondiente — ese registro es asíncrono, toma unos segundos. Aplicar ambos en la misma sincronización de ArgoCD falla: `the server could not find the requested resource`. Se probó primero con `sync-wave` (anotación estándar de ArgoCD para ordenar recursos dentro de una misma `Application`) — **no alcanzó**: ArgoCD valida todos los recursos de la sincronización contra el esquema descubierto de la API *antes* de aplicar nada, sin importar la wave. La solución real fue separar en dos `Application` distintas (`policies-templates`, `policies-constraints`), cada una con su propio ciclo de sincronización/reintento — la de constraints reintenta sola (`selfHeal`) hasta que el CRD ya existe.

## Verificado con un rechazo real

```
kubectl apply -f pod-sin-cumplir.yaml
→ Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
  [require-non-root] ...
  [require-drop-capabilities] ...
  [require-resources] ...
  [disallow-latest-tag] ...
```

Las 4 políticas dispararon correctamente, con mensajes específicos por cada violación (no un rechazo genérico). Un pod que sí cumple (`runAsNonRoot`, `capabilities.drop: [ALL]`, `resources` completos, tag fijada) se aceptó sin fricción — confirma que las políticas no son overly-broad / no generan falsos positivos. El `deployment` de Jaeger, ya corriendo desde antes de estas políticas, siguió `Synced`/`Healthy` sin cambios.

## Pendiente
- [ ] Extender el mismo criterio (Rego/Conftest) a los `.tf` de `proxmox-iac` — validar en CI que nunca se usa `root@pam`, por ejemplo. Candidata para una idea futura, no esta.
- [ ] Commit + push.
