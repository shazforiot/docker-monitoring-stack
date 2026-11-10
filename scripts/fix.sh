#!/usr/bin/env bash
# Undo scripts/break.sh: start the app again and switch chaos mode off.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose start demo-app
sleep 2
curl -fsS "http://localhost:8080/chaos?mode=off" >/dev/null 2>&1 || true
echo "demo-app is running again. The alert resolves in about a minute."
