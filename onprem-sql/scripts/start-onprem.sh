#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ONPREM_DIR/.env"

generate_password() {
  printf 'Aa9!%s' "$(openssl rand -hex 14)"
}

ensure_secret() {
  local name="$1"
  if ! grep -q "^${name}=" "$ENV_FILE"; then
    printf '%s=%s\n' "$name" "$(generate_password)" >>"$ENV_FILE"
  fi
}

if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  {
    printf 'MSSQL_SA_PASSWORD=%s\n' "$(generate_password)"
    printf 'BENEFITS_APP_PASSWORD=%s\n' "$(generate_password)"
    printf 'TRANSACTION_HOLDER_PASSWORD=%s\n' "$(generate_password)"
    printf 'NIGHTLY_SYNC_PASSWORD=%s\n' "$(generate_password)"
    printf 'SRE_READER_PASSWORD=%s\n' "$(generate_password)"
    printf 'SRE_AUTOMATION_PASSWORD=%s\n' "$(generate_password)"
    printf 'MCP_BEARER_TOKEN=%s\n' "$(openssl rand -hex 32)"
    printf 'GITHUB_PERSONAL_ACCESS_TOKEN=\n'
  } >"$ENV_FILE"
else
  ensure_secret NIGHTLY_SYNC_PASSWORD
  ensure_secret SRE_AUTOMATION_PASSWORD
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  echo "Set GITHUB_PERSONAL_ACCESS_TOKEN in $ENV_FILE before starting the MCP services." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$ONPREM_DIR/compose.yaml" up -d --build

echo "Waiting for the simulated on-prem SQL Server..."
for attempt in $(seq 1 36); do
  health="$(docker inspect --format '{{.State.Health.Status}}' caldova-onprem-sql 2>/dev/null || true)"
  if [[ "$health" == "healthy" ]]; then
    break
  fi

  if [[ "$attempt" -eq 36 ]]; then
    docker logs --tail 80 caldova-onprem-sql >&2
    echo "SQL Server did not become healthy." >&2
    exit 1
  fi

  sleep 5
done

source "$SCRIPT_DIR/lib.sh"
run_sql_file sa "$MSSQL_SA_PASSWORD" "$ONPREM_DIR/sql/01-bootstrap.sql" \
  -v "BenefitsAppPassword=$BENEFITS_APP_PASSWORD" \
  "TransactionHolderPassword=$TRANSACTION_HOLDER_PASSWORD" \
  "NightlySyncPassword=$NIGHTLY_SYNC_PASSWORD" \
  "SreReaderPassword=$SRE_READER_PASSWORD" \
  "SreAutomationPassword=$SRE_AUTOMATION_PASSWORD"
run_sql_file sa "$MSSQL_SA_PASSWORD" "$ONPREM_DIR/sql/40-automation-recovery.sql"

echo "Caldova simulated on-prem SQL Server is healthy on 127.0.0.1:1433."
echo "Credentials are stored only in onprem-sql/.env (gitignored)."
