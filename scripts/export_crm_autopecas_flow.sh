#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/flows/crm_autopecas_full_flow.json}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

: "${NODE_RED_ADMIN_USER:?defina NODE_RED_ADMIN_USER no ambiente ou .env}"
: "${NODE_RED_ADMIN_PASSWORD:?defina NODE_RED_ADMIN_PASSWORD no ambiente ou .env}"
NODE_RED_URL="${NODE_RED_URL:-http://127.0.0.1:1880}"

echo "[1/3] Solicitando token da API do Node-RED..."
TOKEN_RESPONSE="$(curl -fsS -X POST "$NODE_RED_URL/auth/token" \
  -H 'Content-Type: application/json' \
  --data "{\"client_id\":\"node-red-admin\",\"grant_type\":\"password\",\"scope\":\"*\",\"username\":\"$NODE_RED_ADMIN_USER\",\"password\":\"$NODE_RED_ADMIN_PASSWORD\"}")"
TOKEN="$(python - "$TOKEN_RESPONSE" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get('access_token', ''))
PY
)"

if [[ -z "$TOKEN" ]]; then
  echo "ERRO: não foi possível obter token do Node-RED." >&2
  exit 1
fi

echo "[2/3] Exportando flows ativos..."
RAW_RESPONSE="$(curl -fsS "$NODE_RED_URL/flows" -H "Authorization: Bearer $TOKEN" -H 'Node-RED-API-Version: v2')"

echo "[3/3] Salvando versão rastreável em $OUTPUT_FILE ..."
python - "$RAW_RESPONSE" "$OUTPUT_FILE" <<'PY'
import json
import pathlib
import sys

payload = json.loads(sys.argv[1])
output = pathlib.Path(sys.argv[2])
flows = payload.get('flows', [])
output.parent.mkdir(parents=True, exist_ok=True)
with output.open('w', encoding='utf-8') as f:
    json.dump(flows, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

echo "Export concluído. Faça commit deste arquivo para versionar mudanças de fluxo."
