# Especificación de Requisitos — Idea 10: Policy-as-code con OPA Gatekeeper

Según proceso **SI.2** del Perfil Básico ISO/IEC 29110.

## Requisitos funcionales

| ID | Requisito |
|---|---|
| RF1 | El cluster rechaza la creación de un Pod que no declare `runAsNonRoot: true` (a nivel de contenedor o de pod). |
| RF2 | El cluster rechaza la creación de un Pod cuyos contenedores no declaren `resources.requests` (cpu, memoria) y `resources.limits.memory`. |
| RF3 | El cluster rechaza la creación de un Pod que use la tag `:latest` (explícita o implícita) en cualquier contenedor. |
| RF4 | El cluster rechaza la creación de un Pod que corra `privileged` o no dropee `ALL` capabilities. |
| RF5 | Cada rechazo incluye un mensaje específico identificando qué política y qué contenedor la violó, no un error genérico. |
| RF6 | Las políticas no aplican a los namespaces de infraestructura de plataforma (`kube-system`, `gatekeeper-system`, `argocd`). |

## Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF1 | Si el componente de Gatekeeper que evalúa las políticas no responde, el cluster sigue admitiendo recursos (no bloquea todo por una falla del propio sistema de políticas). |
| RNF2 | Las políticas están versionadas en git y se sincronizan automáticamente al cluster (GitOps), no se aplican con `kubectl apply` manual. |
| RNF3 | Activar las políticas no interrumpe ni modifica un workload ya desplegado que ya las cumple. |
| RNF4 | El footprint de Gatekeeper es una fracción razonable de la RAM disponible del LXC. |

## Fuera de alcance
- Policy-as-code sobre `proxmox-iac`/Terraform.
- Modo auditoría/dry-run previo a enforcement.
- Políticas de red o de verificación de firmas de imagen.
