#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-https://coldova-pharmacy-gateway-prod.delightfulwater-9ca1de99.canadacentral.azurecontainerapps.io}"
PAYMENTS_URL="${GATEWAY_URL%/}/api/payments/process"

run_worker() {
  while true; do
    curl --silent --show-error \
      --request POST \
      --output /dev/null \
      --max-time 10 \
    "$PAYMENTS_URL" || true
    sleep 0.25
  done
}

trap 'kill "${worker_pids[@]}" 2>/dev/null || true' EXIT INT TERM

worker_pids=()
for _ in 1 2 3; do
  run_worker &
  worker_pids+=("$!")
  sleep 0.5
done

wait
