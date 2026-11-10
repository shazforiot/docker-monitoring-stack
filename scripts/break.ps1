# Break the demo app on purpose and watch the alert fire.
#   .\scripts\break.ps1               stop the app          -> DemoAppDown   (about 1 minute)
#   .\scripts\break.ps1 -Mode errors  60% of orders fail    -> HighErrorRate (about 2 minutes)
#   .\scripts\break.ps1 -Mode slow    orders take 1 s more  -> SlowRequests  (about 2 minutes)
param([ValidateSet("down", "errors", "slow")][string]$Mode = "down")
Set-Location (Join-Path $PSScriptRoot "..")
if ($Mode -eq "down") {
  docker compose stop demo-app
  Write-Host "demo-app stopped. Watch http://localhost:9090/alerts (pending, then firing in about 40 s)."
} else {
  Invoke-RestMethod "http://localhost:8080/chaos?mode=$Mode" | Out-Null
  Write-Host "Chaos mode '$Mode' is on. Watch the Demo App dashboard."
}
