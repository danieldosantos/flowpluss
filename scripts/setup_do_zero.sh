#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE_FILE="$ROOT_DIR/.envexemplo"
AUTO_YES="${AUTO_YES:-0}"
RESET_VOLUMES="${RESET_VOLUMES:-0}"

log() { echo "[setup-do-zero] $*"; }
warn() { echo "[setup-do-zero][aviso] $*"; }
fail() { echo "[setup-do-zero][erro] $*" >&2; exit 1; }

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "comando obrigatório não encontrado: $1"
}

confirm_or_abort() {
  local msg="$1"
  if [[ "$AUTO_YES" == "1" ]]; then
    log "$msg (AUTO_YES=1, seguindo sem confirmação interativa)"
    return
  fi

  read -r -p "$msg [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) fail "operação cancelada pelo usuário" ;;
  esac
}

ensure_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    log ".env já existe, mantendo arquivo atual"
    return
  fi

  [[ -f "$ENV_EXAMPLE_FILE" ]] || fail "arquivo .envexemplo não encontrado em $ENV_EXAMPLE_FILE"
  cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
  warn "arquivo .env criado a partir do .envexemplo"
  warn "revise as credenciais e chaves do .env antes de usar em produção"
}

validate_env_required_keys() {
  local required=(
    EVOLUTION_API_KEY
    MISTRAL_API_KEY
    NODE_RED_ADMIN_USER
    NODE_RED_ADMIN_PASSWORD
    WEBHOOK_SECRET
    WEBHOOK_HMAC_SECRET
    NODE_RED_CREDENTIAL_SECRET
    NODE_RED_COOKIE_SECRET
  )

  for key in "${required[@]}"; do
    if ! grep -Eq "^${key}=.+" "$ENV_FILE"; then
      fail "variável obrigatória ausente ou vazia no .env: ${key}"
    fi
  done

  log "validação de variáveis obrigatórias do .env concluída"
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local tries="${3:-30}"
  local sleep_secs="${4:-2}"

  for ((i=1; i<=tries; i++)); do
    if curl -fsS -I "$url" >/dev/null 2>&1; then
      log "$name disponível em $url"
      return
    fi
    sleep "$sleep_secs"
  done

  fail "$name não respondeu após $tries tentativas: $url"
}

main() {
  check_cmd docker
  check_cmd curl

  docker --version >/dev/null
  docker compose version >/dev/null

  ensure_env_file
  validate_env_required_keys

  if [[ "$RESET_VOLUMES" == "1" ]]; then
    confirm_or_abort "RESET_VOLUMES=1 vai apagar volumes e dados locais. Deseja continuar?"
    log "derrubando stack com remoção de volumes..."
    docker compose down -v
  else
    log "mantendo volumes atuais (use RESET_VOLUMES=1 para reset completo)"
    docker compose down
  fi

  log "subindo stack com build..."
  docker compose up -d --build

  log "status dos serviços:"
  docker compose ps

  wait_for_http "Node-RED" "http://127.0.0.1:1880"
  wait_for_http "Evolution API" "http://127.0.0.1:8080"

  log "setup concluído com sucesso"
  log "Node-RED: http://127.0.0.1:1880"
  log "Evolution API: http://127.0.0.1:8080"
}

main "$@"
