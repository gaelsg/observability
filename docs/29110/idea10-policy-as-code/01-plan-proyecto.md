# Plan de Proyecto — Idea 10: Policy-as-code con OPA Gatekeeper

Según proceso **PM.1** del Perfil Básico ISO/IEC 29110. Cuarta idea post-roadmap ([[project-roadmap2-bigtech]]).

## Objetivo
Convertir el criterio de "mínimo privilegio y buenas prácticas" que se repite en todo el proyecto (documentado en cada README, aplicado a mano en cada manifiesto) en algo que el cluster **exige automáticamente** al momento de admitir un recurso, no algo que dependa de que quien despliega se acuerde de hacerlo bien.

## Alcance

**Incluye:**
- OPA Gatekeeper instalado en el cluster k3s.
- 4 `ConstraintTemplate` (Rego) + `Constraint` correspondientes: no-root, requests/limits de recursos, sin tag `:latest`, drop de capabilities.
- Políticas gestionadas por GitOps (mismo patrón de la Idea 9), no aplicadas a mano.
- Verificación real: un pod que viola las políticas es rechazado por el admission webhook; uno que cumple, aceptado; el workload ya desplegado (Jaeger) no se ve afectado.

**No incluye (fuera de alcance v1):**
- Políticas sobre `proxmox-iac` (Conftest sobre `.tf`) — mismo lenguaje (Rego), pero un dominio distinto (Terraform, no Kubernetes), queda como candidata para una idea futura.
- Modo "dry-run"/auditoría antes de enforcement — el cluster solo tenía un workload (Jaeger), ya compatible por diseño, no había riesgo real de romper algo desplegado al ir directo a modo deny.
- Políticas de red (NetworkPolicy) o de admisión de imágenes por firma (verificar la firma de cosign de la Idea 8 como policy) — extensiones posibles, no construidas acá.

## Entregables
1. Gatekeeper instalado en el cluster.
2. `gitops/policies/templates/` (4 `ConstraintTemplate`) + `gitops/policies/constraints/` (4 `Constraint`), cada uno con su propia `Application` de ArgoCD.
3. Esta serie de documentos 29110 + bitácora.

## Riesgos identificados
| Riesgo | Mitigación |
|---|---|
| Gatekeeper caído bloquea todo el cluster | `failurePolicy: Ignore` en el webhook (verificado leyendo el manifiesto antes de instalar) — si el webhook no responde, deja pasar. |
| Las políticas rompen infraestructura de plataforma (ArgoCD, kube-system) | Verificado antes de escribir las políticas que los pods de ArgoCD no cumplirían — excluidos explícitamente, no una sorpresa post-hoc. |
| `ConstraintTemplate` y `Constraint` en la misma sincronización de GitOps fallan por orden de creación de CRDs | Encontrado en la práctica; resuelto separando en dos `Application` de ArgoCD independientes (ver `04-verificacion.md`). |
| Falsos positivos bloqueando despliegues legítimos | Verificado con un pod real que cumple todas las políticas — aceptado sin fricción. |

## Criterios de aceptación
- Un pod que viola cualquiera de las 4 políticas es rechazado por el cluster real, con un mensaje específico por violación.
- Un pod que cumple todas las políticas es aceptado sin fricción.
- El workload ya desplegado (Jaeger, Idea 9) sigue `Synced`/`Healthy` sin cambios tras activar las políticas.
- Las políticas están gestionadas por GitOps (versionadas, sincronizadas por ArgoCD), no aplicadas a mano.
