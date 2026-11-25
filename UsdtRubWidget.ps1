#Requires -Version 5.1
<#
  USDT/RUB — виджет курса с биржи Rapira для Windows 11.
  - обновление каждые 5 секунд (api.rapira.net/open/market/rates)
  - карточка на рабочем столе (перетаскивается мышью, двойной клик — обновить)
  - кнопка на панели задач (её можно закрепить) со стрелкой роста/падения
  - значок в трее с целой частью курса и подсказкой с полным курсом
  Правый клик по карточке или по значку в трее — меню.
#>

# ---------- настройки ----------
$RefreshSeconds = 5
$ApiUrl         = 'https://api.rapira.net/open/market/rates'
$Symbol         = 'USDT/RUB'
$AppId          = 'UsdtRubWidget.Rapira'
$AppName        = 'USDT RUB (Rapira)'
# --------------------------------

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- один экземпляр: повторный запуск просто показывает окно ----------
$mutex = New-Object System.Threading.Mutex($false, 'Local\UsdtRubWidget')
$showSignal = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\UsdtRubWidget.Show')
if (-not $mutex.WaitOne(0)) { [void]$showSignal.Set(); exit }

# ---------- Win32: AppUserModelID (для закрепления на панели задач) и ярлыки ----------
if (-not ('UrwShell' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class UrwShell {
    [DllImport("shell32.dll")]
    static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public static void SetAppId(string id) { SetCurrentProcessExplicitAppUserModelID(id); }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int cch, IntPtr fd, int flags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetHotkey(out short k);
        void SetHotkey(short k);
        void GetShowCmd(out int c);
        void SetShowCmd(int c);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch, out int i);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, int r);
        void Resolve(IntPtr hwnd, int flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        void GetCount(out uint c);
        void GetAt(uint i, out PropKey k);
        void GetValue(ref PropKey k, out PropVar v);
        void SetValue(ref PropKey k, ref PropVar v);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PropKey { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Sequential)]
    struct PropVar { public ushort vt; public ushort r1, r2, r3; public IntPtr p1; public IntPtr p2; }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class CShellLink { }

    public static void CreateShortcut(string lnk, string target, string args, string workDir,
                                      string icon, string appId, string desc) {
        IShellLinkW link = (IShellLinkW)new CShellLink();
        link.SetPath(target);
        link.SetArguments(args);
        link.SetWorkingDirectory(workDir);
        link.SetIconLocation(icon, 0);
        link.SetDescription(desc);

        IPropertyStore store = (IPropertyStore)link;
        PropKey key = new PropKey();
        key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); // PKEY_AppUserModel_ID
        key.pid = 5;
        PropVar val = new PropVar();
        val.vt = 31; // VT_LPWSTR
        val.p1 = Marshal.StringToCoTaskMemUni(appId);
        try {
            store.SetValue(ref key, ref val);
            store.Commit();
        } finally {
            Marshal.FreeCoTaskMem(val.p1);
        }
        ((IPersistFile)link).Save(lnk, true);
    }
}
'@
}
[UrwShell]::SetAppId($AppId)

# ---------- пути и настройки ----------
$DataDir    = Join-Path $env:APPDATA 'UsdtRubWidget'
$ConfigFile = Join-Path $DataDir 'config.json'
$IconFile   = Join-Path $DataDir 'icon.ico'
$Launcher   = Join-Path $PSScriptRoot 'Start-Widget.vbs'
$WScript    = Join-Path $env:WINDIR 'System32\wscript.exe'
$StartMenuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"
$StartupLnk   = Join-Path ([Environment]::GetFolderPath('Startup'))  "$AppName.lnk"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

$cfg = [pscustomobject]@{ Left = $null; Top = $null; Topmost = $true }
if (Test-Path $ConfigFile) {
    try {
        $saved = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        foreach ($p in 'Left', 'Top', 'Topmost') { if ($null -ne $saved.$p) { $cfg.$p = $saved.$p } }
    } catch {}
}

# ---------- рисование значков ----------
function New-Png([int]$size, [scriptblock]$draw) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    & $draw $g $size
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

$TetherGreen = [System.Drawing.Color]::FromArgb(255, 38, 161, 123)
$UpColor     = [System.Drawing.Color]::FromArgb(255, 46, 160, 67)
$DownColor   = [System.Drawing.Color]::FromArgb(255, 218, 54, 51)
$GrayColor   = [System.Drawing.Color]::FromArgb(255, 110, 110, 110)

$AppPng = New-Png 256 {
    param($g, $s)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $TetherGreen), 0, 0, $s - 1, $s - 1)
    $font = New-Object System.Drawing.Font('Segoe UI', [single]($s * 0.58), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString([string][char]0x20AE, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, ($s * 0.03), $s, $s), $sf)
}

function New-ArrowPng([System.Drawing.Color]$color, [bool]$up) {
    New-Png 32 {
        param($g, $s)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 0, 0, 31, 31)
        if ($up) { $pts = @((New-Object System.Drawing.PointF 16, 7), (New-Object System.Drawing.PointF 26, 22), (New-Object System.Drawing.PointF 6, 22)) }
        else     { $pts = @((New-Object System.Drawing.PointF 16, 25), (New-Object System.Drawing.PointF 26, 10), (New-Object System.Drawing.PointF 6, 10)) }
        $g.FillPolygon([System.Drawing.Brushes]::White, [System.Drawing.PointF[]]$pts)
    }
}

function Save-Ico([byte[]]$png, [string]$path) {
    $fs = [System.IO.File]::Create($path)
    $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)          # ICONDIR
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0) # 256x256
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$png.Length); $w.Write([uint32]22)
    $w.Write($png)
    $w.Close()
}

function ConvertTo-ImageSource([byte[]]$bytes) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.StreamSource = New-Object System.IO.MemoryStream (, $bytes)
    $bi.CacheOption = 'OnLoad'
    $bi.EndInit()
    $bi.Freeze()
    $bi
}

try { Save-Ico $AppPng $IconFile } catch {}

# ярлык в меню «Пуск» с тем же AppUserModelID — именно он делает кнопку закрепляемой
function New-AppShortcut([string]$path) {
    [UrwShell]::CreateShortcut($path, $WScript, "`"$Launcher`"", $PSScriptRoot, $IconFile, $AppId, 'Курс USDT/RUB с Rapira')
}
try { New-AppShortcut $StartMenuLnk } catch {}
if (Test-Path $StartupLnk) { try { New-AppShortcut $StartupLnk } catch {} }  # обновить путь, если папку перенесли

# ---------- окно ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="USDT/RUB" Width="250" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="True" Topmost="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <Border x:Name="Card" Margin="10" CornerRadius="12" Padding="16,12,16,12"
          Background="#EE202020" BorderBrush="#33FFFFFF" BorderThickness="1" Cursor="SizeAll">
    <Border.Effect>
      <DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.45"/>
    </Border.Effect>
    <Border.ContextMenu>
      <ContextMenu>
        <MenuItem Name="MiRefresh"   Header="Обновить сейчас"/>
        <MenuItem Name="MiTopmost"   Header="Поверх всех окон" IsCheckable="True"/>
        <MenuItem Name="MiAutostart" Header="Запускать вместе с Windows" IsCheckable="True"/>
        <MenuItem Name="MiHide"      Header="Скрыть (останется в трее)"/>
        <MenuItem Name="MiSite"      Header="Открыть rapira.net"/>
        <Separator/>
        <MenuItem Name="MiExit"      Header="Закрыть виджет"/>
      </ContextMenu>
    </Border.ContextMenu>
    <StackPanel>
      <Grid>
        <TextBlock Text="USDT / RUB" Foreground="#B3FFFFFF" FontSize="12" FontWeight="SemiBold"/>
        <TextBlock x:Name="StatusText" Text="Rapira" HorizontalAlignment="Right" Foreground="#80FFFFFF" FontSize="11"/>
      </Grid>
      <TextBlock x:Name="RateText" Text="—" Foreground="White" FontSize="34" FontWeight="SemiBold"
                 FontFamily="Segoe UI Variable Display, Segoe UI" Margin="0,2,0,0"/>
      <TextBlock x:Name="ChangeText" Text="загрузка…" Foreground="#B3FFFFFF" FontSize="13"/>
      <TextBlock x:Name="BidAskText" Text="" Foreground="#80FFFFFF" FontSize="11" Margin="0,4,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@
$window     = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$Card       = $window.FindName('Card')
$RateText   = $window.FindName('RateText')
$ChangeText = $window.FindName('ChangeText')
$BidAskText = $window.FindName('BidAskText')
$StatusText = $window.FindName('StatusText')
$Menu = @{}
foreach ($it in $Card.ContextMenu.Items) { if ($it -is [System.Windows.Controls.MenuItem]) { $Menu[$it.Name] = $it } }

$window.Icon = ConvertTo-ImageSource $AppPng
$window.Topmost = [bool]$cfg.Topmost
$Menu.MiTopmost.IsChecked = $window.Topmost
$Menu.MiAutostart.IsChecked = Test-Path $StartupLnk

$taskbar = New-Object System.Windows.Shell.TaskbarItemInfo
$window.TaskbarItemInfo = $taskbar
$OverlayUp   = ConvertTo-ImageSource (New-ArrowPng $UpColor $true)
$OverlayDown = ConvertTo-ImageSource (New-ArrowPng $DownColor $false)

$bc = New-Object System.Windows.Media.BrushConverter
function Brush([string]$hex) { $b = $bc.ConvertFromString($hex); $b.Freeze(); $b }
$BrWhite = Brush '#FFFFFFFF'; $BrDim = Brush '#B3FFFFFF'
$BrUp = Brush '#FF6CCB5F';   $BrDown = Brush '#FFFF99A4'; $BrWarn = Brush '#FFFFB74D'
$StatusBrush = $StatusText.Foreground

# ---------- значок в трее ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Text = 'USDT/RUB — загрузка…'
$script:trayHandle = [IntPtr]::Zero
$script:trayKey = ''

function Set-TrayIcon([string]$text, [System.Drawing.Color]$bg) {
    $key = "$text|$($bg.ToArgb())"
    if ($key -eq $script:trayKey) { return }
    $script:trayKey = $key
    $s = [Math]::Max(16, [System.Windows.Forms.SystemInformation]::SmallIconSize.Width)
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $bg), 0, 0, $s, $s)
    if ($text.Length -le 2) { $k = 0.78 } else { $k = 0.56 }
    $font = New-Object System.Drawing.Font('Segoe UI', [single]($s * $k), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $g.DrawString($text, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF -4, 0, ($s + 8), ($s + 1)), $sf)
    $g.Dispose()
    $h = $bmp.GetHicon()
    $bmp.Dispose()
    $old = $script:trayHandle
    $tray.Icon = [System.Drawing.Icon]::FromHandle($h)
    $script:trayHandle = $h
    if ($old -ne [IntPtr]::Zero) { [void][UrwShell]::DestroyIcon($old) }
}

function Show-Widget { $window.Show(); if ($window.WindowState -eq 'Minimized') { $window.WindowState = 'Normal' }; [void]$window.Activate() }
function Hide-Widget { $window.Hide() }
$script:exiting = $false
function Exit-Widget {
    if ($script:exiting) { return }
    $script:exiting = $true
    Save-Config
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Application]::Current.Shutdown()
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$trayMenu.Items.Add('Показать / скрыть виджет', $null, { if ($window.IsVisible) { Hide-Widget } else { Show-Widget } })
[void]$trayMenu.Items.Add('Обновить сейчас', $null, { Start-Fetch })
[void]$trayMenu.Items.Add('Открыть rapira.net', $null, { Start-Process 'https://rapira.net' })
[void]$trayMenu.Items.Add('-')
[void]$trayMenu.Items.Add('Закрыть', $null, { Exit-Widget })
$tray.ContextMenuStrip = $trayMenu
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { if ($window.IsVisible) { Hide-Widget } else { Show-Widget } } })
Set-TrayIcon '…' $GrayColor
$tray.Visible = $true

# ---------- данные ----------
$ru = [Globalization.CultureInfo]::GetCultureInfo('ru-RU')
function Fmt([double]$v) { $v.ToString('N2', $ru) }

$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(4)
$http.DefaultRequestHeaders.UserAgent.ParseAdd('UsdtRubWidget/1.0')
$http.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{ NoCache = $true }

$script:task = $null
$script:lastRate = $null
$script:lastOk = [DateTime]::MinValue
$script:flashUntil = [DateTime]::MinValue

function Start-Fetch {
    if ($null -ne $script:task) { return }
    try { $script:task = $http.GetStringAsync($ApiUrl) } catch { Show-Offline }
}

function Update-View($d) {
    $now = Get-Date
    if ($null -ne $script:lastRate -and $d.Rate -ne $script:lastRate) {
        if ($d.Rate -gt $script:lastRate) { $RateText.Foreground = $BrUp } else { $RateText.Foreground = $BrDown }
        $script:flashUntil = $now.AddMilliseconds(1200)
    }
    $script:lastRate = $d.Rate
    $script:lastOk = $now

    $rateStr = (Fmt $d.Rate) + ' ₽'
    $RateText.Text = $rateStr
    $RateText.Opacity = 1

    $up = $d.ChgAbs -ge 0
    if ($up) { $arrow = '▲'; $sign = '+'; $ChangeText.Foreground = $BrUp }
    else     { $arrow = '▼'; $sign = '−'; $ChangeText.Foreground = $BrDown }
    $chgStr = '{0}{1} ₽ ({0}{2}%)' -f $sign, (Fmt ([Math]::Abs($d.ChgAbs))), (Fmt ([Math]::Abs($d.ChgPct)))
    $ChangeText.Text = "$arrow $chgStr за 24ч"

    $BidAskText.Text = 'Bid {0}  ·  Ask {1}' -f (Fmt $d.Bid), (Fmt $d.Ask)
    $StatusText.Text = 'Rapira · ' + $now.ToString('HH:mm:ss')
    $StatusText.Foreground = $StatusBrush
    $Card.ToolTip = "24ч: мин {0} · макс {1}`nОткрытие {2}" -f (Fmt $d.Low), (Fmt $d.High), (Fmt $d.Open)

    $window.Title = "USDT/RUB  $rateStr  ($sign$(Fmt ([Math]::Abs($d.ChgPct)))%)"
    $taskbar.Description = $window.Title
    if ($up) { $taskbar.Overlay = $OverlayUp } else { $taskbar.Overlay = $OverlayDown }

    $tip = "USDT/RUB $rateStr ($sign$(Fmt ([Math]::Abs($d.ChgPct)))%) · Rapira"
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $tray.Text = $tip
    if ($up) { $bg = $UpColor } else { $bg = $DownColor }
    Set-TrayIcon ([string][Math]::Floor($d.Rate)) $bg
}

function Show-Offline {
    $StatusText.Text = 'нет связи · ' + (Get-Date).ToString('HH:mm:ss')
    $StatusText.Foreground = $BrWarn
    if ($null -eq $script:lastRate) { $ChangeText.Text = 'не удаётся получить курс'; $ChangeText.Foreground = $BrWarn }
    if (((Get-Date) - $script:lastOk).TotalSeconds -gt 30) {
        $RateText.Opacity = 0.5
        $taskbar.Overlay = $null
        if ($null -ne $script:lastRate) { Set-TrayIcon ([string][Math]::Floor($script:lastRate)) $GrayColor }
    }
}

function Complete-Fetch {
    $t = $script:task
    if ($null -eq $t -or -not $t.IsCompleted) { return }
    $script:task = $null
    try {
        if ($t.Status -ne [System.Threading.Tasks.TaskStatus]::RanToCompletion) { throw 'network' }
        $j = $t.Result | ConvertFrom-Json
        $e = @($j.data) | Where-Object { $_.symbol -eq $Symbol } | Select-Object -First 1
        if ($null -eq $e -or [double]$e.close -le 0) { throw 'no data' }
        Update-View ([pscustomobject]@{
            Rate   = [double]$e.close
            Bid    = [double]$e.bidPrice
            Ask    = [double]$e.askPrice
            Open   = [double]$e.open
            High   = [double]$e.high
            Low    = [double]$e.low
            ChgAbs = [double]$e.change
            ChgPct = [double]$e.chg * 100
        })
    } catch { Show-Offline }
}

# ---------- поведение окна ----------
function Save-Config {
    try {
        if ($window.IsVisible) { $cfg.Left = [int]$window.Left; $cfg.Top = [int]$window.Top }
        $cfg.Topmost = $window.Topmost
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
    } catch {}
}

$window.Add_SourceInitialized({
    $vs = [System.Windows.SystemParameters]
    $onScreen = $null -ne $cfg.Left -and $null -ne $cfg.Top -and
                $cfg.Left -ge $vs::VirtualScreenLeft - 50 -and $cfg.Left -le ($vs::VirtualScreenLeft + $vs::VirtualScreenWidth - 80) -and
                $cfg.Top  -ge $vs::VirtualScreenTop - 20  -and $cfg.Top  -le ($vs::VirtualScreenTop + $vs::VirtualScreenHeight - 60)
    if ($onScreen) { $window.Left = $cfg.Left; $window.Top = $cfg.Top }
    else {
        $wa = $vs::WorkArea
        $window.Left = $wa.Right - $window.Width - 8
        $window.Top  = $wa.Top + 8
    }
})

$Card.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -ge 2) { Start-Fetch; return }
    try { $window.DragMove() } catch {}
    Save-Config
})

$Menu.MiRefresh.Add_Click({ Start-Fetch })
$Menu.MiTopmost.Add_Click({ $window.Topmost = $Menu.MiTopmost.IsChecked; Save-Config })
$Menu.MiAutostart.Add_Click({
    try {
        if ($Menu.MiAutostart.IsChecked) { New-AppShortcut $StartupLnk }
        elseif (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force }
    } catch {}
    $Menu.MiAutostart.IsChecked = Test-Path $StartupLnk
})
$Menu.MiHide.Add_Click({ Hide-Widget })
$Menu.MiSite.Add_Click({ Start-Process 'https://rapira.net' })
$Menu.MiExit.Add_Click({ Exit-Widget })

# Alt+F4 / «Закрыть окно» на панели задач — полностью закрывает виджет
$window.Add_Closing({ $tray.Visible = $false })
$window.Add_Closed({ Exit-Widget })

# ---------- таймеры ----------
$fetchTimer = New-Object System.Windows.Threading.DispatcherTimer
$fetchTimer.Interval = [TimeSpan]::FromSeconds($RefreshSeconds)
$fetchTimer.Add_Tick({ Start-Fetch })

$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$uiTimer.Add_Tick({
    Complete-Fetch
    if ($script:flashUntil -ne [DateTime]::MinValue -and (Get-Date) -gt $script:flashUntil) {
        $RateText.Foreground = $BrWhite
        $script:flashUntil = [DateTime]::MinValue
    }
    if ($showSignal.WaitOne(0)) { Show-Widget }   # повторный запуск (например, клик по закреплённой кнопке)
})

$window.Add_Loaded({
    Start-Fetch
    $fetchTimer.Start()
    $uiTimer.Start()
})

# ---------- запуск ----------
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
[void]$app.Run($window)

if ($script:trayHandle -ne [IntPtr]::Zero) { [void][UrwShell]::DestroyIcon($script:trayHandle) }
$http.Dispose()
$mutex.ReleaseMutex()
