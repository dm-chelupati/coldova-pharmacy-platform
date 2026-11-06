#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$ONPREM_DIR/.runtime"
DEFAULT_NGROK_CONFIG="${NGROK_CONFIG:-$HOME/Library/Application Support/ngrok/ngrok.yml}"
RUNTIME_NGROK_CONFIG="$RUNTIME_DIR/ngrok.yml"

if [[ ! -f "$DEFAULT_NGROK_CONFIG" ]]; then
  echo "ngrok is not configured. Run 'ngrok config add-authtoken' first." >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
cat >"$RUNTIME_NGROK_CONFIG" <<'YAML'
version: 3
agent:
  web_addr: 127.0.0.1:4040
tunnels:
  caldova-sql-mcp:
    proto: http
    addr: 8088
    schemes:
      - https
YAML

exec ngrok start --all \
  --config "$DEFAULT_NGROK_CONFIG" \
  --config "$RUNTIME_NGROK_CONFIG" \
  --log stdout \
  --log-format json
