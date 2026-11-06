#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

host="${1:-127.0.0.1}"
port="${2:-1433}"
printf 'Server=%s,%s;Database=CaldovaBenefits;User ID=caldova_benefits_app;Password=%s;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5;Application Name=caldova-benefits-service\n' \
  "$host" "$port" "$BENEFITS_APP_PASSWORD"
