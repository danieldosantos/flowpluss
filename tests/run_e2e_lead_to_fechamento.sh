#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! docker ps --format '{{.Names}}' | rg -q '^evolution-postgres$'; then
  echo "Container evolution-postgres não está em execução."
  echo "Suba a stack antes: docker compose up -d postgres"
  exit 1
fi

docker exec -i evolution-postgres psql -v ON_ERROR_STOP=1 -U flowpluss -d flowpluss < "$SCRIPT_DIR/e2e_lead_to_fechamento.sql"

echo "E2E obrigatório (lead→atendimento→pedido→PIX→pagamento→fechamento) passou com sucesso."
