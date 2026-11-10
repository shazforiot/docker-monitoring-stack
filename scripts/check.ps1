# Health check: containers, Prometheus targets, firing alerts, logs in Loki.
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "== Containers =="
docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}"

Write-Host ""; Write-Host "== Prometheus targets (1 = up, 0 = down) =="
try {
  $r = Invoke-RestMethod -TimeoutSec 5 "http://localhost:9090/api/v1/query?query=up"
  $r.data.result | Sort-Object { $_.metric.job } | ForEach-Object { "  {0}  {1}" -f $_.value[1], $_.metric.job }
} catch { Write-Host "  Prometheus is not answering on http://localhost:9090" }

Write-Host ""; Write-Host "== Firing alerts =="
try {
  $a = Invoke-RestMethod -TimeoutSec 5 "http://localhost:9090/api/v1/alerts"
  $f = @($a.data.alerts | Where-Object { $_.state -eq "firing" })
  if ($f.Count -eq 0) { Write-Host "  none" } else { $f | ForEach-Object { "  {0} ({1})" -f $_.labels.alertname, $_.labels.severity } | Sort-Object -Unique }
} catch { Write-Host "  Prometheus is not answering" }

Write-Host ""; Write-Host "== Logs in Loki (services seen) =="
$l = docker compose exec -T grafana wget -qO- "http://loki:3100/loki/api/v1/label/service/values" 2>$null
if ($l) { try { "  " + ((($l | ConvertFrom-Json).data) -join "  ") } catch { "  $l" } } else { Write-Host "  Loki is not answering yet" }
Write-Host ""
