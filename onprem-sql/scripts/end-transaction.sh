#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"
run_sql_file sa "$MSSQL_SA_PASSWORD" "$ONPREM_DIR/sql/30-end-transaction.sql"
