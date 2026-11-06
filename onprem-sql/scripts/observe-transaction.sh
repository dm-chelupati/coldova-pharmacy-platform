#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

run_sql_file caldova_sre_reader "$SRE_READER_PASSWORD" "$ONPREM_DIR/sql/20-observe-transaction.sql"
