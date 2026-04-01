#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW_FILE="${FLOW_FILE:-$ROOT_DIR/flows/crm_autopecas_full_flow.json}"
SCHEMA_FILE="${SCHEMA_FILE:-$ROOT_DIR/sql/crm_autopecas_schema.sql}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

: "${NODE_RED_ADMIN_USER:?defina NODE_RED_ADMIN_USER no ambiente ou .env}"
: "${NODE_RED_ADMIN_PASSWORD:?defina NODE_RED_ADMIN_PASSWORD no ambiente ou .env}"

NODE_RED_URL="${NODE_RED_URL:-http://127.0.0.1:1880}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-evolution-postgres}"
POSTGRES_DB_NAME="${POSTGRES_DB_NAME:-${POSTGRES_DB:-flowpluss}}"
POSTGRES_DB_USER="${POSTGRES_DB_USER:-${POSTGRES_USER:-flowpluss}}"

CRM_POSTGRES_HOST="${CRM_POSTGRES_HOST:-postgres}"
CRM_POSTGRES_PORT="${CRM_POSTGRES_PORT:-5432}"
CRM_POSTGRES_DB="${CRM_POSTGRES_DB:-$POSTGRES_DB_NAME}"
CRM_PIX_GATEWAY_URL="${CRM_PIX_GATEWAY_URL:-http://webhook-gateway:3000/pix/cobranca}"

if [[ ! -f "$FLOW_FILE" ]]; then
  echo "ERRO: flow não encontrado em $FLOW_FILE" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERRO: schema SQL não encontrado em $SCHEMA_FILE" >&2
  exit 1
fi

echo "[1/4] Aplicando schema SQL no PostgreSQL (${POSTGRES_CONTAINER})..."
docker exec -i "$POSTGRES_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_DB_USER" -d "$POSTGRES_DB_NAME" < "$SCHEMA_FILE"

echo "[2/4] Solicitando token de API do Node-RED..."
TOKEN_RESPONSE="$(curl -fsS -X POST "$NODE_RED_URL/auth/token" \
  -H 'Content-Type: application/json' \
  --data "{\"client_id\":\"node-red-admin\",\"grant_type\":\"password\",\"scope\":\"*\",\"username\":\"$NODE_RED_ADMIN_USER\",\"password\":\"$NODE_RED_ADMIN_PASSWORD\"}")"
TOKEN="$(python - "$TOKEN_RESPONSE" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
print(payload.get('access_token', ''))
PY
)"

if [[ -z "$TOKEN" ]]; then
  echo "ERRO: não foi possível obter token do Node-RED." >&2
  exit 1
fi

echo "[3/4] Montando payload versionado do flow..."
FLOW_PAYLOAD="$(python - "$FLOW_FILE" "$CRM_POSTGRES_HOST" "$CRM_POSTGRES_PORT" "$CRM_POSTGRES_DB" "$CRM_PIX_GATEWAY_URL" <<'PY'
import json
import sys
from datetime import datetime, timezone

flow_file, pg_host, pg_port, pg_db, pix_url = sys.argv[1:]
with open(flow_file, encoding='utf-8') as f:
    flows = json.load(f)

for node in flows:
    if node.get('type') == 'postgresdb' and node.get('id') == 'crm_postgres_config':
        node['hostname'] = pg_host
        node['port'] = str(pg_port)
        node['db'] = pg_db
    if node.get('type') == 'http request' and node.get('name') == 'Gerar PIX (gateway)':
        node['url'] = pix_url

meta = {
    'deployedAt': datetime.now(timezone.utc).isoformat(),
    'sourceFile': flow_file,
    'postgresHost': pg_host,
    'postgresPort': str(pg_port),
    'postgresDb': pg_db,
    'pixGatewayUrl': pix_url,
}

print(json.dumps({'flows': flows, 'meta': meta}, ensure_ascii=False))
PY
)"

CURRENT_FLOWS="$(curl -fsS "$NODE_RED_URL/flows" -H "Authorization: Bearer $TOKEN" -H 'Node-RED-API-Version: v2')"
CURRENT_REV="$(python - "$CURRENT_FLOWS" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
print(payload.get('rev', ''))
PY
)"

DEPLOY_BODY="$(python - "$FLOW_PAYLOAD" "$CURRENT_REV" <<'PY'
import json
import sys
flow_payload = json.loads(sys.argv[1])
rev = sys.argv[2]
body = {'flows': flow_payload['flows']}
if rev:
    body['rev'] = rev
print(json.dumps(body, ensure_ascii=False))
PY
)"

echo "[4/4] Publicando flow no Node-RED (deploy full)..."
curl -fsS -X POST "$NODE_RED_URL/flows" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Node-RED-API-Version: v2' \
  -H 'Node-RED-Deployment-Type: full' \
  -H 'Content-Type: application/json' \
  --data "$DEPLOY_BODY" >/dev/null

mkdir -p "$ROOT_DIR/.artifacts"
printf '%s\n' "$FLOW_PAYLOAD" > "$ROOT_DIR/.artifacts/last_crm_deploy.json"

echo "Deploy automatizado concluído com sucesso."
echo "Artefato de auditoria: .artifacts/last_crm_deploy.json"
