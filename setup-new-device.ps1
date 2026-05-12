# Setup Screenshot Path Keybinding
# Jalanin di PowerShell (tidak perlu admin)
# Prerequisite: Git Bash (mintty) sudah terinstall

$scriptsDir = "$env:USERPROFILE\.claude\scripts"
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

# 1. Buat folder scripts
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null

# 2. Tulis watch-screenshots.ps1
$watcherScript = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;

public class ScreenshotApp : Form {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, int mod, int vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    const int WM_HOTKEY = 0x0312;
    const int MOD_SHIFT = 0x0004;
    const int VK_INSERT = 0x2D;
    const uint KEYUP = 0x0002;

    readonly string pathFile;
    readonly string saveDir;
    string lastHash = null;
    System.Windows.Forms.Timer clipTimer;

    public ScreenshotApp(string pathFile, string saveDir) {
        this.pathFile = pathFile;
        this.saveDir = saveDir;
        this.WindowState = FormWindowState.Minimized;
        this.ShowInTaskbar = false;
        this.FormBorderStyle = FormBorderStyle.None;

        clipTimer = new System.Windows.Forms.Timer();
        clipTimer.Interval = 500;
        clipTimer.Tick += CheckClipboard;
        clipTimer.Start();
    }

    void CheckClipboard(object s, EventArgs e) {
        try {
            Image img = Clipboard.GetImage();
            if (img == null) return;
            using (var ms = new MemoryStream()) {
                img.Save(ms, ImageFormat.Png);
                byte[] bytes = ms.ToArray();
                string hash = BitConverter.ToString(MD5.Create().ComputeHash(bytes));
                if (hash == lastHash) { img.Dispose(); return; }
                lastHash = hash;
                string ts = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
                string fp = Path.Combine(saveDir, "Screenshot_" + ts + ".png");
                img.Save(fp);
                img.Dispose();
                File.WriteAllText(pathFile, fp);
            }
        } catch {}
    }

    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        this.Visible = false;
        RegisterHotKey(this.Handle, 1, MOD_SHIFT, VK_INSERT);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == 1) {
            try {
                string path = File.ReadAllText(pathFile).Trim();
                if (!string.IsNullOrEmpty(path)) {
                    Clipboard.SetText(path);
                    Thread.Sleep(100);
                    keybd_event(0x11, 0, 0, UIntPtr.Zero);
                    keybd_event(0x56, 0, 0, UIntPtr.Zero);
                    keybd_event(0x56, 0, KEYUP, UIntPtr.Zero);
                    keybd_event(0x11, 0, KEYUP, UIntPtr.Zero);
                }
            } catch {}
        }
        base.WndProc(ref m);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        clipTimer.Stop();
        UnregisterHotKey(this.Handle, 1);
        base.OnFormClosing(e);
    }

    [STAThread]
    public static void RunApp(string pathFile, string saveDir) {
        Directory.CreateDirectory(saveDir);
        Application.EnableVisualStyles();
        Application.Run(new ScreenshotApp(pathFile, saveDir));
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing

$pathFile = "$env:USERPROFILE\.claude\scripts\last_screenshot.txt"
$saveDir  = "$env:USERPROFILE\Pictures\Screenshots"

[ScreenshotApp]::RunApp($pathFile, $saveDir)
'@

Set-Content -Path "$scriptsDir\watch-screenshots.ps1" -Value $watcherScript -Encoding UTF8

# 3. Tulis/update .minttyrc
$minttyrc = "$env:USERPROFILE\.minttyrc"
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
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & "$scriptsDir\watch-screenshots.ps1" & """", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding UTF8
Write-Host "[OK] Auto-start dikonfigurasi"

# 5. Jalanin watcher sekarang
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptsDir\watch-screenshots.ps1`"" -WindowStyle Hidden
Start-Sleep -Seconds 2

$running = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID }
if ($running) {
    Write-Host "[OK] Watcher aktif"
} else {
    Write-Host "[WARN] Watcher gagal start - coba jalanin manual"
}

Write-Host ""
Write-Host "Setup selesai!"
Write-Host "- Restart Git Bash supaya Ctrl+V aktif"
Write-Host "- Win+Shift+S -> screenshot -> Shift+Insert di Git Bash = paste path"
