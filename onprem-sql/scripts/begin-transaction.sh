#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

sqlcmd="$(sqlcmd_path)"
existing_transaction="$(
  docker exec "$CONTAINER_NAME" "$sqlcmd" \
    -S localhost \
    -U caldova_sre_reader \
    -P "$SRE_READER_PASSWORD" \
    -C -b -h -1 -W \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE login_name = N'caldova_transaction_holder';" \
    | tr -d '\r[:space:]'
)"

if [[ "$existing_transaction" != "0" ]]; then
  echo "The member benefits update transaction is already open." >&2
  exit 1
fi

container_file="/tmp/10-begin-member-update.sql"
docker cp "$ONPREM_DIR/sql/10-begin-member-update.sql" "$CONTAINER_NAME:$container_file" >/dev/null
docker exec -d "$CONTAINER_NAME" "$sqlcmd" \
  -S localhost \
  -U caldova_transaction_holder \
  -P "$TRANSACTION_HOLDER_PASSWORD" \
  -C \
  -d CaldovaBenefits \
  -l 5 \
  -i "$container_file"

echo "The member benefits update transaction is open."
echo "Generate application traffic separately to produce customer-facing telemetry."
