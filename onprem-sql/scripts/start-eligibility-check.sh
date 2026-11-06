#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

container_file="/tmp/11-check-member-eligibility.sql"
docker cp "$ONPREM_DIR/sql/11-check-member-eligibility.sql" "$CONTAINER_NAME:$container_file" >/dev/null
sqlcmd="$(sqlcmd_path)"
docker exec -d "$CONTAINER_NAME" "$sqlcmd" \
  -S localhost \
  -U caldova_benefits_app \
  -P "$BENEFITS_APP_PASSWORD" \
  -C \
  -d CaldovaBenefits \
  -l 5 \
  -i "$container_file"

echo "Started a member eligibility check for transaction analysis."
