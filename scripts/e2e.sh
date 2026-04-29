#!/bin/sh
# End-to-end test runner for Choresy
set -e

echo "=== E2E: Starting stack ==="
if [ "${CI}" = "true" ]; then
  # CI: run app with in-memory stores (no Docker needed)
  go run ./cmd/server &
  APP_PID=$!
  trap "kill ${APP_PID} 2>/dev/null" EXIT
else
  if command -v podman > /dev/null 2>&1; then
    podman compose up -d --build
  else
    docker compose up -d --build
  fi
fi
./scripts/wait-for-stack.sh

echo "=== E2E: Running Playwright tests ==="
pnpm exec playwright test --config playwright.config.js "$@"

EXIT=$?
echo "=== E2E: Done (exit $EXIT) ==="
exit $EXIT
