#!/usr/bin/env bash
# Break the demo app on purpose and watch the alert fire.
#   ./scripts/break.sh          stop the app          -> DemoAppDown   (about 1 minute)
#   ./scripts/break.sh errors   60% of orders fail    -> HighErrorRate (about 2 minutes)
#   ./scripts/break.sh slow     orders take 1 s more  -> SlowRequests  (about 2 minutes)
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-down}"
case "$mode" in
  down)        docker compose stop demo-app; echo "demo-app stopped. Watch http://localhost:9090/alerts (pending, then firing in about 40 s)." ;;
  errors|slow) curl -fsS "http://localhost:8080/chaos?mode=$mode"; echo; echo "Chaos mode '$mode' is on. Watch the Demo App dashboard." ;;
  *)           echo "Usage: ./scripts/break.sh [down|errors|slow]"; exit 1 ;;
esac
