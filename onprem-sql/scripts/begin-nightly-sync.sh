#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

sqlcmd="$(sqlcmd_path)"
existing_sync="$(
  docker exec "$CONTAINER_NAME" "$sqlcmd" \
    -S localhost \
    -U caldova_sre_reader \
    -P "$SRE_READER_PASSWORD" \
    -C -b -h -1 -W \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE login_name = N'caldova_nightly_benefits_sync';" \
    | tr -d '\r[:space:]'
)"

if [[ "$existing_sync" != "0" ]]; then
  echo "The nightly benefits-sync transaction is already open." >&2
  exit 1
fi

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  --profile fault-injection \
  up -d --build nightly-sync

for attempt in $(seq 1 30); do
  active_sync="$(
    docker exec "$CONTAINER_NAME" "$sqlcmd" \
      -S localhost \
      -U caldova_sre_reader \
      -P "$SRE_READER_PASSWORD" \
      -C -b -h -1 -W \
      -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE login_name = N'caldova_nightly_benefits_sync' AND program_name = N'caldova-nightly-benefits-sync' AND open_transaction_count > 0;" \
      | tr -d '\r[:space:]'
  )"
  if [[ "$active_sync" == "1" ]]; then
    echo "The nightly benefits-sync transaction is stalled with its connection open."
    exit 0
  fi
  sleep 1
done

docker logs --tail 50 caldova-nightly-benefits-sync >&2
echo "The nightly benefits-sync transaction did not start." >&2
exit 1
