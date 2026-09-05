# 2026-09-05 — Primer SSO real: Grafana vía Authentik (Idea 12, post-roadmap)

Primer caso end-to-end de SSO/OIDC contra el `sso` nuevo (Authentik, ver repo
[`sso`](https://github.com/gaelsg/sso)). Proveedor OAuth2/OIDC y Application creados
vía la API de Authentik (no clic por clic en la UI), usando un token de servicio
generado por el usuario (`akadmin` → Directory → Tokens).

## Dos incidentes reales de la API de Authentik

1. **`property_mappings` vacío** — el provider se creó sin scope mappings
   (`openid`/`profile`/`email`), y el log mostró
   `"Application requested scopes not configured, setting to overlap"` con
   `scope_allowed: set()`. Arreglado asignando los 3 mappings estándar de Authentik
   (`propertymappings/provider/scope/`) al provider vía `PATCH`.
2. **`grant_types` vacío** y **`signing_key` nulo** — corregidos a
   `["authorization_code"]` y al certificado autofirmado por defecto de Authentik
   (RS256 en vez de HS256 implícito), para interoperar mejor con clientes OIDC
   estándar.

## El incidente real, mismo patrón que el del portapapeles

`Redirect URI Error` inicial: resuelto seteando `GF_SERVER_ROOT_URL` en Grafana
(sin esto arma el `redirect_uri` con su URL interna `localhost:3000` en vez de la
externa real). Confirmado en los logs de Authentik viendo el `redirect_uri` real
que llegaba en cada intento (`cause: redirect_uri_no_match`).

Después de eso, la pantalla de login de Authentik se quedaba cargando
indefinidamente al hacer click en "Iniciar sesión" — hasta 10 clicks sin avance
visible. Se reprodujo el flujo entero por `curl` directo contra la API del flow
executor (sin navegador): **el backend sí avanzaba correctamente** de
`ak-stage-identification` a `ak-stage-password` en cada submit. El problema era
puramente del frontend en el navegador, no del servidor.

**Causa raíz, confirmada por eliminación**: acceder a Authentik por HTTP plano
(puerto 9000) deja indisponibles APIs del navegador que requieren "contexto
seguro" (HTTPS/localhost) -- ya visto una vez con el Clipboard API al copiar el
token de servicio. Esta vez rompía la inicialización de WebAuthn/passkeys del
frontend de login, sin mostrar ningún error visible, solo quedándose colgado. Un
`Ctrl+Shift+R` no lo resolvió (el bug no era de caché). Se corrigió apuntando las
URLs de OIDC de Grafana (`AUTH_URL`/`TOKEN_URL`/`API_URL`) al puerto **9443
(HTTPS)** de Authentik en vez de 9000, con
`GF_AUTH_GENERIC_OAUTH_TLS_SKIP_VERIFY_INSECURE=true` (certificado autofirmado).

**Lección reusable para el resto del portafolio**: cualquier UI de administración
que se acceda por IP+HTTP plano en este homelab es candidata a romperse de formas
no obvias (clipboard, WebAuthn, posiblemente más) por restricciones de "contexto
seguro" del navegador -- no son bugs de la app en sí. Vale la pena, a futuro,
ponerle TLS de verdad (interno) a todo lo administrable, no solo dejarlo en HTTP
por comodidad de homelab.

## Verificado real

`GET /api/org/users` de Grafana mostrando un segundo usuario
(`ferios9615@gmail.com`, `authLabels: ["Generic OAuth"]`,
`isExternallySynced: true`), creado en el mismo segundo que el login exitoso —
no una captura de pantalla de una pantalla que "se ve bien".

## Pendiente

- Rol por defecto de los usuarios que entran por SSO es `Viewer`, no hereda el
  rol de `akadmin` en Authentik -- falta mapeo de roles/grupos si se quiere que
  el admin de Authentik también sea admin en Grafana.
- Login local (`admin`/password) sigue siendo el único con permisos de Admin
  reales por ahora -- no desactivado (`GF_AUTH_DISABLE_LOGIN_FORM` sigue en
  default `false`), a propósito, como red de respaldo.
- Nextcloud (`user_oidc`), Vault, ArgoCD: mismo patrón, pendiente para otra vuelta.
- Portainer y AdGuard Home necesitan el outpost (forward-auth) de Authentik, no
  integración OIDC nativa -- no la tienen.
