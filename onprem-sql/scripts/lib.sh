#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ONPREM_DIR/.env"
COMPOSE_FILE="$ONPREM_DIR/compose.yaml"
CONTAINER_NAME="caldova-onprem-sql"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Run scripts/start-onprem.sh first." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

sqlcmd_path() {
  docker exec "$CONTAINER_NAME" sh -lc \
    'command -v /opt/mssql-tools18/bin/sqlcmd || command -v /opt/mssql-tools/bin/sqlcmd'
}

run_sql_file() {
  local user="$1"
  local password="$2"
  local file="$3"
  shift 3

  local container_file="/tmp/$(basename "$file")"
  docker cp "$file" "$CONTAINER_NAME:$container_file" >/dev/null

  local sqlcmd
  sqlcmd="$(sqlcmd_path)"
  docker exec "$CONTAINER_NAME" "$sqlcmd" \
    -S localhost -U "$user" -P "$password" -C -b \
    -i "$container_file" "$@"
}
