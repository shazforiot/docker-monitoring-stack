# Undo scripts\break.ps1: start the app again and switch chaos mode off.
Set-Location (Join-Path $PSScriptRoot "..")
docker compose start demo-app
Start-Sleep -Seconds 2
try { Invoke-RestMethod "http://localhost:8080/chaos?mode=off" | Out-Null } catch {}
Write-Host "demo-app is running again. The alert resolves in about a minute."
