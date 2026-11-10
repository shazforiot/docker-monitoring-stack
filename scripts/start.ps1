# Start the monitoring stack (Windows PowerShell).   Usage: .\scripts\start.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host "Docker is not installed. See README, Step 0."; exit 1 }
docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "Docker is not running. Start Docker Desktop and wait for 'Engine running'."; exit 1 }

function Get-EnvValue($name) {
  $line = Get-Content .env | Where-Object { $_ -match "^$name=" } | Select-Object -Last 1
  if ($line) { return $line.Substring($name.Length + 1).Trim() } else { return "" }
}
function Set-EnvValue($name, $value) {
  $lines = @(Get-Content .env)
  if ($lines -match "^$name=") { $lines = $lines | ForEach-Object { if ($_ -match "^$name=") { "$name=$value" } else { $_ } } }
  else { $lines += "$name=$value" }
  [IO.File]::WriteAllLines((Join-Path (Get-Location) ".env"), $lines)
}

# 1. Settings: create .env once, with a random Grafana password
if (-not (Test-Path .env)) {
  $pass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
  $lines = Get-Content .env.example | ForEach-Object { if ($_ -match "^GRAFANA_ADMIN_PASSWORD=") { "GRAFANA_ADMIN_PASSWORD=$pass" } else { $_ } }
  [IO.File]::WriteAllLines((Join-Path (Get-Location) ".env"), $lines)
  Write-Host "Created .env with a random Grafana password."
}

# 2. Discord: if a webhook URL is set, hand it to Alertmanager as a secret file
$webhook = Get-EnvValue "DISCORD_WEBHOOK_URL"
if ($webhook) {
  New-Item -ItemType Directory -Force -Path alertmanager\secrets | Out-Null
  [IO.File]::WriteAllText((Join-Path (Get-Location) "alertmanager\secrets\discord_webhook"), $webhook)
  Set-EnvValue "ALERTMANAGER_CONFIG" "alertmanager-discord.yml"
  Write-Host "Discord alerts: ON"
} else {
  Set-EnvValue "ALERTMANAGER_CONFIG" "alertmanager.yml"
  Write-Host "Discord alerts: off (set DISCORD_WEBHOOK_URL in .env and run this script again)"
}

# 3. Start (first run downloads about 1.5 GB of images)
Write-Host "Starting 8 containers..."
docker compose up -d
if ($LASTEXITCODE -ne 0) { exit 1 }
if ($webhook) { docker compose restart alertmanager | Out-Null }

# 4. Wait until Grafana and Prometheus answer
Write-Host -NoNewline "Waiting for Grafana"
$ok = $false
foreach ($i in 1..60) {
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:3000/api/health | Out-Null
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:9090/-/ready | Out-Null
    $ok = $true; break
  } catch { Write-Host -NoNewline "."; Start-Sleep -Seconds 2 }
}
Write-Host ""
if (-not $ok) { Write-Host "Still starting. Check: docker compose ps   and   docker compose logs grafana"; exit 1 }

Write-Host ""
Write-Host "MONITORING IS READY"
Write-Host ("  Grafana        http://localhost:3000    user: {0}   password: {1}" -f (Get-EnvValue "GRAFANA_ADMIN_USER"), (Get-EnvValue "GRAFANA_ADMIN_PASSWORD"))
Write-Host "  Prometheus     http://localhost:9090"
Write-Host "  Alertmanager   http://localhost:9093"
Write-Host "  Demo app       http://localhost:8080"
Write-Host ""
Write-Host "Next:  .\scripts\check.ps1   then   .\scripts\break.ps1   (and .\scripts\fix.ps1)"
