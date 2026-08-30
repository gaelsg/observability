# 2026-08-30 — Verificado empíricamente: Vault sellado y la regla `VaultSealed`

Cierra el pendiente de la Idea 3: "confirmar empíricamente si Vault sellado hace caer el target en Prometheus". Se probó contra Vault real, en producción, con la colaboración del usuario (sellar/desellar requiere el root token — `vault-admin` no puede, a propósito, ver `policies/admin-limited.hcl` en `vault-secrets`).

## Procedimiento
1. Usuario generó un root token nuevo con la ceremonia `generate-root` (init → 3 unseal keys → decode) — mismo procedimiento de la Idea 2, ningún valor sensible pasó por el asistente.
2. `vault operator seal`.
3. Se monitoreó `/api/v1/targets` de Prometheus cada 10s durante 170s.
4. `vault operator unseal` (x3).
5. Root token revocado (`vault token revoke -self`) inmediatamente después de usarlo.

## Resultado: la premisa original estaba equivocada, en los dos sentidos

**`TargetDown` NO detecta un Vault sellado.** El target siguió `health: up` los 170 segundos completos. Confirmado con `curl` directo: `/v1/sys/metrics?format=prometheus` devuelve `200 OK` con datos válidos **incluso sellado** — el listener HTTP y las métricas del runtime de Go (goroutines, GC) no dependen del estado sealed/unsealed, solo las operaciones sobre el storage/secrets. El scrape de Prometheus nunca falla, así que `up == 0` nunca se cumple.

**La métrica `vault_core_unsealed` sí existe — la Idea 3 se había equivocado al asumir que no.** Se había investigado esto en su momento con `curl` (no a ciegas) y no apareció; con Vault sellado ahora, `curl` mostró `vault_core_unsealed{cluster="..."} 0` con claridad. No se determinó la causa exacta de la discrepancia (¿versión de Vault distinta en ese momento? ¿un error al revisar el output?) — lo que importa es que se volvió a verificar contra el sistema real en vez de asumir que la primera revisión seguía siendo válida para siempre.

## Cambio
`prometheus/alert-rules.yml`: regla `VaultSealed` (`vault_core_unsealed == 0`, `for: 1m`, `severity: critical`) restaurada. Desplegada al LXC real y confirmada `health: ok` en `/api/v1/rules`.

## Verificado
- `vault_core_unsealed` en `0` mientras estuvo sellado, `1` tras el unseal — confirmado con `curl` directo contra el exporter real en ambos momentos.
- Regla cargada sin errores en Prometheus tras el despliegue.
- Servicios que dependen de Vault (`proxmox-mcp-server`, y por extensión `k8s-mcp-server`/`devops-multiagent`) siguieron funcionando sin interrupción después del ciclo — sus AppRole tokens de corta vida ya estaban activos durante la ventana breve de sellado, y renovaron sin problema después.

## No se alcanzó a verificar
Que la alerta `VaultSealed` dispare de punta a punta hasta Telegram con el Diagnostician (como sí se hizo con `TargetDown` en la Idea 3) — hubiera requerido dejar Vault sellado varios minutos más para que el `for: 1m` se cumpla y Alertmanager la despache, extendiendo una interrupción real de un servicio del que ya dependen 4 proyectos. Se prioriza la verificación de la métrica en sí (lo que estaba realmente en duda) sobre repetir el patrón completo de entrega ya validado con otra alerta.
