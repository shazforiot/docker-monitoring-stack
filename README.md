# Docker monitoring stack: Prometheus + Grafana + Loki + Alertmanager 📈

A complete monitoring setup that starts with **one command**. It watches a small demo app and the machine it runs on, shows everything on ready-made Grafana dashboards, collects every container's logs, and sends an alert to Discord when something breaks.

No configuration needed: data sources, dashboards and alert rules load automatically.

> 🎥 Companion to the Thetips4you video *"/monitor: Prometheus + Grafana + Loki in 1 Command"*.

| Tool | Job | Open it |
|---|---|---|
| **Prometheus** | collects metrics every 10 s, checks the alert rules | http://localhost:9090 |
| **Grafana** | dashboards for metrics and logs | http://localhost:3000 |
| **Loki** | stores logs | (through Grafana) |
| **Grafana Alloy** | reads every container's logs and ships them to Loki | (no page published; `docker compose logs alloy`) |
| **Alertmanager** | groups alerts, sends them to Discord | http://localhost:9093 |
| **node_exporter** | CPU, memory, disk, network of the machine | (scraped by Prometheus) |
| **demo-app** + **traffic** | a small shop API to monitor, plus fake visitors | http://localhost:8080 |

```
 demo-app ──/metrics──┐                         ┌──> Grafana dashboards
 node_exporter ───────┼──> Prometheus ──rules──>│
 (this machine)       │        │                └──> Alertmanager ──> Discord
                      │        └─ stores metrics
 all containers ──logs──> Alloy ──> Loki ──────────> Grafana logs
```

---

## What's inside

```
docker-monitoring-stack/
├── docker-compose.yml            the 8 containers
├── .env.example                  settings (password, Discord webhook, versions); the start script creates .env
├── prometheus/
│   ├── prometheus.yml            what to scrape and how often
│   └── alerts.yml                7 alert rules (app down, error rate, slow, CPU, memory, disk, target down)
├── alertmanager/
│   ├── alertmanager.yml          default: alerts visible in the UI only
│   └── alertmanager-discord.yml  used when you set a Discord webhook
├── loki/loki-config.yml          log storage, 7 days retention
├── alloy/config.alloy            collect Docker logs -> Loki
├── grafana/
│   ├── provisioning/             data sources + dashboard loader (read at start-up)
│   └── dashboards/               3 dashboards: Demo App, Machine, Logs
├── app/
│   ├── app.py                    the demo shop API (Python standard library only)
│   └── traffic.py                fake visitors
└── scripts/                      start, check, break, fix, stop (.sh for Linux/WSL/macOS, .ps1 for Windows)
```

## Requirements

- Docker with Compose v2 (Docker Desktop on Windows/macOS, Docker Engine on Linux)
- 4 GB RAM free, about 2 GB disk
- Git (or download the ZIP)

---

## Step 0 · Install Docker (pick your setup)

**Windows 10/11 (Docker Desktop)**
1. Install WSL2 once: open PowerShell **as Administrator**, run `wsl --install`, then reboot.
2. Install **Docker Desktop** from docker.com. In *Settings → General*, keep **"Use the WSL 2 based engine"** on.
3. Start Docker Desktop and wait for *"Engine running"*.

**WSL2 (Ubuntu)**: either enable *Docker Desktop → Settings → Resources → WSL integration → Ubuntu*, or install Docker Engine inside Ubuntu:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER      # then close and reopen the terminal
```

**Linux**: `curl -fsSL https://get.docker.com | sh` (installs Docker Engine + the Compose plugin).

Check it works:
```bash
docker --version
docker compose version
```

## Step 1 · Get the files

```bash
git clone https://github.com/shazforiot/docker-monitoring-stack.git
cd docker-monitoring-stack
```
(or on the GitHub page: **Code → Download ZIP**, then unzip)

## Step 2 · Start everything

**Windows (PowerShell)**
```powershell
# once per machine, if scripts are blocked:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\scripts\start.ps1
```

**WSL2 / Linux / macOS**
```bash
./scripts/start.sh
```

The script:
1. creates `.env` with a random Grafana password,
2. runs `docker compose up -d` (first run downloads about 1.5 GB of images),
3. waits until Grafana and Prometheus answer,
4. prints the addresses and the Grafana login.

<details><summary>Prefer to type the commands yourself?</summary>

```bash
cp .env.example .env          # then change GRAFANA_ADMIN_PASSWORD
docker compose up -d
docker compose ps             # 8 containers, all "running"
```
</details>

## Step 3 · Check it

```bash
./scripts/check.sh            # Windows: .\scripts\check.ps1
```
You should see 8 running containers, six targets with `1` (up), no firing alerts, and the services that send logs.

In the browser:
- **http://localhost:9090/targets**: every target is green (**UP**).
- **http://localhost:8080/metrics**: the raw numbers the demo app publishes.

## Step 4 · Open Grafana

1. Open **http://localhost:3000** and log in with `admin` and the password the start script printed (it is also in `.env`).
2. **Dashboards → Monitoring Demo**:
   - **1 · Demo App**: status, requests per second, error rate, response time, plus the app's error logs.
   - **2 · Machine**: CPU, memory, disk, network. On Docker Desktop this is the Linux VM that runs your containers.
   - **3 · Logs**: every container's logs. Pick a service or type a search text.
3. **Explore** (compass icon) lets you ask your own questions:
   - Prometheus: `sum by (route) (rate(demo_http_requests_total[1m]))`
   - Loki: `{service="demo-app", level="error"}`

## Step 5 · Discord alerts (optional, 1 minute)

1. In Discord: **Server Settings → Integrations → Webhooks → New Webhook → Copy Webhook URL**.
2. Open `.env` and paste it: `DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...`
3. Run the start script again. It prints `Discord alerts: ON`.

Without a webhook, alerts still show in Prometheus (**/alerts**) and Alertmanager (**:9093**).

## Step 6 · Break it

```bash
./scripts/break.sh            # Windows: .\scripts\break.ps1
```
This stops the demo app. Then watch:

| When | What happens |
|---|---|
| about 10 s | *App status* on the dashboard turns red: **DOWN** |
| about 10 s | http://localhost:9090/alerts shows **DemoAppDown** as *pending* |
| about 40 s | the alert is **firing** and appears in Alertmanager |
| about 1 min | Discord: **🔥 FIRING: DemoAppDown** |

Fix it:
```bash
./scripts/fix.sh              # Windows: .\scripts\fix.ps1
```
The dashboard turns green and Discord gets **✅ RESOLVED** a minute or two later.

More ways to break it: `./scripts/break.sh errors` (60% of orders fail → **HighErrorRate**) and `./scripts/break.sh slow` (→ **SlowRequests**). Windows: `.\scripts\break.ps1 -Mode errors`.

## Step 7 · Monitor your own things

**Another server**: install [node_exporter](https://github.com/prometheus/node_exporter) on it, then add to `prometheus/prometheus.yml`:
```yaml
  - job_name: my-server
    static_configs:
      - targets: ["192.168.1.50:9100"]
```
Reload without a restart: `curl -X POST http://localhost:9090/-/reload`

**Your own app**: expose a `/metrics` page (there are Prometheus client libraries for every language), add it as a target the same way. Its container logs are collected automatically.

**Your own alert**: add a rule to `prometheus/alerts.yml`, then reload as above.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `port is already allocated` (3000, 9090, 9093 or 8080) | Something else uses that port. Stop it, or change the left number in `docker-compose.yml`, e.g. `"3001:3000"`. |
| Grafana login fails | The password is in `.env` (`GRAFANA_ADMIN_PASSWORD`). It is set on the first start only; to change it later run `./scripts/stop.sh --reset` and start again (this deletes stored data). |
| A target is **DOWN** on :9090/targets | `docker compose ps` to see if the container runs, then `docker compose logs <name>`. |
| Dashboards show "No data" | Wait 30 seconds after the first start. Check the time range (top right) is *Last 15 minutes*. |
| Logs dashboard is empty | `docker compose logs alloy`. Alloy needs the Docker socket: on Linux with rootless Docker, change the socket path in `docker-compose.yml`. |
| Machine dashboard looks small on Windows/macOS | Expected: Docker Desktop runs containers in a Linux VM, so you see the VM. To watch Windows itself, run [windows_exporter](https://github.com/prometheus-community/windows_exporter) and add it as a target. |
| No Discord message | Run the start script again after editing `.env`; check `docker compose logs alertmanager`. |
| Windows: `start.ps1 cannot be loaded` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| WSL: `bad interpreter` or `$'\r'` errors | The repo sets line endings via `.gitattributes`; clone again with Git rather than copying files from Windows. |

## Stop / reset

```bash
./scripts/stop.sh            # stop, keep data          (Windows: .\scripts\stop.ps1)
./scripts/stop.sh --reset    # stop and delete all data (Windows: .\scripts\stop.ps1 -Reset)
```

## Security notes

- This is a learning setup for your own computer. Don't expose ports 3000, 9090 or 9093 to the internet without HTTPS and authentication; Prometheus and Alertmanager have no login.
- `.env` and `alertmanager/secrets/` hold your password and webhook URL. Both are in `.gitignore`. Never commit them.
- Alloy reads the Docker socket (read-only mount) to find containers and their logs.

## Credits & licence

- Demo files: MIT licence (see `LICENSE`).
- [Prometheus](https://github.com/prometheus/prometheus), [Alertmanager](https://github.com/prometheus/alertmanager), [node_exporter](https://github.com/prometheus/node_exporter): Apache 2.0. [Grafana](https://github.com/grafana/grafana), [Loki](https://github.com/grafana/loki): AGPL-3.0. [Grafana Alloy](https://github.com/grafana/alloy): Apache 2.0.
- Versions pinned in `.env.example` (checked November 2026): Prometheus 3.16.0, Alertmanager 0.35.0, node_exporter 1.12.1, Loki 3.7.9, Alloy 1.21.3, Grafana 13.3.0.
