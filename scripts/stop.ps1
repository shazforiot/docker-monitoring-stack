# Stop the stack.   .\scripts\stop.ps1          keep metrics, logs and dashboards
#                   .\scripts\stop.ps1 -Reset   also delete all stored data
param([switch]$Reset)
Set-Location (Join-Path $PSScriptRoot "..")
if ($Reset) {
  docker compose down -v
  Write-Host "Stopped. All stored metrics, logs and Grafana data were deleted."
} else {
  docker compose down
  Write-Host "Stopped. Data is kept in Docker volumes. Start again with .\scripts\start.ps1"
}
