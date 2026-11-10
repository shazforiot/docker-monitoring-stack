#!/usr/bin/env bash
# Start the monitoring stack (Linux, WSL2, macOS).   Usage: ./scripts/start.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v docker >/dev/null || { echo "Docker is not installed. See README, Step 0."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is missing. See README, Step 0."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker Desktop (or: sudo systemctl start docker)."; exit 1; }

# 1. Settings: create .env once, with a random Grafana password
if [ ! -f .env ]; then
  pass="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
  sed "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=${pass}/" .env.example > .env
  echo "Created .env with a random Grafana password."
fi
get() { grep -E "^$1=" .env | tail -n 1 | cut -d= -f2- | tr -d '\r' || true; }
set_env() { if grep -qE "^$1=" .env; then sed -i.bak "s|^$1=.*|$1=$2|" .env && rm -f .env.bak; else echo "$1=$2" >> .env; fi; }

# 2. Discord: if a webhook URL is set, hand it to Alertmanager as a secret file
webhook="$(get DISCORD_WEBHOOK_URL)"
if [ -n "$webhook" ]; then
  mkdir -p alertmanager/secrets
  printf '%s' "$webhook" > alertmanager/secrets/discord_webhook
  chmod 644 alertmanager/secrets/discord_webhook
  set_env ALERTMANAGER_CONFIG alertmanager-discord.yml
  echo "Discord alerts: ON"
else
  set_env ALERTMANAGER_CONFIG alertmanager.yml
  echo "Discord alerts: off (set DISCORD_WEBHOOK_URL in .env and run this script again)"
fi

# 3. Start (first run downloads about 1.5 GB of images)
echo "Starting 8 containers..."
docker compose up -d
[ -n "$webhook" ] && docker compose restart alertmanager >/dev/null

# 4. Wait until Grafana and Prometheus answer
printf "Waiting for Grafana"
for _ in $(seq 1 60); do
  if curl -fs http://localhost:3000/api/health >/dev/null 2>&1 && curl -fs http://localhost:9090/-/ready >/dev/null 2>&1; then ok=1; break; fi
  printf "."; sleep 2
done
echo
[ "${ok:-0}" = 1 ] || { echo "Still starting. Check: docker compose ps   and   docker compose logs grafana"; exit 1; }

cat <<MSG

MONITORING IS READY
  Grafana        http://localhost:3000    user: $(get GRAFANA_ADMIN_USER)   password: $(get GRAFANA_ADMIN_PASSWORD)
  Prometheus     http://localhost:9090
  Alertmanager   http://localhost:9093
  Demo app       http://localhost:8080

Next:  ./scripts/check.sh   then   ./scripts/break.sh   (and ./scripts/fix.sh)
MSG
