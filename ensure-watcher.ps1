$watcher = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*watch-screenshots.ps1*' }
if (-not $watcher) {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:USERPROFILE\.claude\scripts\watch-screenshots.ps1`"" -WindowStyle Hidden
}
