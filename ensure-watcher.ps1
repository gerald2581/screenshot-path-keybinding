$scriptPath = "$env:USERPROFILE\.claude\scripts\watch-screenshots.ps1"

# Kill semua watcher yang sedang jalan
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*watch-screenshots.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
} catch {}

# Start satu watcher baru — tanpa -WindowStyle Hidden di PS args (WinForms perlu window context)
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden
