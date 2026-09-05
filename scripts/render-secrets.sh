#!/usr/bin/env bash
# Trae secret/observability de Vault (via el AppRole dedicado, no root/admin)
# y renderiza los archivos locales (gitignored) que docker-compose y
# Alertmanager necesitan: .env y alertmanager/alertmanager.yml.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPROLE_FILE="$REPO_ROOT/.observability-approle"

if [ ! -f "$APPROLE_FILE" ]; then
  echo "Falta $APPROLE_FILE (credenciales AppRole del proyecto)" >&2
  exit 1
fi

set -a
source "$APPROLE_FILE"
set +a

LOGIN=$(curl -s --cacert "$VAULT_CACERT" -X POST "$VAULT_ADDR/v1/auth/approle/login" \
  -d "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}")
TOKEN=$(echo "$LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

python3 - "$REPO_ROOT" "$VAULT_ADDR" "$VAULT_CACERT" "$TOKEN" <<'PYEOF'
import json
import subprocess
import sys

repo_root, vault_addr, vault_cacert, token = sys.argv[1:5]

resp = subprocess.run(
    ["curl", "-s", "--cacert", vault_cacert, "-H", f"X-Vault-Token: {token}",
     f"{vault_addr}/v1/secret/data/observability"],
    capture_output=True, text=True, check=True,
)
data = json.loads(resp.stdout)["data"]["data"]

with open(f"{repo_root}/.env", "w") as f:
    for key in ("PROXMOX_HOST", "PROXMOX_USER", "PROXMOX_TOKEN_NAME", "PROXMOX_TOKEN_VALUE",
                "PROXMOX_VERIFY_SSL", "GRAFANA_ADMIN_USER", "GRAFANA_ADMIN_PASSWORD",
                "GRAFANA_OIDC_CLIENT_ID", "GRAFANA_OIDC_CLIENT_SECRET",
                "TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"):
        f.write(f"{key}={data[key]}\n")

with open(f"{repo_root}/alertmanager/alertmanager.yml.template") as f:
    template = f.read()
with open(f"{repo_root}/alertmanager/alertmanager.yml", "w") as f:
    f.write(template.replace("__WEBHOOK_SHARED_SECRET__", data["WEBHOOK_SHARED_SECRET"]))

print("Renderizados .env y alertmanager/alertmanager.yml (valores no impresos)")
PYEOF
