# Setup Screenshot Path Keybinding
# Jalanin di PowerShell (tidak perlu admin)
# Prerequisite: Git Bash (mintty) sudah terinstall

$repoBase   = "https://raw.githubusercontent.com/gerald2581/.claude-skill/main/screenshot-watcher"
$scriptsDir = "$env:USERPROFILE\.claude\scripts"
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

# 1. Buat folder scripts
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null

# 2. Download scripts dari repo
Write-Host "Downloading scripts..."
Invoke-WebRequest "$repoBase/watch-screenshots.ps1" -OutFile "$scriptsDir\watch-screenshots.ps1"
Invoke-WebRequest "$repoBase/ensure-watcher.ps1"    -OutFile "$scriptsDir\ensure-watcher.ps1"
Write-Host "[OK] Scripts downloaded"

# 3. Tulis/update .minttyrc
$minttyrc    = "$env:USERPROFILE\.minttyrc"
$requiredLine = 'Key_Ctrl+V=\e[200~%p\e[201~'
if (-not (Test-Path $minttyrc)) {
    Set-Content -Path $minttyrc -Value $requiredLine -Encoding UTF8
    Write-Host "[OK] .minttyrc dibuat"
} elseif (-not (Select-String -Path $minttyrc -Pattern 'Key_Ctrl\+V' -Quiet)) {
    Add-Content -Path $minttyrc -Value $requiredLine
    Write-Host "[OK] Key_Ctrl+V ditambahkan ke .minttyrc"
} else {
    Write-Host "[OK] .minttyrc sudah terkonfigurasi"
}

# 4. Buat VBS di Startup folder
$vbsPath = "$startupDir\ScreenshotWatcher.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -File """ & "$scriptsDir\watch-screenshots.ps1" & """", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding UTF8
Write-Host "[OK] Auto-start dikonfigurasi"

# 5. Jalanin watcher sekarang
powershell.exe -ExecutionPolicy Bypass -File "$scriptsDir\ensure-watcher.ps1"
Start-Sleep -Seconds 4
$p = Get-Content "$scriptsDir\watcher.pid" -ErrorAction SilentlyContinue
if ($p -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) {
    Write-Host "[OK] Watcher aktif"
} else {
    Write-Host "[WARN] Watcher gagal start - coba restart Windows"
}

Write-Host ""
Write-Host "Setup selesai!"
Write-Host "- Restart Git Bash supaya Ctrl+V aktif"
Write-Host "- Win+Shift+S -> screenshot -> Shift+Insert = paste path"
Write-Host "- Copy teks -> Shift+Insert = paste teks normal"
