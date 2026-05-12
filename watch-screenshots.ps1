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
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }

    const int WH_KEYBOARD_LL = 13;
    const int WM_KEYDOWN     = 0x0100;
    const int VK_SHIFT       = 0x10;
    const int VK_INSERT      = 0x2D;
    const uint KEYUP         = 0x0002;

    readonly string pathFile;
    readonly string saveDir;
    string lastHash    = null;
    bool skipNext      = false;
    IntPtr hookId      = IntPtr.Zero;
    LowLevelKeyboardProc hookProc;
    System.Windows.Forms.Timer clipTimer;

    public ScreenshotApp(string pathFile, string saveDir) {
        this.pathFile = pathFile;
        this.saveDir  = saveDir;
        this.WindowState    = FormWindowState.Minimized;
        this.ShowInTaskbar  = false;
        this.FormBorderStyle = FormBorderStyle.None;
        this.Size = new System.Drawing.Size(1, 1);

        clipTimer = new System.Windows.Forms.Timer();
        clipTimer.Interval = 500;
        clipTimer.Tick += CheckClipboard;
        clipTimer.Start();
    }

    IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN) {
            var s = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
            bool isShiftInsert = s.vkCode == VK_INSERT && (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

            if (isShiftInsert) {
                if (skipNext) { skipNext = false; return CallNextHookEx(hookId, nCode, wParam, lParam); }

                if (Clipboard.ContainsImage()) {
                    try {
                        string path = File.ReadAllText(pathFile).Trim();
                        if (!string.IsNullOrEmpty(path)) {
                            Clipboard.SetText(path);
                            Thread.Sleep(50);
                            skipNext = true;
                            keybd_event(VK_SHIFT, 0, 0, UIntPtr.Zero);
                            keybd_event(VK_INSERT, 0, 0, UIntPtr.Zero);
                            keybd_event(VK_INSERT, 0, KEYUP, UIntPtr.Zero);
                            keybd_event(VK_SHIFT, 0, KEYUP, UIntPtr.Zero);
                        }
                    } catch {}
                    return new IntPtr(1); // suppress original
                }
                // teks/lainnya: pass through ke mintty
            }
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    void CheckClipboard(object s, EventArgs e) {
        try {
            Image img = Clipboard.GetImage();
            if (img == null) return;
            using (var ms = new MemoryStream()) {
                img.Save(ms, ImageFormat.Png);
                string hash = BitConverter.ToString(MD5.Create().ComputeHash(ms.ToArray()));
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
        hookProc = HookCallback;
        hookId = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc, GetModuleHandle(null), 0);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        clipTimer.Stop();
        if (hookId != IntPtr.Zero) UnhookWindowsHookEx(hookId);
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
