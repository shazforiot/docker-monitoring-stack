#!/usr/bin/env bash
# Health check: containers, Prometheus targets, firing alerts, logs in Loki.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== Containers =="
docker compose ps --format 'table {{.Name}}\t{{.State}}\t{{.Status}}'

echo; echo "== Prometheus targets (1 = up, 0 = down) =="
curl -fsS 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null \
  | tr '{' '\n' | sed -n 's/.*"job":"\([^"]*\)".*"value":\[[^,]*,"\([01]\)"\].*/  \2  \1/p' | sort -k2 \
  || echo "  Prometheus is not answering on http://localhost:9090"

echo; echo "== Firing alerts =="
alerts="$(curl -fsS 'http://localhost:9090/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D' 2>/dev/null \
  | tr '{' '\n' | sed -n 's/.*"alertname":"\([^"]*\)".*"severity":"\([^"]*\)".*/  \1 (\2)/p' | sort -u)"
[ -n "$alerts" ] && echo "$alerts" || echo "  none"

echo; echo "== Logs in Loki (services seen) =="
docker compose exec -T grafana wget -qO- 'http://loki:3100/loki/api/v1/label/service/values' 2>/dev/null \
  | tr -d '[]{}"' | sed 's/status:success,data://; s/,/  /g; s/^/  /' || echo "  Loki is not answering yet"
echo
