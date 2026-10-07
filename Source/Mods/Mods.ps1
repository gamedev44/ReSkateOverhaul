#Requires -Version 5.1
param(
    [string]$Drive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class UiTheme {
  [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
  public static extern int SetWindowTheme(IntPtr hwnd, string subApp, IntPtr subId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll", EntryPoint = "SendMessageW")]
  public static extern IntPtr SendMessagePtr(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
  [DllImport("uxtheme.dll", EntryPoint = "#135")]
  static extern int SetPreferredAppMode(int mode);
  [DllImport("uxtheme.dll", EntryPoint = "#133")]
  static extern int AllowDarkModeForWindow(IntPtr hwnd, bool allow);
  [DllImport("dwmapi.dll")]
  static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
  public static void PreferDark() {
    try { SetPreferredAppMode(2); } catch {}
  }
  public static void DarkScroll(IntPtr hwnd) {
    try { AllowDarkModeForWindow(hwnd, true); } catch {}
    SetWindowTheme(hwnd, "DarkMode_Explorer", IntPtr.Zero);
  }
  public static void DarkCaption(IntPtr hwnd) {
    int on = 1;
    int caption = 0x00101010;
    int text = 0x00F5F5F5;
    int border = 0x002A2A2A;
    int round = 2;
    DwmSetWindowAttribute(hwnd, 20, ref on, 4);
    DwmSetWindowAttribute(hwnd, 35, ref caption, 4);
    DwmSetWindowAttribute(hwnd, 36, ref text, 4);
    DwmSetWindowAttribute(hwnd, 34, ref border, 4);
    DwmSetWindowAttribute(hwnd, 33, ref round, 4);
  }
  public static void SetBorder(IntPtr hwnd, int color) {
    DwmSetWindowAttribute(hwnd, 34, ref color, 4);
  }
}
public class WinFocus {
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
}
"@
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class UiBackdrop {
  public static Bitmap Make(string path, int width, int height) {
    byte[] bytes = System.IO.File.ReadAllBytes(path);
    Bitmap raw;
    using (var ms = new System.IO.MemoryStream(bytes))
    using (var img = Image.FromStream(ms)) {
      raw = Cover(img, Math.Max(1, width / 2), Math.Max(1, height / 2));
    }
    BoxBlur(raw, 8);
    BoxBlur(raw, 4);
    var full = new Bitmap(width, height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(full)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.DrawImage(raw, 0, 0, width, height);
      using (var veil = new SolidBrush(Color.FromArgb(72, 0, 0, 0)))
        g.FillRectangle(veil, 0, 0, width, height);
    }
    raw.Dispose();
    return full;
  }
  static Bitmap Cover(Image src, int width, int height) {
    float scale = Math.Max(width / (float)src.Width, height / (float)src.Height);
    int dw = Math.Max(1, (int)(src.Width * scale));
    int dh = Math.Max(1, (int)(src.Height * scale));
    var bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.Clear(Color.Black);
      g.DrawImage(src, (width - dw) / 2, (height - dh) / 2, dw, dh);
    }
    return bmp;
  }
  static void BoxBlur(Bitmap bmp, int radius) {
    int w = bmp.Width, h = bmp.Height, r = Math.Max(1, radius);
    var rect = new Rectangle(0, 0, w, h);
    var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    int bytes = stride * h;
    byte[] src = new byte[bytes];
    byte[] tmp = new byte[bytes];
    Marshal.Copy(data.Scan0, src, 0, bytes);
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        int b = 0, g = 0, rd = 0, a = 0, c = 0;
        int x0 = Math.Max(0, x - r), x1 = Math.Min(w - 1, x + r);
        for (int i = x0; i <= x1; i++) {
          int p = row + i * 4;
          b += src[p]; g += src[p + 1]; rd += src[p + 2]; a += src[p + 3]; c++;
        }
        int o = row + x * 4;
        tmp[o] = (byte)(b / c); tmp[o + 1] = (byte)(g / c); tmp[o + 2] = (byte)(rd / c); tmp[o + 3] = (byte)(a / c);
      }
    }
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        int b = 0, g = 0, rd = 0, a = 0, c = 0;
        int y0 = Math.Max(0, y - r), y1 = Math.Min(h - 1, y + r);
        for (int i = y0; i <= y1; i++) {
          int p = i * stride + x * 4;
          b += tmp[p]; g += tmp[p + 1]; rd += tmp[p + 2]; a += tmp[p + 3]; c++;
        }
        int o = y * stride + x * 4;
        src[o] = (byte)(b / c); src[o + 1] = (byte)(g / c); src[o + 2] = (byte)(rd / c); src[o + 3] = (byte)(a / c);
      }
    }
    Marshal.Copy(src, 0, data.Scan0, bytes);
    bmp.UnlockBits(data);
  }
}
public class GlassPanel : Panel {
  public GlassPanel() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { PaintParent(this, e); }
  public static void PaintParent(Control self, PaintEventArgs e) {
    Form form = self.FindForm();
    Image img = form == null ? null : form.BackgroundImage;
    if (img == null || form.ClientSize.Width < 1 || form.ClientSize.Height < 1) { return; }
    Point screen = self.PointToScreen(Point.Empty);
    Point origin = form.PointToScreen(Point.Empty);
    int dx = screen.X - origin.X;
    int dy = screen.Y - origin.Y;
    Rectangle dest = e.ClipRectangle;
    float sx = img.Width / (float)form.ClientSize.Width;
    float sy = img.Height / (float)form.ClientSize.Height;
    var src = new RectangleF((dx + dest.X) * sx, (dy + dest.Y) * sy, Math.Max(1f, dest.Width * sx), Math.Max(1f, dest.Height * sy));
    e.Graphics.DrawImage(img, dest, src, GraphicsUnit.Pixel);
  }
}
public class GlassTable : TableLayoutPanel {
  public GlassTable() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { GlassPanel.PaintParent(this, e); }
}
public class GlassFlow : FlowLayoutPanel {
  public GlassFlow() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { GlassPanel.PaintParent(this, e); }
}
public class UiShape {
  public static Region Round(int width, int height, int radius) {
    int d = Math.Min(Math.Max(1, radius) * 2, Math.Min(width, height));
    var path = new GraphicsPath();
    path.AddArc(0, 0, d, d, 180, 90);
    path.AddArc(width - d, 0, d, d, 270, 90);
    path.AddArc(width - d, height - d, d, d, 0, 90);
    path.AddArc(0, height - d, d, d, 90, 90);
    path.CloseFigure();
    return new Region(path);
  }
  public static Region Chamfer(int width, int height, int cut) {
    int c = Math.Max(1, Math.Min(cut, Math.Min(width, height) / 3));
    var path = new GraphicsPath();
    path.AddPolygon(new Point[] {
      new Point(c, 0), new Point(width - c, 0), new Point(width, c), new Point(width, height - c),
      new Point(width - c, height), new Point(c, height), new Point(0, height - c), new Point(0, c)
    });
    return new Region(path);
  }
}
public class ClickWatch : NativeWindow {
  public event EventHandler Pressed;
  protected override void WndProc(ref Message m) {
    int msg = m.Msg;
    if (msg == 0x0210) {
      int code = m.WParam.ToInt32() & 0xFFFF;
      if (code == 0x0201) Raise();
    }
    else if (msg == 0x0201) Raise();
    base.WndProc(ref m);
  }
  void Raise() {
    if (Pressed != null) Pressed(this, EventArgs.Empty);
  }
}
public class RoundField : Panel {
  public int Radius = 12;
  public RoundField() {
    DoubleBuffered = true;
    ResizeRedraw = true;
    BackColor = Color.FromArgb(58, 58, 58);
  }
  protected override void OnPaintBackground(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    int w = Math.Max(1, Width - 1);
    int h = Math.Max(1, Height - 1);
    int d = Math.Min(Math.Max(2, Radius * 2), Math.Min(w, h));
    using (var path = new GraphicsPath()) {
      path.AddArc(0, 0, d, d, 180, 90);
      path.AddArc(w - d, 0, d, d, 270, 90);
      path.AddArc(w - d, h - d, d, d, 0, 90);
      path.AddArc(0, h - d, d, d, 90, 90);
      path.CloseFigure();
      using (var brush = new SolidBrush(BackColor))
      using (var pen = new Pen(Color.FromArgb(120, 120, 120))) {
        e.Graphics.FillPath(brush, path);
        e.Graphics.DrawPath(pen, path);
      }
    }
  }
  protected override void OnResize(EventArgs e) {
    base.OnResize(e);
    if (Width > 8 && Height > 8) Region = UiShape.Round(Width, Height, Radius);
  }
}
"@
[System.Windows.Forms.Application]::EnableVisualStyles()
[UiTheme]::PreferDark()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$StoreApi = "https://thunderstore.io/c/reskate/api/v1/package/"
$StorePage = "https://old.thunderstore.io/c/reskate/"
$Script:ByFull = @{}
$Script:SkateRoot = $null
$Script:Installing = @{}
$Script:DlDepth = 0
$Script:ModsPage = "Recommended"
$Script:ModCategory = "All"
$Script:BrowseSection = "mods"
$Script:BrowseOrder = "last-updated"
$Script:PackageKind = "mods"
$Script:CatalogReady = $false
$Script:StoreHover = -1
$emptyNote = $null
$installedEmpty = $null
$profileEmpty = $null
$Script:ModPicks = @(
    @{ Cat = "Skate 2"; Owner = "brassy"; Name = "Skate2Map"; Title = "Skate2Map" }
    @{ Cat = "Skate 2"; Owner = "Prayboy"; Name = "Skate2Soundtracks"; Title = "Skate 2 Soundtracks" }
    @{ Cat = "Skate 3"; Owner = "zeex64"; Name = "Full_Skate_3_Map"; Title = "Full Skate 3 Map" }
    @{ Cat = "Skate 3"; Owner = "333"; Name = "Skate_3_Improved"; Title = "Skate 3 Improved" }
    @{ Cat = "Skate 3"; Owner = "Prayboy"; Name = "Skate3Soundtrack"; Title = "Skate 3 Soundtrack" }
    @{ Cat = "Skater XL"; Owner = "brassy"; Name = "bedroom"; Title = "Bedroom" }
    @{ Cat = "Skater XL"; Owner = "AltDoug"; Name = "South_Florida"; Title = "South Florida" }
    @{ Cat = "Other"; Owner = "Lukas9875"; Name = "Bullworth"; Title = "Bullworth" }
    @{ Cat = "Other"; Owner = "relsmodding"; Name = "Bo2_Grind"; Title = "Bo2 Grind" }
    @{ Cat = "Other"; Owner = "forestmouse"; Name = "The_SLS_Hangar"; Title = "The SLS Hangar" }
    @{ Cat = "Maps"; Owner = "zeex64"; Name = "Full_Skate_3_Map"; Title = "Full Skate 3 Map" }
    @{ Cat = "Maps"; Owner = "333"; Name = "Skate_3_Improved"; Title = "Skate 3 Improved" }
    @{ Cat = "Maps"; Owner = "brassy"; Name = "Skate2Map"; Title = "Skate2Map" }
    @{ Cat = "Maps"; Owner = "AltDoug"; Name = "South_Florida"; Title = "South Florida" }
    @{ Cat = "Maps"; Owner = "brassy"; Name = "bedroom"; Title = "Bedroom" }
    @{ Cat = "Maps"; Owner = "Lukas9875"; Name = "Bullworth"; Title = "Bullworth" }
    @{ Cat = "Maps"; Owner = "relsmodding"; Name = "Bo2_Grind"; Title = "Bo2 Grind" }
    @{ Cat = "Maps"; Owner = "forestmouse"; Name = "The_SLS_Hangar"; Title = "The SLS Hangar" }
    @{ Cat = "Audio"; Owner = "Prayboy"; Name = "Skate3Soundtrack"; Title = "Skate 3 Soundtrack" }
    @{ Cat = "Audio"; Owner = "Prayboy"; Name = "Skate2Soundtracks"; Title = "Skate 2 Soundtracks" }
)

function Find-SkateRoots {
    $hits = New-Object System.Collections.Generic.List[string]
    $rels = @(
        "Steam\steamapps\common\Skate",
        "Program Files (x86)\Steam\steamapps\common\Skate",
        "Program Files\Steam\steamapps\common\Skate"
    )
    $letters = @()
    if ($Drive) { $letters += ($Drive.ToUpper() -replace "[^A-Z]", "").Substring(0, 1) }
    foreach ($disk in (Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3")) {
        $letters += $disk.DeviceID.TrimEnd(":").Substring(0, 1)
    }
    $letters = $letters | Select-Object -Unique
    foreach ($letter in $letters) {
        foreach ($rel in $rels) {
            $path = "{0}:\{1}" -f $letter, $rel
            if (Test-Path -LiteralPath (Join-Path $path "Skate.exe")) {
                $hits.Add([IO.Path]::GetFullPath($path))
            }
        }
    }
    return $hits
}

function Write-LogBox {
    param([string]$Message)
    $logBox.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format "HH:mm:ss"), $Message))
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-ModsRoot {
    if (-not $Script:SkateRoot) { throw "Choose the Skate folder first." }
    $mods = Join-Path $Script:SkateRoot "Mods"
    if (-not (Test-Path -LiteralPath $mods)) {
        New-Item -ItemType Directory -Path $mods -Force | Out-Null
    }
    return $mods
}

function Get-ProfilesRoot {
    $root = Join-Path $RepoRoot "Profiles"
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-SafeProfileName {
    param([string]$Name)
    $clean = $Name.Trim()
    if (-not $clean) { throw "Enter a profile name." }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $clean = $clean.Replace([string]$char, "")
    }
    $clean = $clean.Trim().TrimEnd(".")
    if (-not $clean) { throw "That name cannot be used as a folder." }
    return $clean
}

function Refresh-Profiles {
    if ($null -eq $profileList) { return }
    $profileList.Items.Clear()
    $root = Get-ProfilesRoot
    Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name | ForEach-Object {
        [void]$profileList.Items.Add($_.Name)
    }
    if ($null -ne $profileEmpty) {
        $profileEmpty.Visible = ($profileList.Items.Count -eq 0)
        if ($profileEmpty.Visible) { $profileEmpty.BringToFront() }
    }
}

function Save-ModProfile {
    param([string]$Name)
    $safe = Get-SafeProfileName $Name
    $dest = Join-Path (Get-ProfilesRoot) $safe
    if (Test-Path -LiteralPath $dest) {
        $answer = [System.Windows.Forms.MessageBox]::Show("Replace profile $safe ?", "ReSkate", "YesNo")
        if ($answer -ne "Yes") { return }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    $modsDest = Join-Path $dest "Mods"
    New-Item -ItemType Directory -Path $modsDest -Force | Out-Null
    $live = Get-ModsRoot
    $names = New-Object System.Collections.Generic.List[string]
    Write-LogBox "Saving profile $safe"
    foreach ($dir in @(Get-ChildItem -LiteralPath $live -Directory -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $dir.FullName -Destination (Join-Path $modsDest $dir.Name) -Recurse -Force
        $names.Add($dir.Name)
    }
    $order = Join-Path $live "mods.json"
    if (Test-Path -LiteralPath $order) {
        Copy-Item -LiteralPath $order -Destination (Join-Path $dest "mods.json") -Force
    }
    $meta = @{
        name   = $safe
        savedAt = (Get-Date).ToString("o")
        mods   = [bool]$autoMods.Checked
        folders = @($names)
    }
    $meta | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dest "profile.json") -Encoding UTF8
    Write-LogBox "Saved profile $safe ($($names.Count) mods) -> Profiles\$safe"
    Refresh-Profiles
}

function Install-ModProfile {
    param([string]$Name)
    $dest = Join-Path (Get-ProfilesRoot) $Name
    $modsSrc = Join-Path $dest "Mods"
    if (-not (Test-Path -LiteralPath $modsSrc)) { throw "Profile $Name has no Mods folder." }
    $live = Get-ModsRoot
    Write-LogBox "Loading profile $Name"
    foreach ($dir in @(Get-ChildItem -LiteralPath $modsSrc -Directory -ErrorAction SilentlyContinue)) {
        $target = Join-Path $live $dir.Name
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Copy-Item -LiteralPath $dir.FullName -Destination $target -Recurse -Force
    }
    $order = Join-Path $dest "mods.json"
    if (Test-Path -LiteralPath $order) {
        Copy-Item -LiteralPath $order -Destination (Join-Path $live "mods.json") -Force
    }
    $metaPath = Join-Path $dest "profile.json"
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        $flag = $meta.PSObject.Properties["mods"]
        if ($flag) { $autoMods.Checked = [bool]$flag.Value }
    }
    Refresh-Installed
    Write-LogBox "Loaded profile $Name into Mods"
}

function Return-ToGameSelect {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'Source\\Launch\\Select\.ps1' })
    if ($running.Count -gt 0) {
        $hostProcess = Get-Process -Id $running[0].ProcessId -ErrorAction SilentlyContinue
        if ($hostProcess -and $hostProcess.MainWindowHandle -ne [IntPtr]::Zero) {
            [void][WinFocus]::ShowWindow($hostProcess.MainWindowHandle, 9)
            [void][WinFocus]::SetForegroundWindow($hostProcess.MainWindowHandle)
            $form.Close()
            return
        }
    }
    $script = Join-Path $RepoRoot "Source\Launch\Select.ps1"
    $argLine = "-NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argLine -WindowStyle Hidden
    $form.Close()
}

function Test-ZipSlip {
    param([string]$ZipPath)
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace("/", "\")
            if ($name.StartsWith("\") -or $name -match "^[A-Za-z]:\\" -or ($name.Split("\") -contains "..")) {
                throw "Unsafe path in archive: $($entry.FullName)"
            }
        }
    }
    finally { $zip.Dispose() }
}

function Expand-ModZip {
    param([string]$ZipPath, [string]$Destination)
    Test-ZipSlip $ZipPath
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

function Get-ModRoot {
    param([string]$Directory)
    $current = $Directory
    for ($i = 0; $i -lt 3; $i++) {
        $markers = @("manifest.json", "reskate-levels.json", "layout.toc") | Where-Object {
            Test-Path -LiteralPath (Join-Path $current $_)
        }
        $payload = @(Get-ChildItem -LiteralPath $current -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @(".dll", ".lua", ".ogg", ".mp3", ".wav", ".flac")
        })
        if ($markers -or $payload.Count -gt 0) { return $current }
        $dirs = @(Get-ChildItem -LiteralPath $current -Directory -Force | Where-Object { $_.Name -ne "__MACOSX" })
        $files = @(Get-ChildItem -LiteralPath $current -File -Force | Where-Object { $_.Name -notin @(".DS_Store") })
        if ($dirs.Count -eq 1 -and $files.Count -eq 0) {
            $current = $dirs[0].FullName
            continue
        }
        break
    }
    return $current
}

function Get-ModKind {
    param([string]$Directory)
    if (Test-Path -LiteralPath (Join-Path $Directory "reskate-levels.json")) { return "map" }
    if (Test-Path -LiteralPath (Join-Path $Directory "layout.toc")) { return "frostbite map" }
    if (Test-Path -LiteralPath (Join-Path $Directory "manifest.json")) { return "thunderstore package" }
    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse -ErrorAction SilentlyContinue)
    if ($files | Where-Object { $_.Extension -eq ".lua" }) { return "lua script" }
    if ($files | Where-Object { $_.Extension -eq ".dll" }) { return "dll plugin" }
    if ($files | Where-Object { $_.Extension -in @(".ogg", ".mp3", ".wav", ".flac") }) { return "audio pack" }
    return "mod folder"
}

function Copy-ModPayload {
    param([string]$Source, [string]$Destination)
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -ne "__MACOSX" } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Recurse -Force
    }
}

function Install-LocalTree {
    param([string]$Path, [string]$FolderName)
    $kindSource = $Path
    $work = $Path
    $temp = $null
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing: $Path" }
    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) {
        if ($item.Extension -match '^\.(exe|bat|cmd|ps1|msi)$') {
            throw "Refusing to run $($item.Name). Mods are folders, not installers."
        }
        if ($item.Extension -eq ".zip" -or ((Get-Content -LiteralPath $Path -Encoding Byte -TotalCount 2) -join ',') -eq "80,75") {
            $temp = Join-Path $env:TEMP ("ReSkateMod-" + [guid]::NewGuid().ToString("N"))
            Expand-ModZip -ZipPath $Path -Destination $temp
            $work = Get-ModRoot $temp
            $kindSource = $work
        }
        elseif ($item.Extension -eq ".dll") {
            $temp = Join-Path $env:TEMP ("ReSkateMod-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            Copy-Item -LiteralPath $Path -Destination (Join-Path $temp $item.Name) -Force
            $work = $temp
        }
        else {
            $temp = Join-Path $env:TEMP ("ReSkateMod-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            Copy-Item -LiteralPath $Path -Destination (Join-Path $temp $item.Name) -Force
            $work = $temp
        }
    }
    else {
        $work = Get-ModRoot $Path
    }
    $kind = Get-ModKind $work
    if (-not $FolderName) {
        $manifestPath = Join-Path $work "manifest.json"
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($manifest.name) { $FolderName = [string]$manifest.name }
        }
        if (-not $FolderName) { $FolderName = (Get-Item -LiteralPath $work).Name }
    }
    $FolderName = ($FolderName -replace '[<>:"/\\|?*]', "").Trim()
    if (-not $FolderName) { throw "Could not name this mod." }
    $dest = Join-Path (Get-ModsRoot) $FolderName
    Copy-ModPayload -Source $work -Destination $dest
    if ($temp -and (Test-Path -LiteralPath $temp)) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-LogBox "Installed $FolderName ($kind) -> Mods\$FolderName"
}

function Test-NewerVersion {
    param([string]$Latest, [string]$Installed)
    if (-not $Installed) { return $true }
    try { return ([version]$Latest) -gt ([version]$Installed) }
    catch { return $Latest -ne $Installed }
}

function Get-ReSkateSettings {
    $path = Join-Path $RepoRoot "ReSkate.settings.json"
    $settings = @{ reskate = $false; mods = $false }
    if (-not (Test-Path -LiteralPath $path)) { return $settings }
    try {
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($key in @("reskate", "mods")) {
            $prop = $json.PSObject.Properties[$key]
            if ($prop) { $settings[$key] = [bool]$prop.Value }
        }
    }
    catch {}
    return $settings
}

function Save-ReSkateSettings {
    param($Settings)
    $payload = @{ reskate = [bool]$Settings.reskate; mods = [bool]$Settings.mods }
    $payload | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RepoRoot "ReSkate.settings.json") -Encoding UTF8
}

function Show-DownloadBar([string]$Name, [int]$Percent) {
    $pct = [Math]::Max(0, [Math]::Min(100, $Percent))
    if (-not $dlHost.Visible) { $dlHost.Visible = $true }
    $dlName.Text = $Name
    if ($dlBar.Value -ne $pct) { $dlBar.Value = $pct }
    $dlPct.Text = "{0}%" -f $pct
}

function Hide-DownloadBar {
    $dlHost.Visible = $false
    $dlBar.Value = 0
    $dlPct.Text = ""
    $dlName.Text = ""
}

function Receive-PackageFile([string]$Url, [string]$Destination, [string]$Name) {
    $client = New-Object System.Net.WebClient
    $client.Headers["User-Agent"] = "ReSkateMods"
    $Script:DlDone = $false
    $Script:DlError = $null
    $client.Add_DownloadProgressChanged({
        $pct = [int]$_.ProgressPercentage
        $bar = $dlBar
        $label = $dlPct
        $apply = {
            $safe = [Math]::Max(0, [Math]::Min(100, $pct))
            if ($bar.Value -ne $safe) { $bar.Value = $safe }
            $label.Text = "{0}%" -f $safe
        }.GetNewClosure()
        if ($bar.IsHandleCreated -and $bar.InvokeRequired) { [void]$bar.BeginInvoke($apply) }
        else { & $apply }
    }.GetNewClosure())
    $client.Add_DownloadFileCompleted({
        if ($_.Error) { $Script:DlError = [string]$_.Error.Message }
        elseif ($_.Cancelled) { $Script:DlError = "Download cancelled." }
        $Script:DlDone = $true
    })
    Show-DownloadBar $Name 0
    try {
        $client.DownloadFileAsync([Uri]$Url, $Destination)
        while (-not $Script:DlDone) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
        }
        if ($Script:DlError) { throw $Script:DlError }
        Show-DownloadBar $Name 100
    }
    finally { $client.Dispose() }
}

function Install-StorePackage {
    param($Package, [switch]$Update)
    $folder = "{0}-{1}" -f $Package.Owner, $Package.Name
    if ($Script:Installing.ContainsKey($folder)) { return }
    $Script:Installing[$folder] = $true
    $Script:DlDepth++
    try {
        $mods = Get-ModsRoot
        if ((Test-Path -LiteralPath (Join-Path $mods $folder)) -and -not $Update) {
            Write-LogBox "Already installed: $folder"
            return
        }
        foreach ($dep in @($Package.Dependencies)) {
            if ($dep -match '^(?<owner>[^-]+)-(?<name>.+)-(?<ver>\d+\.\d+\.\d+.*)$') {
                $key = "{0}-{1}" -f $Matches.owner, $Matches.name
                if ($Script:ByFull.ContainsKey($key) -and -not (Test-Path -LiteralPath (Join-Path $mods $key))) {
                    Write-LogBox "Dependency $key"
                    Install-StorePackage $Script:ByFull[$key]
                }
            }
        }
        if (-not $Package.Url) { throw "No download for $folder yet. Wait for the catalog, then try again." }
        $zip = Join-Path $env:TEMP ("{0}.zip" -f $folder)
        Write-LogBox "Downloading $folder $($Package.Version)"
        Receive-PackageFile $Package.Url $zip $folder
        Install-LocalTree -Path $zip -FolderName $folder
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }
    finally {
        $Script:DlDepth--
        if ($Script:DlDepth -le 0) {
            $Script:DlDepth = 0
            Hide-DownloadBar
        }
    }
}

function Update-InstalledMods {
    $mods = Get-ModsRoot
    $changed = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $mods -Directory -ErrorAction SilentlyContinue)) {
        $manifestPath = Join-Path $dir.FullName "manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
        if (-not $Script:ByFull.ContainsKey($dir.Name)) { continue }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $installedVer = ""
        $verProp = $manifest.PSObject.Properties["version_number"]
        if ($verProp) { $installedVer = [string]$verProp.Value }
        $pkg = $Script:ByFull[$dir.Name]
        if (Test-NewerVersion $pkg.Version $installedVer) {
            Write-LogBox "Update $($dir.Name) $installedVer -> $($pkg.Version)"
            $Script:Installing.Remove($dir.Name)
            Install-StorePackage $pkg -Update
            $changed++
        }
    }
    if ($changed -eq 0) { Write-LogBox "Installed mods are current." }
    else { Write-LogBox "Updated $changed mod(s). Enable them in the ReSkate MODS menu." }
    Refresh-Installed
}

function Refresh-Installed {
    $installed.Items.Clear()
    if (-not $Script:SkateRoot) { return }
    $mods = Join-Path $Script:SkateRoot "Mods"
    if (-not (Test-Path -LiteralPath $mods)) { return }
    Get-ChildItem -LiteralPath $mods -Directory | ForEach-Object {
        $installed.Items.Add($_.Name) | Out-Null
    }
    if ($null -ne $installedEmpty) {
        $installedEmpty.Visible = ($installed.Items.Count -eq 0)
        if ($installedEmpty.Visible) { $installedEmpty.BringToFront() }
    }
}

function Add-StoreRow($pkg, [string]$Title, [string]$Category) {
    $label = $pkg.Full
    if ($Title) { $label = $Title }
    $row = New-Object System.Windows.Forms.ListViewItem($label)
    $catText = ""
    if ($Category) { $catText = $Category }
    [void]$row.SubItems.Add($catText)
    [void]$row.SubItems.Add([string]$pkg.Version)
    [void]$row.SubItems.Add([string]$pkg.Downloads)
    $row.Tag = $pkg
    [void]$store.Items.Add($row)
}

function Test-RecommendedMatch($Item, [string]$Full, [string]$Query) {
    if (-not $Query -or -not $Query.Trim()) { return $true }
    $q = $Query.Trim()
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    return ($Item.Title.IndexOf($q, $cmp) -ge 0) -or ($Full.IndexOf($q, $cmp) -ge 0) -or ($Item.Cat.IndexOf($q, $cmp) -ge 0)
}

function Show-ModpackList {
    param([string]$Query)
    $store.BeginUpdate()
    $store.Items.Clear()
    $q = ""
    if ($Query) { $q = $Query.Trim() }
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    $rows = @($Script:ByFull.Values | Where-Object { @($_.Categories) -contains "Modpacks" } | Sort-Object @{ Expression = "Downloads"; Descending = $true })
    foreach ($pkg in $rows) {
        $label = ([string]$pkg.Name).Replace("_", " ")
        if ($q -and ($label.IndexOf($q, $cmp) -lt 0) -and ($pkg.Full.IndexOf($q, $cmp) -lt 0)) { continue }
        Add-StoreRow $pkg $label "Modpack"
    }
    $store.EndUpdate()
    $countLabel.Text = "{0} modpacks" -f $store.Items.Count
    Update-StoreEmpty
}

function Show-Recommended {
    param([string]$Category, [string]$Query)
    if ($Script:PackageKind -eq "modpacks") {
        Show-ModpackList $Query
        return
    }
    $store.BeginUpdate()
    $store.Items.Clear()
    $seen = @{}
    $useAll = (-not $Category) -or ($Category -eq "All")
    foreach ($item in $Script:ModPicks) {
        $full = "{0}-{1}" -f $item.Owner, $item.Name
        if (-not $useAll -and $item.Cat -ne $Category) { continue }
        if ($useAll) {
            if ($seen.ContainsKey($full)) { continue }
            $seen[$full] = $true
        }
        if (-not (Test-RecommendedMatch $item $full $Query)) { continue }
        $pkg = $null
        if ($Script:ByFull.ContainsKey($full)) { $pkg = $Script:ByFull[$full] }
        else {
            $pkg = [pscustomobject]@{
                Owner        = [string]$item.Owner
                Name         = [string]$item.Name
                Full         = $full
                Version      = ""
                Downloads    = ""
                Url          = ""
                Page         = ("https://old.thunderstore.io/c/reskate/p/{0}/{1}/" -f $item.Owner, $item.Name)
                Dependencies = @()
            }
        }
        Add-StoreRow $pkg $item.Title $item.Cat
    }
    $store.EndUpdate()
    $countLabel.Text = "{0} packages" -f $store.Items.Count
    Update-StoreEmpty
}

function Get-ModsSearchUrl {
    param([string]$Query)
    $q = ""
    if ($Query -and $Query.Trim()) { $q = [Uri]::EscapeDataString($Query.Trim()) }
    return ("https://old.thunderstore.io/c/reskate/?q={0}&ordering={1}&section={2}" -f $q, $Script:BrowseOrder, $Script:BrowseSection)
}

function Show-ModSearch {
    param([string]$Query)
    $url = Get-ModsSearchUrl $Query
    $client = New-Object System.Net.WebClient
    $client.Headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
    try { $html = $client.DownloadString($url) }
    finally { $client.Dispose() }
    $store.BeginUpdate()
    $store.Items.Clear()
    $seen = @{}
    foreach ($match in [regex]::Matches($html, '/c/reskate/p/([^/"\s?#]+)/([^/"\s?#]+)/')) {
        $full = "{0}-{1}" -f $match.Groups[1].Value, $match.Groups[2].Value
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if ($Script:ByFull.ContainsKey($full)) { Add-StoreRow $Script:ByFull[$full] }
    }
    $store.EndUpdate()
    $countLabel.Text = "{0} packages" -f $store.Items.Count
    Update-StoreEmpty
}

function Update-StoreEmpty {
    if ($null -eq $emptyNote) { return }
    $query = ""
    if ($null -ne $filter -and $filter.Text) { $query = $filter.Text.Trim() }
    $show = ($store.Items.Count -eq 0) -and (($query.Length -gt 0) -or $Script:CatalogReady)
    $emptyNote.Text = "No results"
    $emptyNote.Visible = $show
    if ($show) { $emptyNote.BringToFront() }
}

function Load-Catalog {
    Write-LogBox "Loading ReSkate Thunderstore catalog"
    $client = New-Object System.Net.WebClient
    $client.Headers["User-Agent"] = "ReSkateMods"
    try { $raw = $client.DownloadString($StoreApi) }
    finally { $client.Dispose() }
    $rows = $raw | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    $map = @{}
    foreach ($row in $rows) {
        $ver = $row.versions | Select-Object -First 1
        if (-not $ver) { continue }
        $pkg = [pscustomobject]@{
            Owner        = [string]$row.owner
            Name         = [string]$row.name
            Full         = "{0}-{1}" -f $row.owner, $row.name
            Version      = [string]$ver.version_number
            Downloads    = [int]($row.versions | Measure-Object downloads -Sum).Sum
            Url          = [string]$ver.download_url
            Page         = "$StorePage" + "p/$($row.owner)/$($row.name)/"
            Dependencies = @($ver.dependencies)
            Categories   = @($row.categories | ForEach-Object { [string]$_ })
        }
        $list.Add($pkg)
        $map[$pkg.Full] = $pkg
    }
    $Script:ByFull = $map
    $Script:CatalogReady = $true
    if ($Script:ModsPage -eq "Browse") { Show-ModSearch $filter.Text }
    else { Show-Recommended $Script:ModCategory $filter.Text }
    Write-LogBox ("Catalog ready: {0} mods. Recommended is the default list." -f $list.Count)
}

function Set-SkateRoot {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath (Join-Path $Path "Skate.exe"))) {
        throw "Skate.exe was not found at $Path"
    }
    $Script:SkateRoot = [IO.Path]::GetFullPath($Path)
    $pathBox.Text = $Script:SkateRoot
    Refresh-Installed
    Write-LogBox "Skate: $Script:SkateRoot"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "ReSkate  |  Mods"
$form.Size = New-Object System.Drawing.Size(1080, 760)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(16, 18, 22)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$bg = [System.Drawing.Color]::FromArgb(8, 8, 8)
$panelBg = [System.Drawing.Color]::FromArgb(58, 58, 58)
$edge = [System.Drawing.Color]::FromArgb(92, 92, 92)
$form.BackColor = $bg
$bgArt = Join-Path $RepoRoot "Assets\Backgrounds\mods.jpg"
if (Test-Path -LiteralPath $bgArt) {
    $form.BackgroundImage = [UiBackdrop]::Make($bgArt, 1080, 700)
    $form.BackgroundImageLayout = "Stretch"
}
$form.ForeColor = [System.Drawing.Color]::White

function New-FlatButton {
    param([string]$Text, [int]$Width)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 32
    $button.FlatStyle = "Flat"
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = $panelBg
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $button.FlatAppearance.BorderColor = $edge
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(78, 78, 78)
    $cut = 8
    $button.Add_Resize({
        param($sender, $e)
        if ($sender.Width -lt 16 -or $sender.Height -lt 16) { return }
        $sender.Region = [UiShape]::Chamfer($sender.Width, $sender.Height, $cut)
    }.GetNewClosure())
    $button.Add_HandleCreated({
        param($sender, $e)
        if ($sender.Width -lt 16 -or $sender.Height -lt 16) { return }
        $sender.Region = [UiShape]::Chamfer($sender.Width, $sender.Height, $cut)
    }.GetNewClosure())
    return $button
}

function New-RoundField {
    param($Box, [int]$Radius = 12)
    $hostPanel = New-Object RoundField
    $hostPanel.Radius = $Radius
    $hostPanel.Dock = "Fill"
    $hostPanel.BackColor = $panelBg
    $hostPanel.Padding = New-Object System.Windows.Forms.Padding(14, 6, 14, 6)
    $Box.BorderStyle = "None"
    $Box.Dock = "Fill"
    $Box.Margin = New-Object System.Windows.Forms.Padding(0)
    $Box.BackColor = $panelBg
    $Box.ForeColor = [System.Drawing.Color]::White
    $hostPanel.Controls.Add($Box)
    return $hostPanel
}

function New-EmptyLabel {
    param([string]$Text)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Dock = "None"
    $label.TextAlign = "MiddleCenter"
    $label.ForeColor = [System.Drawing.Color]::FromArgb(176, 176, 176)
    $label.BackColor = $panelBg
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $label.Visible = $false
    return $label
}

function Sync-Overlay($HostPanel, $Label) {
    $Label.SetBounds(0, 0, $HostPanel.ClientSize.Width, $HostPanel.ClientSize.Height)
}

function Set-SoftList($Box) {
    $Box.DrawMode = "OwnerDrawFixed"
    $Box.ItemHeight = 30
    $Box.BorderStyle = "None"
    $Box.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $on = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $fill = $panelBg
        if ($on) { $fill = $accent }
        $brush = New-Object System.Drawing.SolidBrush $fill
        $e.Graphics.FillRectangle($brush, $e.Bounds)
        $brush.Dispose()
        $rect = New-Object System.Drawing.Rectangle ($e.Bounds.X + 12), $e.Bounds.Y, [Math]::Max(1, $e.Bounds.Width - 18), $e.Bounds.Height
        $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Items[$e.Index], $sender.Font, $rect, [System.Drawing.Color]::White, $flags)
    }.GetNewClosure())
}

function New-ListShell($Box, [string]$EmptyText) {
    Set-SoftList $Box
    $label = New-EmptyLabel $EmptyText
    $hostPanel = New-Object System.Windows.Forms.Panel
    $hostPanel.Dock = "Fill"
    $hostPanel.BackColor = $panelBg
    $Box.Dock = "Fill"
    $hostPanel.Controls.Add($Box)
    $hostPanel.Controls.Add($label)
    $hostPanel.Add_Resize({ Sync-Overlay $hostPanel $label }.GetNewClosure())
    $shell = New-Object RoundField
    $shell.Dock = "Fill"
    $shell.Radius = 14
    $shell.Padding = New-Object System.Windows.Forms.Padding(1)
    $shell.BackColor = $panelBg
    $shell.Controls.Add($hostPanel)
    return @{ Shell = $shell; Empty = $label }
}

$header = New-Object System.Windows.Forms.Label
$header.Text = "MODS"
$header.Dock = "Top"
$header.Height = 52
$header.TextAlign = "BottomCenter"
$header.ForeColor = [System.Drawing.Color]::White
$header.BackColor = [System.Drawing.Color]::Transparent
$header.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$header.Dock = "Fill"

$pathRow = New-Object GlassPanel
$pathRow.Dock = "Top"
$pathRow.Height = 48
$pathRow.BackColor = $bg
$pathRow.Padding = New-Object System.Windows.Forms.Padding(28, 10, 28, 6)
$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Dock = "Fill"
$pathBox.BorderStyle = "FixedSingle"
$pathBox.BackColor = $panelBg
$pathBox.ForeColor = [System.Drawing.Color]::White
$browseGame = New-FlatButton "Folder" 88
$browseGame.Dock = "Right"
$pathField = New-RoundField $pathBox
$pathRow.Controls.Add($pathField)
$pathRow.Controls.Add($browseGame)
$pathRow.Dock = "Fill"

$accent = [System.Drawing.Color]::FromArgb(232, 93, 4)
$backBtn = New-FlatButton "Back" 72
$recBtn = New-FlatButton "Recommended" 132
$browseBtn = New-FlatButton "Browse" 88
$installedPageBtn = New-FlatButton "Installed" 100
$profilesPageBtn = New-FlatButton "Profiles" 96
$backBtn.Height = 32
$recBtn.Height = 32
$browseBtn.Height = 32
$installedPageBtn.Height = 32
$profilesPageBtn.Height = 32
$backBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$recBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$browseBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$installedPageBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$profilesPageBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
$catRow = $null
$browseRow = $null
$profilesTab = $null
$profileList = $null
$store = $null
$storeLayout = $null
$catHeader = $null
$filter = $null

function Set-PageButton($button, [bool]$On) {
    $face = $(if ($On) { $accent } else { $panelBg })
    $button.BackColor = $face
    $button.FlatAppearance.BorderColor = $(if ($On) { $accent } else { $edge })
    $button.FlatAppearance.MouseOverBackColor = $face
    $button.FlatAppearance.MouseDownBackColor = $face
}

function Show-ModsPage([string]$Name) {
    $Script:ModsPage = $Name
    $rec = $Name -eq "Recommended"
    $browse = $Name -eq "Browse"
    $storeTab.Visible = $rec -or $browse
    $installedTab.Visible = $Name -eq "Installed"
    if ($null -ne $profilesTab) { $profilesTab.Visible = $Name -eq "Profiles" }
    Set-PageButton $recBtn $rec
    Set-PageButton $browseBtn $browse
    Set-PageButton $installedPageBtn ($Name -eq "Installed")
    Set-PageButton $profilesPageBtn ($Name -eq "Profiles")
    if ($null -ne $catRow) {
        $catRow.Visible = $rec
        $catRow.Enabled = $rec
        $storeLayout.RowStyles[0].Height = $(if ($rec -or $browse) { 36 } else { 0 })
        if ($rec) { $catRow.BringToFront() }
        foreach ($other in @($catRow.Controls)) {
            $tag = [string]$other.Tag
            if ($tag.StartsWith("kind|")) {
                Set-PageButton $other ($rec -and ($Script:PackageKind -eq $tag.Substring(5)))
            }
            else {
                Set-PageButton $other ($rec -and ($Script:PackageKind -eq "mods") -and ($tag -eq $Script:ModCategory))
            }
        }
    }
    if ($null -ne $browseRow) {
        $browseRow.Visible = $browse
        $browseRow.Enabled = $browse
        if ($browse) { $browseRow.BringToFront() }
        foreach ($other in @($browseRow.Controls)) {
            $parts = ([string]$other.Tag).Split("|")
            $on = $false
            if ($parts[0] -eq "section") { $on = $Script:BrowseSection -eq $parts[1] }
            elseif ($parts[0] -eq "order") { $on = $Script:BrowseOrder -eq $parts[1] }
            Set-PageButton $other ($browse -and $on)
        }
    }
    if ($null -ne $store -and $store.Columns.Count -gt 1) {
        $store.Columns[1].Width = $(if ($rec) { 150 } else { 0 })
    }
    if ($null -ne $catHeader) { $catHeader.Visible = $rec }
    if ($null -ne $filter -and $filter.IsHandleCreated) {
        $cue = "Search recommended"
        if ($rec -and $Script:PackageKind -eq "modpacks") { $cue = "Search modpacks" }
        if ($browse) {
            $cue = "Search mods"
            if ($Script:BrowseSection -eq "modpacks") { $cue = "Search modpacks" }
        }
        [void][UiTheme]::SendMessage($filter.Handle, 0x1501, [IntPtr]1, $cue)
    }
    if ($null -eq $store) { return }
    try {
        if ($rec) { Show-Recommended $Script:ModCategory $filter.Text }
        elseif ($browse) { Show-ModSearch $filter.Text }
        elseif ($Name -eq "Profiles") { Refresh-Profiles }
    }
    catch { Write-LogBox $_.Exception.Message }
}

$backBtn.Add_Click({ Return-ToGameSelect })
$recBtn.Add_Click({ Show-ModsPage "Recommended" })
$browseBtn.Add_Click({ Show-ModsPage "Browse" })
$installedPageBtn.Add_Click({ Show-ModsPage "Installed" })
$profilesPageBtn.Add_Click({ Show-ModsPage "Profiles" })

$switch = New-Object GlassFlow
$switch.Dock = "Fill"
$switch.BackColor = $bg
$switch.WrapContents = $false
$switch.Padding = New-Object System.Windows.Forms.Padding(16, 6, 0, 0)
$switch.Controls.Add($backBtn)
$switch.Controls.Add($recBtn)
$switch.Controls.Add($browseBtn)
$switch.Controls.Add($installedPageBtn)
$switch.Controls.Add($profilesPageBtn)

$storeTab = New-Object GlassPanel
$storeTab.Dock = "Fill"
$storeTab.BackColor = $bg
$storeTab.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
$installedTab = New-Object GlassPanel
$installedTab.Dock = "Fill"
$installedTab.BackColor = $bg
$installedTab.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
$pages = New-Object GlassPanel
$pages.Dock = "Fill"
$pages.BackColor = $bg
$pages.Controls.Add($installedTab)
$pages.Controls.Add($storeTab)

$pageHost = New-Object GlassTable
$pageHost.Dock = "Fill"
$pageHost.ColumnCount = 1
$pageHost.RowCount = 2
$pageHost.BackColor = $bg
[void]$pageHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$pageHost.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
[void]$pageHost.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$pageHost.Controls.Add($switch, 0, 0)
$pageHost.Controls.Add($pages, 0, 1)

$filter = New-Object System.Windows.Forms.TextBox
$filter.Dock = "Top"
$filter.Height = 28
$filter.BorderStyle = "FixedSingle"
$filter.BackColor = $panelBg
$filter.ForeColor = [System.Drawing.Color]::White

$store = New-Object System.Windows.Forms.ListView
$store.Dock = "Fill"
$store.View = "Details"
$store.FullRowSelect = $true
$store.CheckBoxes = $true
$store.BorderStyle = "None"
$store.BackColor = $panelBg
$store.ForeColor = [System.Drawing.Color]::White
$store.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$store.HideSelection = $false
$store.OwnerDraw = $true
$rowPad = New-Object System.Windows.Forms.ImageList
$rowPad.ImageSize = New-Object System.Drawing.Size(1, 28)
$store.SmallImageList = $rowPad
[void]$store.Columns.Add("Package", 530)
[void]$store.Columns.Add("Category", 150)
[void]$store.Columns.Add("Version", 110)
[void]$store.Columns.Add("Downloads", 120)
$store.HeaderStyle = "None"
$colHead = New-Object System.Windows.Forms.Panel
$colHead.Dock = "Fill"
$colHead.BackColor = [System.Drawing.Color]::FromArgb(42, 42, 42)
$colHead.Padding = New-Object System.Windows.Forms.Padding(28, 0, 0, 0)
foreach ($pair in @(
    @{ Text = "Downloads"; Width = 120 },
    @{ Text = "Version"; Width = 110 },
    @{ Text = "Category"; Width = 150 },
    @{ Text = "Package"; Width = 530 }
)) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $pair.Text
    $label.Width = $pair.Width
    $label.Dock = "Left"
    $label.TextAlign = "MiddleLeft"
    $label.ForeColor = [System.Drawing.Color]::White
    $label.BackColor = [System.Drawing.Color]::FromArgb(42, 42, 42)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    if ($pair.Text -eq "Category") { $catHeader = $label }
    $colHead.Controls.Add($label)
}
$store.Add_DrawColumnHeader({ param($sender, $e) $e.DrawDefault = $false })
$store.Add_DrawItem({ })
$store.Add_DrawSubItem({
    param($sender, $e)
    if ($e.Bounds.Width -le 0 -or $e.Bounds.Height -le 0) { return }
    $hot = ($e.Item.Index -eq $Script:StoreHover) -and (-not $e.Item.Selected)
    $fill = $panelBg
    if ($e.Item.Selected) { $fill = $accent }
    elseif ($hot) { $fill = [System.Drawing.Color]::FromArgb(78, 78, 78) }
    $brush = New-Object System.Drawing.SolidBrush $fill
    $e.Graphics.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()
    $left = 8
    if ($e.ColumnIndex -eq 0 -and $sender.CheckBoxes) {
        $box = New-Object System.Drawing.Rectangle ($e.Bounds.X + 6), ($e.Bounds.Y + [Math]::Max(0, ($e.Bounds.Height - 16) / 2)), 16, 16
        if ([System.Windows.Forms.Application]::RenderWithVisualStyles) {
            $mark = [System.Windows.Forms.VisualStyles.VisualStyleElement]::Button.CheckBox.UncheckedNormal
            if ($e.Item.Checked) { $mark = [System.Windows.Forms.VisualStyles.VisualStyleElement]::Button.CheckBox.CheckedNormal }
            $renderer = New-Object System.Windows.Forms.VisualStyles.VisualStyleRenderer $mark
            $renderer.DrawBackground($e.Graphics, $box)
        }
        else {
            $state = [System.Windows.Forms.ButtonState]::Normal
            if ($e.Item.Checked) { $state = [System.Windows.Forms.ButtonState]::Checked }
            [System.Windows.Forms.ControlPaint]::DrawCheckBox($e.Graphics, $box, $state)
        }
        $left = 28
    }
    $textRect = New-Object System.Drawing.Rectangle ($e.Bounds.X + $left), $e.Bounds.Y, [Math]::Max(1, $e.Bounds.Width - $left - 6), $e.Bounds.Height
    $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.SubItem.Text, $sender.Font, $textRect, [System.Drawing.Color]::White, $flags)
})

$catRow = New-Object GlassFlow
$catRow.Dock = "Fill"
$catRow.BackColor = $bg
$catRow.WrapContents = $false
$catRow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
foreach ($kindName in @("Mods", "Modpacks")) {
    $kindWidth = 72
    if ($kindName -eq "Modpacks") { $kindWidth = 108 }
    $kindBtn = New-FlatButton $kindName $kindWidth
    $kindBtn.Height = 28
    $kindBtn.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    $kindBtn.Tag = "kind|" + $kindName.ToLower()
    $kindBtn.Add_Click({
        $Script:PackageKind = ([string]$this.Tag).Substring(5)
        $Script:BrowseSection = $Script:PackageKind
        if ($Script:ModsPage -eq "Browse") { Show-ModsPage "Browse" }
        else { Show-ModsPage "Recommended" }
    })
    [void]$catRow.Controls.Add($kindBtn)
}
foreach ($catName in @("All", "Skate 2", "Skate 3", "Skater XL", "Other", "Maps", "Audio")) {
    $width = 72
    if ($catName -eq "Skater XL") { $width = 100 }
    elseif ($catName -eq "Skate 2" -or $catName -eq "Skate 3") { $width = 84 }
    elseif ($catName -eq "All") { $width = 56 }
    $catBtn = New-FlatButton $catName $width
    $catBtn.Height = 28
    $catBtn.Margin = New-Object System.Windows.Forms.Padding($(if ($catName -eq "All") { 14 } else { 0 }), 2, 6, 0)
    $catBtn.Tag = $catName
    $catBtn.Add_Click({
        $Script:PackageKind = "mods"
        $Script:BrowseSection = "mods"
        $Script:ModCategory = [string]$this.Tag
        Show-ModsPage "Recommended"
    })
    [void]$catRow.Controls.Add($catBtn)
}

$browseRow = New-Object GlassFlow
$browseRow.Dock = "Fill"
$browseRow.BackColor = $bg
$browseRow.WrapContents = $false
$browseRow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
$browseRow.Visible = $false
foreach ($spec in @(
    @{ Text = "Mods"; Kind = "section"; Value = "mods"; Width = 72; Gap = 0 }
    @{ Text = "Modpacks"; Kind = "section"; Value = "modpacks"; Width = 108; Gap = 0 }
    @{ Text = "Last updated"; Kind = "order"; Value = "last-updated"; Width = 124; Gap = 16 }
    @{ Text = "Newest"; Kind = "order"; Value = "newest"; Width = 84; Gap = 0 }
    @{ Text = "Most downloaded"; Kind = "order"; Value = "most-downloaded"; Width = 150; Gap = 0 }
    @{ Text = "Top rated"; Kind = "order"; Value = "top-rated"; Width = 96; Gap = 0 }
)) {
    $browseChip = New-FlatButton $spec.Text $spec.Width
    $browseChip.Height = 28
    $browseChip.Margin = New-Object System.Windows.Forms.Padding($spec.Gap, 2, 6, 0)
    $browseChip.Tag = "{0}|{1}" -f $spec.Kind, $spec.Value
    $browseChip.Add_Click({
        $parts = ([string]$this.Tag).Split("|")
        if ($parts[0] -eq "section") {
            $Script:BrowseSection = $parts[1]
            $Script:PackageKind = $parts[1]
        }
        else { $Script:BrowseOrder = $parts[1] }
        Show-ModsPage "Browse"
    })
    [void]$browseRow.Controls.Add($browseChip)
}
$chipHost = New-Object GlassPanel
$chipHost.Dock = "Fill"
$chipHost.BackColor = $bg
$chipHost.Controls.Add($browseRow)
$chipHost.Controls.Add($catRow)

$storeButtons = New-Object GlassFlow
$storeButtons.Dock = "Bottom"
$storeButtons.Height = 40
$countLabel = New-Object System.Windows.Forms.Label
$countLabel.AutoSize = $true
$countLabel.Text = "0 packages"
$countLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
$countLabel.BackColor = [System.Drawing.Color]::Transparent
$countLabel.Padding = New-Object System.Windows.Forms.Padding(0, 8, 12, 0)
$addBtn = New-FlatButton "Pull checked" 120
$openBtn = New-FlatButton "Open page" 110
$localBtn = New-FlatButton "Add zip or folder" 140
$autoMods = New-Object System.Windows.Forms.CheckBox
$autoMods.Text = "Auto-update"
$autoMods.AutoSize = $true
$autoMods.ForeColor = [System.Drawing.Color]::White
$autoMods.BackColor = [System.Drawing.Color]::Transparent
$autoMods.Margin = New-Object System.Windows.Forms.Padding(12, 8, 0, 0)
$autoMods.Checked = [bool](Get-ReSkateSettings).mods
$storeButtons.Controls.Add($countLabel)
$storeButtons.Controls.Add($addBtn)
$storeButtons.Controls.Add($openBtn)
$storeButtons.Controls.Add($localBtn)
$storeButtons.Controls.Add($autoMods)
$storeButtons.Dock = "Fill"
$filter.Dock = "Fill"
$filterField = New-RoundField $filter

$paste = New-Object System.Windows.Forms.TextBox
$paste.Dock = "Fill"
$paste.Height = 28
$paste.BorderStyle = "FixedSingle"
$paste.BackColor = $panelBg
$paste.ForeColor = [System.Drawing.Color]::White
$pasteField = New-RoundField $paste
$storeLayout = New-Object GlassTable
$storeLayout.Dock = "Fill"
$storeLayout.ColumnCount = 1
$storeLayout.RowCount = 6
$storeLayout.BackColor = $bg
[void]$storeLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
[void]$storeLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
$colHead.Dock = "Top"
$colHead.Height = 30
$emptyNote = New-EmptyLabel "No results"
$resultHost = New-Object System.Windows.Forms.Panel
$resultHost.Dock = "Fill"
$resultHost.BackColor = $panelBg
$store.Dock = "Fill"
$resultHost.Controls.Add($store)
$resultHost.Controls.Add($emptyNote)
$resultHost.Add_Resize({ Sync-Overlay $resultHost $emptyNote })
$listShell = New-Object RoundField
$listShell.Dock = "Fill"
$listShell.Radius = 14
$listShell.Padding = New-Object System.Windows.Forms.Padding(1)
$listShell.BackColor = $panelBg
$listShell.Controls.Add($resultHost)
$listShell.Controls.Add($colHead)
$storeLayout.Controls.Add($chipHost, 0, 0)
$storeLayout.Controls.Add($filterField, 0, 1)
$storeLayout.Controls.Add($listShell, 0, 2)
$storeLayout.SetRowSpan($listShell, 2)
$storeLayout.Controls.Add($storeButtons, 0, 4)
$storeLayout.Controls.Add($pasteField, 0, 5)
$storeTab.Controls.Add($storeLayout)
Show-ModsPage "Recommended"

$installed = New-Object System.Windows.Forms.ListBox
$installed.Dock = "Fill"
$installed.BorderStyle = "None"
$installed.BackColor = $panelBg
$installed.ForeColor = [System.Drawing.Color]::White
$installed.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$installedPack = New-ListShell $installed "No mods installed"
$installedEmpty = $installedPack.Empty
$removeBtn = New-FlatButton "Remove selected" 150
$removeBtn.Dock = "Fill"
$removeBtn.Height = 34
$installed.Dock = "Fill"
$installedLayout = New-Object GlassTable
$installedLayout.Dock = "Fill"
$installedLayout.ColumnCount = 1
$installedLayout.RowCount = 2
$installedLayout.BackColor = $bg
[void]$installedLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$installedLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$installedLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
$installedLayout.Controls.Add($installedPack.Shell, 0, 0)
$installedLayout.Controls.Add($removeBtn, 0, 1)
$installedTab.Controls.Add($installedLayout)

$profilesTab = New-Object GlassPanel
$profilesTab.Dock = "Fill"
$profilesTab.BackColor = $bg
$profilesTab.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
$profilesTab.Visible = $false
$profileName = New-Object System.Windows.Forms.TextBox
$profileName.Dock = "Fill"
$profileName.BorderStyle = "FixedSingle"
$profileName.BackColor = $panelBg
$profileName.ForeColor = [System.Drawing.Color]::White
$saveProfileBtn = New-FlatButton "Save" 88
$saveProfileBtn.Dock = "Right"
$saveProfileBtn.Height = 28
$nameRow = New-Object GlassPanel
$nameRow.Dock = "Fill"
$nameRow.BackColor = $bg
$nameField = New-RoundField $profileName
$nameRow.Controls.Add($nameField)
$nameRow.Controls.Add($saveProfileBtn)
$profileList = New-Object System.Windows.Forms.ListBox
$profileList.Dock = "Fill"
$profileList.BorderStyle = "None"
$profileList.BackColor = $panelBg
$profileList.ForeColor = [System.Drawing.Color]::White
$profileList.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$profilePack = New-ListShell $profileList "No profiles saved"
$profileEmpty = $profilePack.Empty
$loadProfileBtn = New-FlatButton "Load" 110
$loadProfileBtn.Height = 32
$loadProfileBtn.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$deleteProfileBtn = New-FlatButton "Delete" 110
$deleteProfileBtn.Height = 32
$deleteProfileBtn.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$profileButtons = New-Object GlassFlow
$profileButtons.Dock = "Fill"
$profileButtons.BackColor = $bg
$profileButtons.WrapContents = $false
$profileButtons.Controls.Add($loadProfileBtn)
$profileButtons.Controls.Add($deleteProfileBtn)
$profilesLayout = New-Object GlassTable
$profilesLayout.Dock = "Fill"
$profilesLayout.ColumnCount = 1
$profilesLayout.RowCount = 3
$profilesLayout.BackColor = $bg
[void]$profilesLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$profilesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$profilesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$profilesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
$profilesLayout.Controls.Add($nameRow, 0, 0)
$profilesLayout.Controls.Add($profilePack.Shell, 0, 1)
$profilesLayout.Controls.Add($profileButtons, 0, 2)
$profilesTab.Controls.Add($profilesLayout)
$pages.Controls.Add($profilesTab)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = "Bottom"
$logBox.Height = 140
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BorderStyle = "None"
$logBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Dock = "Fill"
$logHost = New-RoundField $logBox 14
$logHost.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$logHost.Padding = New-Object System.Windows.Forms.Padding(12, 8, 6, 8)
$logBox.BackColor = $logHost.BackColor
$shell = New-Object GlassTable
$shell.Dock = "Fill"
$shell.ColumnCount = 1
$shell.RowCount = 4
$shell.BackColor = $bg
[void]$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$shell.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
[void]$shell.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
[void]$shell.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$shell.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
$shell.Controls.Add($header, 0, 0)
$shell.Controls.Add($pathRow, 0, 1)
$shell.Controls.Add($pageHost, 0, 2)
$logFrame = New-Object GlassPanel
$logFrame.Dock = "Fill"
$logFrame.Padding = New-Object System.Windows.Forms.Padding(16, 0, 16, 12)
$dlHost = New-Object System.Windows.Forms.Panel
$dlHost.Dock = "Top"
$dlHost.Height = 28
$dlHost.Visible = $false
$dlHost.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$dlHost.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$dlPct = New-Object System.Windows.Forms.Label
$dlPct.Dock = "Right"
$dlPct.Width = 52
$dlPct.TextAlign = "MiddleRight"
$dlPct.ForeColor = [System.Drawing.Color]::White
$dlPct.BackColor = $dlHost.BackColor
$dlPct.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$dlName = New-Object System.Windows.Forms.Label
$dlName.Dock = "Left"
$dlName.Width = 280
$dlName.AutoEllipsis = $true
$dlName.TextAlign = "MiddleLeft"
$dlName.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$dlName.BackColor = $dlHost.BackColor
$dlName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$dlBar = New-Object System.Windows.Forms.ProgressBar
$dlBar.Dock = "Fill"
$dlBar.Style = "Continuous"
$dlBar.Minimum = 0
$dlBar.Maximum = 100
$dlHost.Controls.Add($dlBar)
$dlHost.Controls.Add($dlName)
$dlHost.Controls.Add($dlPct)
$logFrame.Controls.Add($logHost)
$logFrame.Controls.Add($dlHost)
$shell.Controls.Add($logFrame, 0, 3)
$form.Controls.Add($shell)

$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 400
$searchTimer.Add_Tick({
    $searchTimer.Stop()
    try {
        if ($Script:ModsPage -eq "Recommended") { Show-Recommended $Script:ModCategory $filter.Text }
        elseif ($Script:ModsPage -eq "Browse") { Show-ModSearch $filter.Text }
    }
    catch { Write-LogBox $_.Exception.Message }
})
$filter.Add_TextChanged({
    $searchTimer.Stop()
    $searchTimer.Start()
})

$Script:IconCache = @{}
$Script:IconStreams = @{}
$Script:HoverKey = ""
$Script:ThumbPkg = $null
$Script:ThumbPoint = [System.Drawing.Point]::Empty
$iconForm = New-Object System.Windows.Forms.Form
$iconForm.FormBorderStyle = "None"
$iconForm.ShowInTaskbar = $false
$iconForm.StartPosition = "Manual"
$iconForm.BackColor = [System.Drawing.Color]::FromArgb(92, 92, 92)
$iconForm.ClientSize = New-Object System.Drawing.Size(136, 136)
$iconForm.TopMost = $true
$iconPic = New-Object System.Windows.Forms.PictureBox
$iconPic.Location = New-Object System.Drawing.Point(4, 4)
$iconPic.Size = New-Object System.Drawing.Size(128, 128)
$iconPic.SizeMode = "Zoom"
$iconPic.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$iconForm.Controls.Add($iconPic)
$iconForm.Add_HandleCreated({
    if ($iconForm.Width -gt 8) { $iconForm.Region = [UiShape]::Round($iconForm.Width, $iconForm.Height, 16) }
})

function Get-ModThumbUrl($Package) {
    if ($null -eq $Package) { return "" }
    $version = [string]$Package.Version
    if (-not $version) { return "" }
    $file = [Uri]::EscapeDataString(("{0}-{1}-{2}.png" -f $Package.Owner, $Package.Name, $version))
    return "https://old.thunderstore.io/thumbnail-serve/repository/icons/$file/?width=128&height=128"
}

function Hide-ModThumb {
    $Script:HoverKey = ""
    if ($iconForm.Visible) { $iconForm.Hide() }
}

function Move-ModThumb([System.Drawing.Point]$ScreenPoint) {
    $area = [System.Windows.Forms.Screen]::FromPoint($ScreenPoint).WorkingArea
    $x = $ScreenPoint.X + 20
    $y = $ScreenPoint.Y + 20
    if (($x + $iconForm.Width) -gt $area.Right) { $x = $ScreenPoint.X - $iconForm.Width - 12 }
    if (($y + $iconForm.Height) -gt $area.Bottom) { $y = $ScreenPoint.Y - $iconForm.Height - 12 }
    $iconForm.Location = New-Object System.Drawing.Point($x, $y)
}

function Show-ModThumb($Package, [System.Drawing.Point]$ScreenPoint) {
    $url = Get-ModThumbUrl $Package
    if (-not $url) { Hide-ModThumb; return }
    if ($Script:HoverKey -eq $url) {
        Move-ModThumb $ScreenPoint
        if (-not $iconForm.Visible) { return }
        return
    }
    $Script:HoverKey = $url
    if (-not $Script:IconCache.ContainsKey($url)) {
        $client = New-Object System.Net.WebClient
        $client.Headers["User-Agent"] = "Mozilla/5.0"
        try {
            $bytes = $client.DownloadData($url)
            $stream = New-Object System.IO.MemoryStream(,$bytes)
            $Script:IconStreams[$url] = $stream
            $Script:IconCache[$url] = [System.Drawing.Image]::FromStream($stream)
        }
        catch {
            $Script:IconCache[$url] = $null
        }
        finally { $client.Dispose() }
    }
    $image = $Script:IconCache[$url]
    if ($null -eq $image) { Hide-ModThumb; return }
    $iconPic.Image = $image
    Move-ModThumb $ScreenPoint
    if (-not $iconForm.Visible) {
        $iconForm.Show($form)
        [void][WinFocus]::ShowWindow($iconForm.Handle, 8)
    }
}

$thumbTimer = New-Object System.Windows.Forms.Timer
$thumbTimer.Interval = 160
$thumbTimer.Add_Tick({
    $thumbTimer.Stop()
    try { Show-ModThumb $Script:ThumbPkg $Script:ThumbPoint }
    catch { Hide-ModThumb }
})
$store.Add_MouseMove({
    param($sender, $e)
    $hit = $store.HitTest($e.Location)
    $pkg = $null
    $hover = -1
    if ($null -ne $hit.Item) { $pkg = $hit.Item.Tag; $hover = $hit.Item.Index }
    if ($hover -ne $Script:StoreHover) {
        $prev = $Script:StoreHover
        $Script:StoreHover = $hover
        if ($prev -ge 0 -and $prev -lt $store.Items.Count) { $store.RedrawItems($prev, $prev, $true) }
        if ($hover -ge 0) { $store.RedrawItems($hover, $hover, $true) }
    }
    $Script:ThumbPkg = $pkg
    $Script:ThumbPoint = $store.PointToScreen($e.Location)
    $thumbTimer.Stop()
    $thumbTimer.Start()
})
$store.Add_MouseLeave({
    $thumbTimer.Stop()
    Hide-ModThumb
    if ($Script:StoreHover -ge 0 -and $Script:StoreHover -lt $store.Items.Count) {
        $prev = $Script:StoreHover
        $Script:StoreHover = -1
        $store.RedrawItems($prev, $prev, $true)
    }
})
$installed.Add_MouseMove({
    param($sender, $e)
    $pkg = $null
    $index = $installed.IndexFromPoint($e.Location)
    if ($index -ge 0) {
        $name = [string]$installed.Items[$index]
        if ($Script:ByFull.ContainsKey($name)) { $pkg = $Script:ByFull[$name] }
    }
    $Script:ThumbPkg = $pkg
    $Script:ThumbPoint = $installed.PointToScreen($e.Location)
    $thumbTimer.Stop()
    $thumbTimer.Start()
})
$installed.Add_MouseLeave({ $thumbTimer.Stop(); Hide-ModThumb })
$form.Add_Deactivate({ Hide-ModThumb })

$autoMods.Add_CheckedChanged({
    $saved = Get-ReSkateSettings
    $saved.mods = $autoMods.Checked
    Save-ReSkateSettings $saved
    if ($autoMods.Checked) {
        try { Update-InstalledMods }
        catch { Write-LogBox $_.Exception.Message }
    }
})

$browseGame.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Folder that contains Skate.exe"
    if ($dialog.ShowDialog() -eq "OK") {
        try { Set-SkateRoot $dialog.SelectedPath }
        catch { Write-LogBox $_.Exception.Message }
    }
})

$openBtn.Add_Click({
    $target = $null
    if ($store.SelectedItems.Count -gt 0) { $target = $store.SelectedItems[0].Tag.Page }
    elseif ($Script:ModsPage -eq "Browse") { $target = Get-ModsSearchUrl $filter.Text }
    if ($target) { Start-Process $target }
})

$addBtn.Add_Click({
    try {
        $picked = @($store.CheckedItems)
        if ($paste.Text.Trim()) { $picked += $paste.Text.Trim() }
        if ($picked.Count -eq 0 -and $store.SelectedItems.Count -gt 0) {
            $picked = @($store.SelectedItems)
        }
        foreach ($entry in $picked) {
            $pkg = $null
            if ($entry -is [System.Windows.Forms.ListViewItem]) { $pkg = $entry.Tag }
            else {
                $text = [string]$entry
                if ($text -match 'thunderstore\.io/.+/p/([^/]+)/([^/]+)') {
                    $key = "{0}-{1}" -f $Matches[1], $Matches[2]
                }
                elseif ($text -match '^(?<owner>[^-]+)-(?<name>.+)-(?<ver>\d+\.\d+\.\d+.*)$') {
                    $key = "{0}-{1}" -f $Matches.owner, $Matches.name
                }
                else { $key = $text }
                if ($Script:ByFull.ContainsKey($key)) { $pkg = $Script:ByFull[$key] }
                else { throw "Not in the ReSkate catalog: $text" }
            }
            Install-StorePackage $pkg
        }
        $paste.Clear()
        Refresh-Installed
        Show-ModsPage "Installed"
    }
    catch { Write-LogBox $_.Exception.Message }
})

$localBtn.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Mod archives and files|*.zip;*.dll;*.lua;*.ogg;*.mp3;*.json|All files|*.*"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -ne "OK") { return }
    try {
        foreach ($file in $dialog.FileNames) { Install-LocalTree -Path $file }
        Refresh-Installed
        Show-ModsPage "Installed"
    }
    catch { Write-LogBox $_.Exception.Message }
})

$removeBtn.Add_Click({
    if ($installed.SelectedItem -eq $null) { return }
    $name = [string]$installed.SelectedItem
    $answer = [System.Windows.Forms.MessageBox]::Show("Remove Mods\$name ?", "ReSkate", "YesNo")
    if ($answer -ne "Yes") { return }
    Remove-Item -LiteralPath (Join-Path (Get-ModsRoot) $name) -Recurse -Force
    Write-LogBox "Removed $name"
    Refresh-Installed
})

$saveProfileBtn.Add_Click({
    try { Save-ModProfile $profileName.Text }
    catch { Write-LogBox $_.Exception.Message }
})
$loadProfileBtn.Add_Click({
    if ($null -eq $profileList.SelectedItem) {
        Write-LogBox "Select a profile."
        return
    }
    try { Install-ModProfile ([string]$profileList.SelectedItem) }
    catch { Write-LogBox $_.Exception.Message }
})
$deleteProfileBtn.Add_Click({
    if ($null -eq $profileList.SelectedItem) { return }
    $name = [string]$profileList.SelectedItem
    $answer = [System.Windows.Forms.MessageBox]::Show("Delete profile $name ?", "ReSkate", "YesNo")
    if ($answer -ne "Yes") { return }
    Remove-Item -LiteralPath (Join-Path (Get-ProfilesRoot) $name) -Recurse -Force
    if ($profileName.Text -eq $name) { $profileName.Clear() }
    Refresh-Profiles
    Write-LogBox "Deleted profile $name"
})
$profileList.Add_SelectedIndexChanged({
    if ($null -ne $profileList.SelectedItem) { $profileName.Text = [string]$profileList.SelectedItem }
})

$Script:ModsClaimed = $false
$Script:ModsPhase = 0.0
$Script:ModsHiding = $false
function Set-ModsBorder([double]$Blend) {
    $r = [int](232 + (40 - 232) * $Blend)
    $g = [int](93 + (190 - 93) * $Blend)
    $b = [int](4 + (70 - 4) * $Blend)
    $color = ($b -shl 16) -bor ($g -shl 8) -bor $r
    [UiTheme]::SetBorder($form.Handle, $color)
}
function Stop-ModsBorder {
    $Script:ModsClaimed = $true
    $borderTimer.Stop()
    Set-ModsBorder 0
}
$borderTimer = New-Object System.Windows.Forms.Timer
$borderTimer.Interval = 30
$borderTimer.Add_Tick({
    if ($Script:ModsClaimed) { $borderTimer.Stop(); return }
    $Script:ModsPhase += 0.045
    $blend = ([Math]::Sin($Script:ModsPhase) + 1) / 2
    Set-ModsBorder $blend
})
$clickWatch = New-Object ClickWatch
$clickWatch.Add_Pressed({ Stop-ModsBorder })
$form.Add_Deactivate({
    if ($Script:ModsHiding -or $form.WindowState -eq "Minimized") { return }
    foreach ($owned in @($form.OwnedForms)) {
        if ($owned.Visible) { return }
    }
    $front = [WinFocus]::GetForegroundWindow()
    if ([WinFocus]::GetWindow($front, 4) -eq $form.Handle) { return }
    $Script:ModsHiding = $true
    $form.WindowState = "Minimized"
    $Script:ModsHiding = $false
})
$form.Add_Shown({
    try {
        [UiTheme]::DarkCaption($form.Handle)
        $clickWatch.AssignHandle($form.Handle)
        $borderTimer.Start()
        foreach ($scroll in @($store, $installed, $profileList, $logBox, $filter, $paste, $pathBox, $profileName)) {
            [UiTheme]::DarkScroll($scroll.Handle)
        }
        [void][UiTheme]::SendMessage($filter.Handle, 0x1501, [IntPtr]1, "Search recommended")
        [void][UiTheme]::SendMessage($paste.Handle, 0x1501, [IntPtr]1, "Paste a Thunderstore link")
        [void][UiTheme]::SendMessage($profileName.Handle, 0x1501, [IntPtr]1, "Profile name")
        $found = @(Find-SkateRoots)
        if ($found.Count -ge 1) { Set-SkateRoot $found[0] }
        else { Write-LogBox "Skate.exe was not found. Set the folder that contains it." }
        Load-Catalog
        if ($autoMods.Checked) { Update-InstalledMods }
    }
    catch { Write-LogBox $_.Exception.Message }
})

[void]$form.ShowDialog()
