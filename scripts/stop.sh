#!/usr/bin/env bash
# Stop the stack.   ./scripts/stop.sh           keep metrics, logs and dashboards
#                   ./scripts/stop.sh --reset   also delete all stored data
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--reset" ]; then
  docker compose down -v
  echo "Stopped. All stored metrics, logs and Grafana data were deleted."
else
  docker compose down
  echo "Stopped. Data is kept in Docker volumes. Start again with ./scripts/start.sh"
fi
