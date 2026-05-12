# Single-instance via PID file
$pidFile = "$env:USERPROFILE\.claude\scripts\watcher.pid"
if (Test-Path $pidFile) {
    $oldPid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { exit 0 }
}
$PID | Set-Content $pidFile

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
        this.Size = new System.Drawing.Size(1, 1);

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
