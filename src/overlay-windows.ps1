# VS-code-chat-manager, src/overlay-windows.ps1: dot-sourced by VS-code-chat-manager.ps1
# in its turn, never on its own - see the list there.

#region overlay: Windows window ------------------------------------------------
# WPF in a hidden powershell.exe -STA. The window never takes focus and lets
# clicks through while locked: WS_EX_NOACTIVATE, WS_EX_TRANSPARENT on top of
# the WS_EX_LAYERED a transparent WPF window has anyway, and WS_EX_TOOLWINDOW
# to keep it out of Alt+Tab and off the taskbar. Its buttons are a second
# small window beside it, shown while the pointer is near, which takes the
# mouse where it is drawn. The C# below is C# 5, which is what Windows
# PowerShell 5.1 compiles, and holds nothing that moves the pointer, types,
# or brings a window forward; the pointer is only ever read.

$script:ChatOverlayNativeCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class ChatOverlayNative {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern int GetWindowLong32(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")] static extern IntPtr GetWindowLongPtr64(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr h, int i, int v);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    const int GWL_EXSTYLE = -20;
    public const long WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_LAYERED = 0x80000, WS_EX_NOACTIVATE = 0x8000000;
    const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_NOOWNERZORDER = 0x200;

    public static long GetExStyle(IntPtr h) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(h, GWL_EXSTYLE).ToInt64() : GetWindowLong32(h, GWL_EXSTYLE);
    }
    static void SetExStyle(IntPtr h, long v) {
        if (IntPtr.Size == 8) { SetWindowLongPtr64(h, GWL_EXSTYLE, new IntPtr(v)); } else { SetWindowLong32(h, GWL_EXSTYLE, (int)v); }
    }
    // always a tool window that never activates; clicks go through only while
    // locked. WPF sets APPWINDOW for ShowInTaskbar, which would put a button
    // on the taskbar in spite of TOOLWINDOW, so it goes.
    public static void ApplyExStyle(IntPtr h, bool clickThrough) {
        long s = (GetExStyle(h) | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED) & ~WS_EX_APPWINDOW;
        s = clickThrough ? (s | WS_EX_TRANSPARENT) : (s & ~WS_EX_TRANSPARENT);
        SetExStyle(h, s);
    }
    // back above windows that took the topmost band since - without activating
    public static void KeepTopmost(IntPtr h) {
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    public static void MoveTo(IntPtr h, int x, int y) {
        SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    // where and how big, in the pixels of the screen it lands on
    public static void Place(IntPtr h, int x, int y, int w, int hgt) {
        SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    public static int[] GetRect(IntPtr h) {
        RECT r;
        if (!GetWindowRect(h, out r)) { return null; }
        return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
    }
    // per-monitor v2 where Windows has it (1703+), else system-wide
    public static bool SetDpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return true; } } catch (EntryPointNotFoundException) { }
        try { return SetProcessDPIAware(); } catch (EntryPointNotFoundException) { return false; }
    }
    // a file dropped on the console, copied off the window's thread: a large
    // one would otherwise freeze the panel and the console both
    public static System.Threading.Tasks.Task CopyFileAsync(string from, string to) {
        return System.Threading.Tasks.Task.Run(() => System.IO.File.Copy(from, to, true));
    }
}

// A system-wide hotkey: a hidden window of its own to receive WM_HOTKEY,
// filtered here so PowerShell hears only the key press, not every message.
public class ChatOverlayHotkey : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    const int WM_HOTKEY = 0x312;
    const uint MOD_NOREPEAT = 0x4000;
    bool registered;
    public event EventHandler Pressed;
    public ChatOverlayHotkey() { CreateHandle(new CreateParams()); }
    public bool Register(uint mods, uint vk) {
        if (registered) { UnregisterHotKey(Handle, 1); registered = false; }
        registered = RegisterHotKey(Handle, 1, mods | MOD_NOREPEAT, vk);
        return registered;
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && Pressed != null) { Pressed(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
    public void Dispose() {
        if (registered) { UnregisterHotKey(Handle, 1); registered = false; }
        if (Handle != IntPtr.Zero) { DestroyHandle(); }
    }
}
'@

# Two looks. A state keeps its colour's meaning in both; the light look's are
# darker, to read on white. panel is the ground of the buttons and settings
# box, which sit over the rows; accent marks the choice made.
$script:ChatOverlayPalettes = @{
    dark  = @{
        waiting = '#F5B942'; 'needs-input' = '#F5B942'; busy = '#4CC38A'; running = '#4EA1FF'; idle = '#80868F'; queued = '#B48CFF'; cutoff = '#FF8A4C'
        text = '#E8EAED'; dim = '#9AA0A6'; faint = '#6B7079'; project = '#8AB8FF'; frame = '#EB1B1F24'; edge = '#2EFFFFFF'
        unlocked = '#4EA1FF'; track = '#26FFFFFF'; normal = '#5AA9E6'; warning = '#F5B942'; critical = '#FF5C5C'
        warn = '#F5B942'; error = '#FF7B72'; panel = '#F7262B33'; hover = '#33FFFFFF'; accent = '#4EA1FF'; onAccent = '#FFFFFF'
        window = '#FF1E2227'; input = '#FF15181C'; inputEdge = '#3DFFFFFF'; select = '#384EA1FF'
    }
    light = @{
        waiting = '#C98A00'; 'needs-input' = '#C98A00'; busy = '#1A8F4C'; running = '#1F6FEB'; idle = '#8C959F'; queued = '#8250DF'; cutoff = '#BC4C00'
        text = '#1F2328'; dim = '#57606A'; faint = '#8C959F'; project = '#0969DA'; frame = '#F2FAFAFB'; edge = '#26000000'
        unlocked = '#0969DA'; track = '#1F000000'; normal = '#0969DA'; warning = '#BF8700'; critical = '#CF222E'
        warn = '#9A6700'; error = '#CF222E'; panel = '#FAFFFFFF'; hover = '#1A000000'; accent = '#0969DA'; onAccent = '#FFFFFF'
        window = '#FFF6F8FA'; input = '#FFFFFFFF'; inputEdge = '#40000000'; select = '#290969DA'
    }
}
$script:ChatOverlayColors = $script:ChatOverlayPalettes.dark

function Initialize-ChatOverlayNative {
    # In the one order that works: DPI awareness is process-wide and only the
    # first call gets to set it, and WPF reads it as it loads. The AppContext
    # switch lets WPF redraw at a second monitor's own scale when the panel is
    # dragged there, instead of keeping the first one's.
    if (-not ('ChatOverlayNative' -as [type])) {
        Add-Type -TypeDefinition $script:ChatOverlayNativeCode -ReferencedAssemblies System.Windows.Forms
    }
    try { [void][ChatOverlayNative]::SetDpiAware() } catch { Write-ChatOverlayLog "dpi: $($_.Exception.Message)" }
    try { [System.AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false) } catch {}
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
    # A panel this small, redrawn every few seconds at most, gains nothing
    # from a Direct3D device - which is most of what WPF would otherwise hold.
    try { [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly } catch {}
}

function Get-ChatOverlayBrush {
    param([string]$Name)
    $hex = if ($Name.StartsWith('#')) { $Name } else { $script:ChatOverlayColors[$Name] }
    if (-not $hex) { $hex = $script:ChatOverlayColors.text }
    $b = $script:ChatOverlayBrushes[$hex]
    if (-not $b) {
        $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()
        $script:ChatOverlayBrushes[$hex] = $b
    }
    return $b
}

function New-ChatOverlayText {
    param([string]$Text, [string]$Color = 'text', [double]$Size = 0, [switch]$Bold, [switch]$Trim)
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text = $Text
    $t.Foreground = Get-ChatOverlayBrush $Color
    if ($Size) { $t.FontSize = $Size }
    if ($Bold) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    if ($Trim) { $t.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis }
    return $t
}

function New-ChatOverlayWindow {
    # The window and its frame, built in code rather than XAML: rows come and
    # go every pass, and one way of making elements is simpler than two.
    param($H)
    $cfg = $H.Ctx.Config
    [void](Select-ChatOverlayPalette $H)
    $w = [System.Windows.Window]::new()
    $w.Title = 'chatoverlay'
    $w.WindowStyle = [System.Windows.WindowStyle]::None
    $w.AllowsTransparency = $true
    $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $w.Topmost = $true
    $w.ShowActivated = $false
    # true, with WS_EX_TOOLWINDOW keeping it off the taskbar: false would make
    # WPF parent the window to a hidden owner that is not topmost
    $w.ShowInTaskbar = $true
    $w.SizeToContent = [System.Windows.SizeToContent]::Height
    $w.Width = $cfg.width
    $w.Opacity = $cfg.opacity
    $w.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $w.Left = -32000
    $w.Top = -32000
    $w.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI, Malgun Gothic, Microsoft YaHei UI')
    $w.FontSize = 12
    $frame = [System.Windows.Controls.Border]::new()
    $frame.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $frame.Background = Get-ChatOverlayBrush 'frame'
    $frame.BorderBrush = Get-ChatOverlayBrush 'edge'
    $frame.BorderThickness = [System.Windows.Thickness]::new(1)
    $frame.Padding = [System.Windows.Thickness]::new(11, 8, 11, 9)
    $stack = [System.Windows.Controls.StackPanel]::new()
    $frame.Child = $stack
    $w.Content = $frame
    # only ever raised while unlocked - a locked window lets the mouse through
    $frame.add_MouseLeftButtonDown({ Invoke-ChatOverlayDrag })
    $frame.add_MouseEnter({ $script:ChatOverlayHost.PointerIn = $true })
    $frame.add_MouseLeave({ $script:ChatOverlayHost.PointerIn = $false; $script:ChatOverlayHost.LeftAt = Get-Date })
    $H.Win = $w
    $H.Frame = $frame
    $H.Stack = $stack
    $H.Hwnd = [System.Windows.Interop.WindowInteropHelper]::new($w).EnsureHandle()
    [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
    New-ChatOverlayControlsWindow $H
    New-ChatOverlayChipWindow $H
}

function New-ChatOverlayControlsWindow {
    <#
    The buttons and the settings box live in a small window of their own,
    on the panel's top edge rather than over its rows. So the panel stays
    click-through all over, and this one - shown only while the pointer is
    near - takes the mouse where it is drawn; its see-through parts let
    clicks through, as any layered window's do. The same styles as the panel
    less WS_EX_TRANSPARENT: it never takes focus either, and is in neither
    Alt+Tab nor the taskbar. Kept at full opacity, so the slider stays
    readable whatever it is set to.
    #>
    param($H)
    $c = [System.Windows.Window]::new()
    $c.Title = 'chatoverlay controls'
    $c.WindowStyle = [System.Windows.WindowStyle]::None
    $c.AllowsTransparency = $true
    $c.Background = [System.Windows.Media.Brushes]::Transparent
    $c.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $c.Topmost = $true
    $c.ShowActivated = $false
    # true for the same reason as the panel's: false means a hidden owner
    # that is not topmost
    $c.ShowInTaskbar = $true
    $c.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $c.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $c.Left = -32000
    $c.Top = -32000
    $c.FontFamily = $H.Win.FontFamily
    $c.FontSize = 12
    $stack = [System.Windows.Controls.StackPanel]::new()
    $c.Content = $stack
    $H.CtlWin = $c
    $H.CtlStack = $stack
    New-ChatOverlayControls $H
    $H.CtlHwnd = [System.Windows.Interop.WindowInteropHelper]::new($c).EnsureHandle()
    [ChatOverlayNative]::ApplyExStyle($H.CtlHwnd, $false)
    # the box opening or closing changes its size; the edge by the panel stays
    $c.add_SizeChanged({ param($s, $e) Set-ChatOverlayControlsPlacement $script:ChatOverlayHost $e.NewSize })
}

function Select-ChatOverlayPalette {
    # the colours for the theme set, and whether that changed the look
    param($H)
    $name = Resolve-ChatOverlayTheme $H.Ctx.Config.theme
    if ($name -eq $H.ThemeName) { return $false }
    $H.ThemeName = $name
    $script:ChatOverlayColors = $script:ChatOverlayPalettes[$name]
    return $true
}

function Update-ChatOverlayTheme {
    # the look again, after the setting or Windows' own changed: the frame,
    # the buttons and settings box made anew, the rows redrawn, the tray dot
    param($H)
    if (-not (Select-ChatOverlayPalette $H)) { return }
    $H.Frame.Background = Get-ChatOverlayBrush 'frame'
    $H.Frame.BorderBrush = Get-ChatOverlayBrush $(if ($H.Locked) { 'edge' } else { 'unlocked' })
    New-ChatOverlayControls $H
    Hide-ChatOverlayChip $H
    if ($H.ChipWin) { New-ChatOverlayChipContent $H }
    # the console too, keeping what is typed in it
    if ($H.Con) { Initialize-ChatConsoleContent $H }
    $H.ViewKey = $null
    if ($H.Snap) {
        Update-ChatOverlayView $H $H.Snap
        if ($H.Tray) { Update-ChatOverlayTray $H $H.Snap }
    }
}

function New-ChatOverlayIcon {
    # A small button drawn as a path, so no icon font is needed: stroked for
    # lines, filled for dots, or both.
    param([string]$Tip, $Geometry, [switch]$Stroke, [switch]$Fill)
    $b = [System.Windows.Controls.Border]::new()
    $b.Width = 22
    $b.Height = 20
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    # transparent, not none: WPF sends the mouse only to what is painted
    $b.Background = [System.Windows.Media.Brushes]::Transparent
    $b.ToolTip = $Tip
    $p = [System.Windows.Shapes.Path]::new()
    $p.Data = $Geometry
    if ($Stroke) {
        $p.Stroke = Get-ChatOverlayBrush 'dim'
        $p.StrokeThickness = 1.4
        $p.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
        $p.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
    }
    if ($Fill) { $p.Fill = Get-ChatOverlayBrush 'dim' }
    $p.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $p.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $b.Child = $p
    $b.add_MouseEnter({ param($s, $e) $s.Background = Get-ChatOverlayBrush 'hover' })
    $b.add_MouseLeave({ param($s, $e) $s.Background = [System.Windows.Media.Brushes]::Transparent })
    return $b
}

function New-ChatOverlayControls {
    <#
    The controls window's content: a row of buttons - drag grip, collapse,
    refresh usage, settings, hide to the tray, close, left to right, so
    close sits at the corner as it does on any window - and the settings box
    on the far side of them from the panel. Made anew when the look changes
    or the panel folds; the box stays open or shut as it was.
    #>
    param($H)
    $H.CtlStack.Children.Clear()
    $geo = { param($d) [System.Windows.Media.Geometry]::Parse($d) }
    $dots = [System.Windows.Media.GeometryGroup]::new()
    foreach ($x in 1.5, 5.5) { foreach ($y in 1.5, 5.5, 9.5) { $dots.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new($x, $y), 1.25, 1.25)) } }
    $sliders = [System.Windows.Media.GeometryGroup]::new()
    $sliders.Children.Add((& $geo 'M0,2.5 L11,2.5 M0,8.5 L11,8.5'))
    $sliders.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new(3.5, 2.5), 1.8, 1.8))
    $sliders.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new(7.5, 8.5), 1.8, 1.8))
    # a chevron pointing where the panel will go: up to fold it, down to open it
    $fold = if ($H.Collapsed) { & $geo 'M0.5,1 L4.5,5 L8.5,1' } else { & $geo 'M0.5,5 L4.5,1 L8.5,5' }
    # a circle with a gap and an arrowhead
    $again = & $geo 'M8.6,3.2 A4,4 0 1 0 9,6.5 M8.8,0.6 L8.7,3.4 L5.9,3.1'
    # an arrow down onto a line: into the tray
    $tray = & $geo 'M4.5,0.5 L4.5,6 M2,3.6 L4.5,6 L7,3.6 M0.5,9 L8.5,9'
    # a speech bubble: the console, to write to a chat
    $bubble = & $geo 'M1,1 L10,1 L10,7 L4.5,7 L2,9.5 L2,7 L1,7 Z'
    $cross = & $geo 'M0.5,0.5 L8.5,8.5 M8.5,0.5 L0.5,8.5'

    $grip = New-ChatOverlayIcon 'Drag to move' $dots -Fill
    $grip.Cursor = [System.Windows.Input.Cursors]::SizeAll
    $grip.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Start-ChatOverlayGripDrag $s })
    $grip.add_MouseMove({ param($s, $e) Move-ChatOverlayGripDrag })
    $grip.add_MouseLeftButtonUp({ param($s, $e) Stop-ChatOverlayGripDrag $s })
    $grip.add_LostMouseCapture({ param($s, $e) Stop-ChatOverlayGripDrag $s })
    $foldB = New-ChatOverlayIcon $(if ($H.Collapsed) { 'Expand' } else { 'Collapse to one line' }) $fold -Stroke
    $foldB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Collapsed) { 'expand' } else { 'collapse' }) })
    $againB = New-ChatOverlayIcon 'Ask Claude for usage now - Codex''s moves only when Codex runs' $again -Stroke
    $againB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayRefresh })
    # turns while an ask is out (Update-ChatOverlaySpin), about the arc's centre
    $againB.Child.RenderTransform = [System.Windows.Media.RotateTransform]::new(0, 5.2, 5.3)
    $H.Spin = $againB.Child.RenderTransform
    $H.Spinning = $false
    $conB = New-ChatOverlayIcon 'Open the console - write to a chat, queue, continue' $bubble -Stroke
    $conB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb 'console' })
    $gear = New-ChatOverlayIcon 'Opacity and theme' $sliders -Stroke -Fill
    $gear.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Set-ChatOverlaySettingsOpen $script:ChatOverlayHost (-not $script:ChatOverlayHost.SettingsOpen) })
    $trayB = New-ChatOverlayIcon 'Hide to the tray - click the tray dot to show it' $tray -Stroke
    $trayB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Hide-ChatOverlayByButton })
    $close = New-ChatOverlayIcon 'Close the overlay - chatoverlay starts it again' $cross -Stroke
    $close.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb 'stop' })
    $line = [System.Windows.Controls.StackPanel]::new()
    $line.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $H.CtlButtons = @($grip, $foldB, $againB, $conB, $gear, $trayB, $close)
    foreach ($b in $H.CtlButtons) { [void]$line.Children.Add($b) }
    $H.CtlLine = $line
    $bar = [System.Windows.Controls.Border]::new()
    $bar.Background = Get-ChatOverlayBrush 'panel'
    $bar.BorderBrush = Get-ChatOverlayBrush 'edge'
    $bar.BorderThickness = [System.Windows.Thickness]::new(1)
    $bar.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $bar.Padding = [System.Windows.Thickness]::new(1)
    $bar.Child = $line
    $H.Controls = $bar
    $H.Settings = New-ChatOverlaySettings $H
    Set-ChatOverlayControlsSide $H $(if ($H.CtlSide) { $H.CtlSide } else { 'above' })
}

function New-ChatOverlaySettings {
    # the box beside the row of buttons: opacity on a slider, the theme as
    # three choices, and usage as lines or bars
    param($H)
    $theme = [string]$H.Ctx.Config.theme
    $box = [System.Windows.Controls.Border]::new()
    $box.Background = Get-ChatOverlayBrush 'panel'
    $box.BorderBrush = Get-ChatOverlayBrush 'edge'
    $box.BorderThickness = [System.Windows.Thickness]::new(1)
    $box.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $box.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $box.Width = 244
    $box.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    $box.Visibility = if ($H.SettingsOpen) { 'Visible' } else { 'Collapsed' }
    $g = [System.Windows.Controls.Grid]::new()
    foreach ($cw in 56, 0, 38) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($cw) { [System.Windows.GridLength]::new($cw) } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $g.ColumnDefinitions.Add($cd)
    }
    foreach ($i in 1..3) { $g.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) }
    $put = {
        param($el, $row, $col, $span = 1)
        [System.Windows.Controls.Grid]::SetRow($el, $row)
        [System.Windows.Controls.Grid]::SetColumn($el, $col)
        [System.Windows.Controls.Grid]::SetColumnSpan($el, $span)
        [void]$g.Children.Add($el)
    }
    $label = { param($t) $l = New-ChatOverlayText $t 'dim' 11; $l.VerticalAlignment = [System.Windows.VerticalAlignment]::Center; $l }

    & $put (& $label 'Opacity') 0 0
    $slider = [System.Windows.Controls.Slider]::new()
    $slider.Minimum = 0.3
    $slider.Maximum = 1.0
    $slider.SmallChange = 0.05
    $slider.LargeChange = 0.1
    $slider.IsMoveToPointEnabled = $true
    $slider.Value = if ($H.Win) { $H.Win.Opacity } else { $H.Ctx.Config.opacity }
    $slider.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $slider.Margin = [System.Windows.Thickness]::new(0, 2, 4, 2)
    $slider.add_ValueChanged({ param($s, $e) Set-ChatOverlayOpacity $script:ChatOverlayHost $e.NewValue })
    & $put $slider 0 1
    $H.OpacityText = New-ChatOverlayText "$([int][Math]::Round($slider.Value * 100))%" 'text' 11
    $H.OpacityText.TextAlignment = [System.Windows.TextAlignment]::Right
    $H.OpacityText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    & $put $H.OpacityText 0 2

    & $put (& $label 'Theme') 1 0
    & $put (New-ChatOverlayChips @('dark', 'light', 'system') $theme { param($s, $e) $e.Handled = $true; Set-ChatOverlayThemeChoice $script:ChatOverlayHost ([string]$s.Tag) }) 1 1 2
    & $put (& $label 'Usage') 2 0
    & $put (New-ChatOverlayChips @('lines', 'bars') ([string]$H.Ctx.Config.usageView) { param($s, $e) $e.Handled = $true; Set-ChatOverlayUsageView $script:ChatOverlayHost ([string]$s.Tag) }) 2 1 2
    $box.Child = $g
    return $box
}

function New-ChatOverlayChips {
    # a row of choices, the one in force filled in; a click hands its name
    # to -OnClick
    param([string[]]$Names, [string]$Current, [scriptblock]$OnClick)
    $chips = [System.Windows.Controls.StackPanel]::new()
    $chips.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $chips.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    foreach ($t in $Names) {
        $on = $t -eq $Current
        $c = [System.Windows.Controls.Border]::new()
        $c.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $c.BorderThickness = [System.Windows.Thickness]::new(1)
        $c.Padding = [System.Windows.Thickness]::new(8, 1, 8, 2)
        $c.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $c.Background = if ($on) { Get-ChatOverlayBrush 'accent' } else { [System.Windows.Media.Brushes]::Transparent }
        $c.BorderBrush = Get-ChatOverlayBrush $(if ($on) { 'accent' } else { 'edge' })
        $c.Cursor = [System.Windows.Input.Cursors]::Hand
        $c.Tag = $t
        $c.Child = New-ChatOverlayText ($t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1)) $(if ($on) { 'onAccent' } else { 'text' }) 11
        $c.add_MouseLeftButtonUp($OnClick)
        [void]$chips.Children.Add($c)
    }
    return $chips
}

function Set-ChatOverlaySettingsOpen {
    param($H, [bool]$Open)
    $H.SettingsOpen = $Open
    if ($H.Settings) { $H.Settings.Visibility = if ($Open) { 'Visible' } else { 'Collapsed' } }
}

function Show-ChatOverlayControls {
    # the controls window comes with the pointer and goes with it, closing
    # the box; placed before it shows, so it never flashes where it last was
    param($H, [bool]$Show)
    $H.ControlsShown = $Show
    if (-not $H.CtlWin) { return }
    if ($Show) {
        Set-ChatOverlayControlsPlacement $H
        $H.CtlWin.Show()
        # WPF sets WS_EX_APPWINDOW again as it shows a window
        [ChatOverlayNative]::ApplyExStyle($H.CtlHwnd, $false)
        [ChatOverlayNative]::KeepTopmost($H.CtlHwnd)
        Set-ChatOverlayControlsPlacement $H
    }
    else {
        if ($H.SettingsOpen) { Set-ChatOverlaySettingsOpen $H $false }
        $H.CtlWin.Hide()
    }
}

function Get-ChatOverlayControlsPlacement {
    <#
    Where the controls window goes, all in screen pixels (-Panel a rect,
    x y width height; -Size just width and height): its long edge along the
    panel's top, its right end at the panel's top-right corner - above the
    panel while the row of buttons (-Bar tall) fits there, else below it,
    on the side it is on already (-Prefer, above at first) while it fits.
    So the box opening, which makes the window taller away from the panel,
    never moves the buttons out from under the pointer; a box too tall for
    its side is kept on the screen instead. Kept on the screen side to side
    too. Pure, for the tests.
    #>
    param([int[]]$Panel, [int[]]$Size, $Screen, [int]$Gap = 4, [string]$Prefer = 'above', [int]$Bar = 0)
    if ($Bar -le 0) { $Bar = $Size[1] }
    $top = $Screen.Y
    $bottom = $Screen.Y + $Screen.Height
    $fitsAbove = $Panel[1] - $Gap - $Bar -ge $top
    $fitsBelow = $Panel[1] + $Panel[3] + $Gap + $Bar -le $bottom
    $side = if ($Prefer -eq 'below') { if ($fitsBelow -or -not $fitsAbove) { 'below' } else { 'above' } }
    else { if ($fitsAbove -or -not $fitsBelow) { 'above' } else { 'below' } }
    $y = if ($side -eq 'above') { [Math]::Max($top, $Panel[1] - $Gap - $Size[1]) } else { [Math]::Min($bottom - $Size[1], $Panel[1] + $Panel[3] + $Gap) }
    $x = [Math]::Max($Screen.X, [Math]::Min($Panel[0] + $Panel[2] - $Size[0], $Screen.X + $Screen.Width - $Size[0]))
    return [pscustomobject]@{ X = [int]$x; Y = [int]$y; Side = $side }
}

function Set-ChatOverlayControlsSide {
    # The row of buttons hugs the panel's edge, above it or below, flush
    # with its right; the settings box goes on the far side of the row, so
    # opening it never pushes the row off the panel's edge.
    param($H, [string]$Side)
    $H.CtlSide = $Side
    foreach ($el in @($H.Controls, $H.Settings)) { if ($el) { $el.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right } }
    if (-not $H.CtlStack -or -not $H.Controls -or -not $H.Settings) { return }
    $H.Settings.Margin = if ($Side -eq 'below') { [System.Windows.Thickness]::new(0, 4, 0, 0) } else { [System.Windows.Thickness]::new(0, 0, 0, 4) }
    $H.CtlStack.Children.Clear()
    $order = if ($Side -eq 'below') { $H.Controls, $H.Settings } else { $H.Settings, $H.Controls }
    foreach ($el in $order) { [void]$H.CtlStack.Children.Add($el) }
}

function Get-ChatOverlayControlsTarget {
    # Where the controls window goes now, in screen pixels - x, y, width,
    # height, the side of the panel and the gap to it - worked out as for
    # placing it, without moving it: the pointer check wants the spot while
    # it is hidden too. -Dip the size it is about to take, in WPF's units.
    param($H, $Dip)
    if (-not $H -or -not $H.CtlWin -or $H.CtlHwnd -eq [IntPtr]::Zero -or $H.Hwnd -eq [IntPtr]::Zero) { return $null }
    $p = [ChatOverlayNative]::GetRect($H.Hwnd)
    $c = [ChatOverlayNative]::GetRect($H.CtlHwnd)
    if (-not $p -or -not $c) { return $null }
    $a = if ($script:ChatOverlayWorkAreaSeam) { & $script:ChatOverlayWorkAreaSeam $p }
    else { [System.Windows.Forms.Screen]::FromRectangle([System.Drawing.Rectangle]::new($p[0], $p[1], $p[2], $p[3])).WorkingArea }
    # this screen's pixels to one of WPF's units: 4 of them between the two
    $px = $p[2] / [Math]::Max(1.0, [double]$H.Win.ActualWidth)
    $gap = [int][Math]::Round(4 * $px)
    # Its width and height - never its rect, whose first two numbers are
    # where it is: placed by those, it jumped between two spots each pass.
    # Its rect is behind in two cases. As the box opens or shuts, WPF says
    # the new size before the window takes it, so that size is passed in:
    # the window moves as it grows and is never over the panel. Hidden, it
    # keeps the size it last had, or WPF's default before it first shows, so
    # what its content will take instead: it never shows up somewhere else
    # first.
    if (-not $Dip -and -not $H.CtlWin.IsVisible) {
        $H.CtlStack.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $Dip = $H.CtlStack.DesiredSize
    }
    $size = if ($Dip) { @([int][Math]::Ceiling($Dip.Width * $px), [int][Math]::Ceiling($Dip.Height * $px)) } else { @($c[2], $c[3]) }
    # the row of buttons' own height: what has to fit beside the panel
    $rowDip = if (-not $H.Controls) { 0 } elseif ($H.Controls.ActualHeight -gt 0) { $H.Controls.ActualHeight } else { $H.Controls.DesiredSize.Height }
    $bar = [int][Math]::Round($rowDip * $px)
    $at = Get-ChatOverlayControlsPlacement $p $size ([pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height }) $gap $H.CtlSide $bar
    return [pscustomobject]@{ X = $at.X; Y = $at.Y; Width = $size[0]; Height = $size[1]; Side = $at.Side; Gap = $gap; Now = $c }
}

function Set-ChatOverlayControlsPlacement {
    # the controls window on the panel's top edge, wherever the panel is
    # now; -Dip the size it is about to take, in WPF's units
    param($H, $Dip)
    $t = Get-ChatOverlayControlsTarget $H $Dip
    if (-not $t) { return }
    if ($t.Side -ne $H.CtlSide) { Set-ChatOverlayControlsSide $H $t.Side }
    if ($t.X -ne $t.Now[0] -or $t.Y -ne $t.Now[1]) { [ChatOverlayNative]::MoveTo($H.CtlHwnd, $t.X, $t.Y) }
}

function Get-ChatOverlayControlsZone {
    <#
    Where the pointer counts as on the buttons, in screen pixels: their
    window's rect (-Rect x y width height) - where it is, or while hidden
    where it would go - and the gap between it and the panel on its -Side.
    So the buttons can be reached straight from anywhere, not only by way of
    the panel, and crossing the gap never leaves them. Pure, for the tests.
    #>
    param([int[]]$Rect, [string]$Side, [int]$Gap)
    if (-not $Rect -or $Rect.Count -lt 4) { return $null }
    if ($Side -eq 'below') { return @($Rect[0], ($Rect[1] - $Gap), $Rect[2], ($Rect[3] + $Gap)) }
    return @($Rect[0], $Rect[1], $Rect[2], ($Rect[3] + $Gap))
}

function Get-ChatOverlayControlsHoverZone {
    # the buttons' zone for the pointer check, shown or hidden; $null when
    # there is no controls window to place
    param($H)
    $t = Get-ChatOverlayControlsTarget $H
    if (-not $t) { return $null }
    return Get-ChatOverlayControlsZone @($t.X, $t.Y, $t.Width, $t.Height) $t.Side $t.Gap
}

function Start-ChatOverlayGripDrag {
    # A press on the grip: the panel follows the pointer until it is let go,
    # and the controls follow the panel. The pointer is only read; the
    # windows moved are the overlay's own.
    param($Grip)
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if (-not $r) { return }
    $m = [System.Windows.Forms.Control]::MousePosition
    $H.GripDrag = @{ Mx = $m.X; My = $m.Y; X = $r[0]; Y = $r[1] }
    $H.Dragging = $true
    [void]$Grip.CaptureMouse()
}

function Move-ChatOverlayGripDrag {
    $H = $script:ChatOverlayHost
    if (-not $H -or -not $H.GripDrag) { return }
    $d = $H.GripDrag
    $m = [System.Windows.Forms.Control]::MousePosition
    [ChatOverlayNative]::MoveTo($H.Hwnd, $d.X + $m.X - $d.Mx, $d.Y + $m.Y - $d.My)
    Set-ChatOverlayControlsPlacement $H
}

function Stop-ChatOverlayGripDrag {
    # let go - or the capture lost some other way: where it ended is kept
    param($Grip)
    $H = $script:ChatOverlayHost
    if (-not $H -or -not $H.GripDrag) { return }
    $H.GripDrag = $null
    $H.Dragging = $false
    if ($Grip.IsMouseCaptured) { $Grip.ReleaseMouseCapture() }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if ($r) { $H.State.x = $r[0]; $H.State.y = $r[1]; Save-ChatOverlayState $H.State }
}

function Set-ChatOverlayCollapsed {
    # one line - what is running, and usage - or the whole panel; kept for
    # the next start in overlay-state.json
    param($H, [bool]$Collapsed)
    $H.Collapsed = $Collapsed
    Hide-ChatOverlayChip $H
    Set-ChatqProp $H.State 'collapsed' $Collapsed
    Save-ChatOverlayState $H.State
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
    # the chevron turns
    if ($H.CtlWin) { New-ChatOverlayControls $H }
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayOpacity {
    # as the slider moves; config.json gets it once the slider rests
    param($H, [double]$Value)
    if (-not $H) { return }
    $v = [Math]::Round([Math]::Max(0.3, [Math]::Min(1.0, $Value)), 2)
    $H.Win.Opacity = $v
    if ($H.OpacityText) { $H.OpacityText.Text = "$([int][Math]::Round($v * 100))%" }
    $H.PendingOpacity = $v
    $H.PendingAt = Get-Date
}

function Save-ChatOverlaySetting {
    # a choice made in the settings box, kept in config.json like one made
    # with chatoverlay, so the next start has it
    param($H, [hashtable]$Values)
    try {
        Set-ChatOverlayConfig $Values
        $H.Ctx.Config = Get-ChatOverlayConfig
    }
    catch { Write-ChatOverlayLog "settings: $($_.Exception.Message)" }
}

function Set-ChatOverlayThemeChoice {
    param($H, [string]$Theme)
    if (-not $H -or $H.Ctx.Config.theme -eq $Theme) { return }
    Save-ChatOverlaySetting $H @{ theme = $Theme }
    # made anew even when the look stays the same, so the choice shows
    $H.ThemeName = $null
    Update-ChatOverlayTheme $H
}

function Set-ChatOverlayUsageView {
    # lines or bars, from the settings box: kept in config.json, drawn now
    param($H, [string]$View)
    if (-not $H -or $H.Ctx.Config.usageView -eq $View) { return }
    Save-ChatOverlaySetting $H @{ usageView = $View }
    New-ChatOverlayControls $H
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
}

function Invoke-ChatOverlayRefresh {
    # the refresh button: a pass now, which sends the ask; the next pass,
    # two seconds on, draws the answer
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.Dragging) { return }
    Request-ChatOverlayUsageRefresh $H.Ctx
    $H.ViewKey = $null
    Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx -Peek)
    Update-ChatOverlaySpin $H
}

function Update-ChatOverlaySpin {
    # Every pointer check: the refresh icon turns while an ask is out, and an
    # answer that is in is drawn now - a pass would pick it up only up to 2 s
    # on, long enough for a click to look like it did nothing.
    param($H)
    $ready = { param($f) $f -and ($f.Done -or ($f.Task -and $f.Task.IsCompleted) -or ($f.Proc -and $f.Proc.HasExited)) }
    if (((& $ready $H.Ctx.Fetch) -or (& $ready $H.Ctx.CopilotFetch)) -and -not $H.Dragging) {
        Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx -Peek)
    }
    $out = [bool]($H.Ctx.Fetch -or $H.Ctx.CopilotFetch)
    if (-not $H.Spin -or $out -eq $H.Spinning) { return }
    $H.Spinning = $out
    $prop = [System.Windows.Media.RotateTransform]::AngleProperty
    if ($out) {
        $a = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 360, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(900)))
        $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $H.Spin.BeginAnimation($prop, $a)
    }
    else { $H.Spin.BeginAnimation($prop, $null) }
}

function Hide-ChatOverlayByButton {
    # the tray button hides the panel, and says once where it went
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    Invoke-ChatOverlayVerb 'hide'
    if ($H.Tray -and -not $H.HideTold) {
        $H.HideTold = $true
        $key = if ($H.Hotkey) { " or press $($H.HotkeyText)" } else { '' }
        $H.Tray.ShowBalloonTip(6000, 'chatoverlay', "Hidden. Click the tray dot$key to show it again.", [System.Windows.Forms.ToolTipIcon]::None)
    }
}

function Get-ChatOverlayControlsShown {
    <#
    Whether the buttons show, from where the pointer is. Not on first
    contact: a pointer crossing the click-through panel, or the spot above
    it where the buttons go, on its way to the window under it would meet
    buttons that take its click. It rests on either 350 ms first - so the
    buttons can be pointed at straight away, and come up under the pointer.
    Never while a mouse button is held: a tab or a file dragged across that
    corner in the app below would be dropped on them. Once up they stay
    while the pointer is on the panel or on them, while a mouse button is
    held (a slider dragged off the box), mid-drag, and 700 ms after it
    leaves. Pure, for the tests.
    #>
    param([bool]$Shown, [bool]$OnPanel, [bool]$OnControls, [bool]$Dragging, [bool]$Down, [double]$RestedMs, [double]$SinceOverMs)
    if ($Dragging) { return $true }
    if (-not $Shown) { return ((-not $Down) -and ($OnPanel -or $OnControls) -and $RestedMs -ge 350) }
    return ($OnPanel -or $OnControls -or $Down -or $SinceOverMs -lt 700)
}

function Test-ChatOverlayPointerIn {
    # a point, in screen pixels, inside a window's rect from GetRect
    param($At, $Rect)
    return [bool]($Rect -and $At.X -ge $Rect[0] -and $At.X -lt ($Rect[0] + $Rect[2]) -and $At.Y -ge $Rect[1] -and $At.Y -lt ($Rect[1] + $Rect[3]))
}

function Update-ChatOverlayHover {
    <#
    Every 120 ms: where the pointer is - read, never moved - against the
    panel and the controls' zone: their window and the gap to the panel, or
    while hidden the spot they would take. Resting on either brings the
    controls, which stay a moment after it leaves; while a button is held
    they stay, so a slider dragged off the box keeps going. The controls
    follow a panel moved some other way, and an opacity the slider settled
    on is saved here too.
    #>
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.ShuttingDown -or $H.Hidden -or $H.Hwnd -eq [IntPtr]::Zero) { return }
    try {
        $m = [System.Windows.Forms.Control]::MousePosition
        $down = [System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::None
        $onPanel = Test-ChatOverlayPointerIn $m ([ChatOverlayNative]::GetRect($H.Hwnd))
        $onCtl = Test-ChatOverlayPointerIn $m (Get-ChatOverlayControlsHoverZone $H)
        $now = Get-Date
        # a rest with a button held is a drag in the app below; it starts over
        # once the button is let go
        if (-not ($onPanel -or $onCtl) -or ($down -and -not $H.ControlsShown)) { $H.EnterAt = $null }
        elseif (-not $H.EnterAt) { $H.EnterAt = $now }
        if ($onPanel -or $onCtl) { $H.OverAt = $now }
        $rested = if ($H.EnterAt) { ($now - $H.EnterAt).TotalMilliseconds } else { 0 }
        $since = if ($H.OverAt) { ($now - $H.OverAt).TotalMilliseconds } else { [double]::MaxValue }
        $show = Get-ChatOverlayControlsShown ([bool]$H.ControlsShown) $onPanel $onCtl ([bool]$H.Dragging) $down $rested $since
        if ($show -ne [bool]$H.ControlsShown) { Show-ChatOverlayControls $H $show }
        # the grip's own drag places them as it goes; the unlocked panel's
        # DragMove does not
        elseif ($show -and -not $H.GripDrag) { Set-ChatOverlayControlsPlacement $H }
        if ($null -ne $H.PendingOpacity -and -not $down -and ($now - $H.PendingAt).TotalMilliseconds -ge 700) {
            $v = $H.PendingOpacity
            $H.PendingOpacity = $null
            if ($v -ne $H.Ctx.Config.opacity) { Save-ChatOverlaySetting $H @{ opacity = $v } }
        }
        Update-ChatOverlaySpin $H
        Update-ChatOverlayChip $H $m $down $now $onPanel
    }
    catch { Write-ChatOverlayLog "hover: $($_.Exception.Message)" }
}

function Test-ChatOverlayRowOpenable {
    # a row the open chip can show: a Claude chat, by its id, in a folder
    # its window can be found by. Pure.
    param($Row)
    if (-not $Row) { return $false }
    return ([string](Get-ChatField $Row 'provider') -eq 'claude' -and
        [string](Get-ChatField $Row 'sessionId') -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' -and
        [bool][string](Get-ChatField $Row 'cwd'))
}

function Get-ChatOverlayChipTarget {
    <#
    Which row the open chip shows for, from the pointer: '' for none. Not on
    first contact - a pointer crossing the click-through panel on its way to
    what is under it would find a chip in its path - but after it rested on a
    row 1 s from moving onto it (-RestedMs), with no button held, and once per
    visit to a row (-Spent: the row it last showed for, until the pointer
    leaves it). Shown, it stays while the pointer is on it or its row, and
    300 ms after, so crossing to it loses nothing; another row hides it at
    once. -Blocked: collapsed or mid-drag. Pure, for the tests.
    #>
    param([string]$Shown, [string]$Under, [double]$RestedMs, [bool]$OnChip, [double]$SinceOverMs,
        [bool]$Down, [bool]$Blocked, [string]$Spent)
    if ($Blocked) { return '' }
    if ($Shown) {
        if ($OnChip -or $Under -eq $Shown) { return $Shown }
        if ($Under) { return '' }
        if ($SinceOverMs -lt 300) { return $Shown }
        return ''
    }
    if ($Under -and $Under -ne $Spent -and -not $Down -and $RestedMs -ge 1000) { return $Under }
    return ''
}

function Step-ChatOverlayChipState {
    <#
    One pointer check's bookkeeping for the chip, on $S (the host state, or
    any hashtable with its Chip* keys): the row under the pointer and since
    when it rested there, the last time it was over the chip or its row, the
    row a chip already showed for, and whether a click on the chip counts.
    The rest starts only when the pointer moves onto a row: rows redrawn
    under a pointer that sits still start nothing. A click counts only once
    the pointer has been seen off the chip since it appeared, so a pointer
    parked where the chip comes up never opens anything with its next click.
    Pure but for $S.
    #>
    param($S, [string]$Under, [string]$Pos, [bool]$OnChip, [datetime]$Now)
    $moved = $Pos -ne [string]$S.ChipLastPos
    if ($Under -ne [string]$S.ChipUnder) {
        $S.ChipUnder = $Under
        $S.ChipUnderAt = if ($Under -and $moved) { $Now } else { $null }
    }
    elseif ($Under -and -not $S.ChipUnderAt -and $moved) { $S.ChipUnderAt = $Now }
    $S.ChipLastPos = $Pos
    if ($S.ChipKey -and ($OnChip -or $Under -eq $S.ChipKey)) { $S.ChipOverAt = $Now }
    if ($S.ChipSpent -and $Under -ne $S.ChipSpent) { $S.ChipSpent = $null }
    if ($S.ChipKey -and -not $OnChip) { $S.ChipArmed = $true }
}

function Get-ChatOverlayRowRects {
    # Each drawn row's rect, and its first line's, in screen pixels: what the
    # pointer is matched against. Only while the pointer is on the panel or
    # the chip; a row not laid out yet is left out.
    param($H)
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not $H.Stack) { return $out.ToArray() }
    foreach ($w in @($H.Stack.Children)) {
        $row = $w.Tag
        if (-not $row -or $row -is [string] -or -not (Get-ChatField $row 'key')) { continue }
        try {
            $line = @($w.Children | Where-Object { $_.Tag -eq 'line' }) | Select-Object -First 1
            if (-not $line) { $line = $w }
            $rect = {
                param($el)
                $a = $el.PointToScreen([System.Windows.Point]::new(0, 0))
                $b = $el.PointToScreen([System.Windows.Point]::new($el.ActualWidth, $el.ActualHeight))
                @([int][Math]::Round($a.X), [int][Math]::Round($a.Y), [int][Math]::Round($b.X - $a.X), [int][Math]::Round($b.Y - $a.Y))
            }
            $out.Add([pscustomobject]@{ Key = [string]$row.key; Row = $row; Rect = (& $rect $w); Line = (& $rect $line) })
        }
        catch {}
    }
    return $out.ToArray()
}

function Find-ChatOverlayRowAt {
    # the row whose rect holds the point, or $null. Pure.
    param($At, [object[]]$Rects)
    foreach ($r in @($Rects)) { if ($r -and (Test-ChatOverlayPointerIn $At $r.Rect)) { return $r } }
    return $null
}

function Get-ChatOverlayChipPlacement {
    # The chip flush with its row's right end, centred on the row's first
    # line, kept on the screen; all in screen pixels (-Line a rect, -Size
    # width and height). Pure, for the tests.
    param([int[]]$Line, [int[]]$Size, $Screen)
    $x = $Line[0] + $Line[2] - $Size[0]
    $y = $Line[1] + [int][Math]::Round(($Line[3] - $Size[1]) / 2.0)
    $x = [Math]::Max($Screen.X, [Math]::Min($x, $Screen.X + $Screen.Width - $Size[0]))
    $y = [Math]::Max($Screen.Y, [Math]::Min($y, $Screen.Y + $Screen.Height - $Size[1]))
    return [pscustomobject]@{ X = [int]$x; Y = [int]$y }
}

function New-ChatOverlayChipWindow {
    <#
    The open chip: a small window of its own, like the controls', over the
    right end of the row the pointer rests on. The panel stays click-through
    everywhere else. Never takes focus, and is in neither Alt+Tab nor the
    taskbar - the controls window's styles.
    #>
    param($H)
    $c = [System.Windows.Window]::new()
    $c.Title = 'chatoverlay open'
    $c.WindowStyle = [System.Windows.WindowStyle]::None
    $c.AllowsTransparency = $true
    $c.Background = [System.Windows.Media.Brushes]::Transparent
    $c.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $c.Topmost = $true
    $c.ShowActivated = $false
    # true for the same reason as the panel's: false means a hidden owner
    # that is not topmost
    $c.ShowInTaskbar = $true
    $c.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $c.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $c.Left = -32000
    $c.Top = -32000
    $c.FontFamily = $H.Win.FontFamily
    $c.FontSize = 12
    $H.ChipWin = $c
    New-ChatOverlayChipContent $H
    $H.ChipHwnd = [System.Windows.Interop.WindowInteropHelper]::new($c).EnsureHandle()
    [ChatOverlayNative]::ApplyExStyle($H.ChipHwnd, $false)
}

function New-ChatOverlayChipContent {
    # the chip's face, made anew when the look changes
    param($H)
    $b = [System.Windows.Controls.Border]::new()
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $b.Background = Get-ChatOverlayBrush 'panel'
    $b.BorderBrush = Get-ChatOverlayBrush 'edge'
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $b.Padding = [System.Windows.Thickness]::new(7, 1, 7, 2)
    $b.ToolTip = 'Show this chat up to date in its VS Code window. Ends the chat''s idle process, and any background shell it runs.'
    $busy = [bool]$H.OpenProc
    $t = New-ChatOverlayText $(if ($busy) { 'opening' } else { 'open' }) $(if ($busy) { 'dim' } else { 'text' }) 11
    $b.Child = $t
    $b.add_MouseEnter({ param($s, $e) $s.Background = Get-ChatOverlayBrush 'hover' })
    $b.add_MouseLeave({ param($s, $e) $s.Background = Get-ChatOverlayBrush 'panel' })
    # a press counts only once the chip is armed (Step-ChatOverlayChipState)
    $b.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $script:ChatOverlayHost.ChipPressed = [bool]$script:ChatOverlayHost.ChipArmed })
    $b.add_MouseLeftButtonUp({
            param($s, $e)
            $e.Handled = $true
            $X = $script:ChatOverlayHost
            if ($X.ChipPressed) { $X.ChipPressed = $false; Invoke-ChatOverlayOpen $X $X.ChipRow }
        })
    $H.ChipText = $t
    $H.ChipWin.Content = $b
}

function Set-ChatOverlayChipPlacement {
    # over its row's right end, wherever that row is drawn now
    param($H)
    if (-not $H.ChipWin -or $H.ChipHwnd -eq [IntPtr]::Zero -or -not $H.ChipLine) { return }
    $p = [ChatOverlayNative]::GetRect($H.Hwnd)
    if (-not $p) { return }
    $px = $p[2] / [Math]::Max(1.0, [double]$H.Win.ActualWidth)
    if ($H.ChipWin.IsVisible) { $c = [ChatOverlayNative]::GetRect($H.ChipHwnd); $size = @($c[2], $c[3]) }
    else {
        $H.ChipWin.Content.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $d = $H.ChipWin.Content.DesiredSize
        $size = @([int][Math]::Ceiling($d.Width * $px), [int][Math]::Ceiling($d.Height * $px))
    }
    $l = [int[]]$H.ChipLine
    $a = if ($script:ChatOverlayWorkAreaSeam) { & $script:ChatOverlayWorkAreaSeam $l }
    else { [System.Windows.Forms.Screen]::FromRectangle([System.Drawing.Rectangle]::new($l[0], $l[1], [Math]::Max(1, $l[2]), [Math]::Max(1, $l[3]))).WorkingArea }
    $at = Get-ChatOverlayChipPlacement $l $size ([pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height })
    [ChatOverlayNative]::MoveTo($H.ChipHwnd, $at.X, $at.Y)
}

function Show-ChatOverlayChip {
    # for one row (an entry of Get-ChatOverlayRowRects); placed before it
    # shows, so it never flashes where it last was, and armed only when the
    # pointer is not already on it
    param($H, $Entry, $At = $null)
    if (-not $H.ChipWin -or -not $Entry) { return }
    $H.ChipKey = [string]$Entry.Key
    $H.ChipRow = $Entry.Row
    $H.ChipLine = $Entry.Line
    $H.ChipAt = Get-Date
    $H.ChipOverAt = $H.ChipAt
    $H.ChipSpent = $H.ChipKey
    $H.ChipPressed = $false
    Set-ChatOverlayChipPlacement $H
    $H.ChipWin.Show()
    # WPF sets WS_EX_APPWINDOW again as it shows a window
    [ChatOverlayNative]::ApplyExStyle($H.ChipHwnd, $false)
    [ChatOverlayNative]::KeepTopmost($H.ChipHwnd)
    Set-ChatOverlayChipPlacement $H
    $H.ChipArmed = -not ($At -and (Test-ChatOverlayPointerIn $At ([ChatOverlayNative]::GetRect($H.ChipHwnd))))
}

function Hide-ChatOverlayChip {
    param($H)
    if (-not $H) { return }
    if ($H.ChipWin) { try { $H.ChipWin.Hide() } catch {} }
    $H.ChipKey = $null
    $H.ChipRow = $null
    $H.ChipArmed = $false
    $H.ChipPressed = $false
}

function Update-ChatOverlayChip {
    # Every pointer check, after the controls': the chip over a Claude row
    # the pointer rests on (Get-ChatOverlayChipTarget), following its row,
    # gone when the pointer is. The pointer is only read.
    param($H, $At, [bool]$Down, [datetime]$Now, [bool]$OnPanel)
    if (-not $H.ChipWin) { return }
    $blocked = [bool]($H.Collapsed -or $H.Dragging -or $H.GripDrag)
    $onChip = [bool]$H.ChipKey -and (Test-ChatOverlayPointerIn $At ([ChatOverlayNative]::GetRect($H.ChipHwnd)))
    $entry = $null
    if (($OnPanel -or $onChip) -and -not $blocked) {
        $entry = Find-ChatOverlayRowAt $At @(Get-ChatOverlayRowRects $H)
        if ($entry -and -not (Test-ChatOverlayRowOpenable $entry.Row)) { $entry = $null }
    }
    $under = if ($entry) { [string]$entry.Key } else { '' }
    Step-ChatOverlayChipState $H $under "$($At.X),$($At.Y)" $onChip $Now
    $rested = if ($H.ChipUnderAt) { ($Now - $H.ChipUnderAt).TotalMilliseconds } else { 0 }
    $since = if ($H.ChipOverAt) { ($Now - $H.ChipOverAt).TotalMilliseconds } else { [double]::MaxValue }
    $target = Get-ChatOverlayChipTarget ([string]$H.ChipKey) $under $rested $onChip $since $Down $blocked ([string]$H.ChipSpent)
    if (-not $target) { if ($H.ChipKey) { Hide-ChatOverlayChip $H }; return }
    if ($target -ne $H.ChipKey) { Show-ChatOverlayChip $H $entry $At; return }
    # the same row: follow it, should it have moved
    if ($entry -and $entry.Key -eq $H.ChipKey) { $H.ChipLine = $entry.Line }
    Set-ChatOverlayChipPlacement $H
}

function Start-ChatShowFreshProcess {
    <#
    Show-ChatFresh for a chip's row in a hidden Windows PowerShell of its
    own, so the window's thread never waits on the registry, CIM or the code
    CLI. Every value goes in single-quoted, quotes doubled - the curly ones
    too - and the title as base64, so nothing a chat is called is ever read
    as code. It exits with Show-ChatFresh's ExitCode.
    #>
    param($H, $Row)
    if (-not (Test-ChatOverlayRowOpenable $Row)) { return $null }
    $path = $script:ChatqScriptPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    $q = { param($s) "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$s) + "'" }
    $pre = '$env:CHATQ_OVERLAY=''1''; '
    foreach ($n in 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'CHAT_CODE_USER', 'CHATQ_CLAUDE', 'CHATQ_CODE') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $pre += "`$env:$n=$(& $q $v); " }
    }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string](Get-ChatField $Row 'title')))
    $home0 = if ($H -and $H.Ctx) { [string]$H.Ctx.ClaudeHome } else { $script:ChatClaudeHome }
    $cmd = $pre + ". $(& $q $path); `$r = @(Show-ChatFresh -Via chip -SessionId $(& $q $Row.sessionId) -Cwd $(& $q $Row.cwd) " +
    "-TitleB64 $(& $q $b64) -ConfigDir $(& $q $home0))[-1]; exit [int]`$r.ExitCode"
    if ($script:ChatShowSpawnSeam) { return (& $script:ChatShowSpawnSeam $cmd) }   # tests
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    $exe = Join-Path $(if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try { return (Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru) }
    catch { Write-ChatOverlayLog "open: $($_.Exception.Message)"; return $null }
}

function Invoke-ChatOverlayOpen {
    # The chip clicked: one open at a time, in a child of its own. No window
    # is activated from here - code -n, in the child, has VS Code raise its own.
    param($H, $Row)
    if (-not $H -or -not $Row -or $H.OpenProc) { return }
    $p = Start-ChatShowFreshProcess $H $Row
    if (-not $p) { return }
    $H.OpenProc = $p
    $H.OpenAt = Get-Date
    if ($H.ChipText) { $H.ChipText.Text = 'opening'; $H.ChipText.Foreground = Get-ChatOverlayBrush 'dim' }
    $sid = [string]$Row.sessionId
    Write-ChatOverlayLog "open: $($sid.Substring(0, [Math]::Min(8, $sid.Length)))"
}

function Get-ChatOverlayOpenBalloon {
    # what the tray says when an open ends, by its child's exit code
    # (Show-ChatFresh); $null says nothing. Pure.
    param([int]$Code)
    switch ($Code) {
        15 { return 'A queued prompt is running in that chat - open it once it finishes.' }
        20 { return 'That chat is open in a terminal - not opened in VS Code as well.' }
        25 { return 'Shown in its window, which also has other folders open - bring it forward yourself.' }
        30 { return 'That chat has not started yet.' }
        40 { return 'Asked its window to show it, but VS Code''s code command was not found, so the window was not brought forward.' }
        41 { return 'code failed - see data/logs/watcher.log.' }
    }
    return $null
}

function Update-ChatOverlayOpen {
    # every tick while an open runs: when its child is done, say how it went,
    # and put the chip back; after 60 s stop waiting for it
    param($H)
    $p = $H.OpenProc
    if (-not $p) { return }
    $ended = try { $p.HasExited } catch { $true }
    if (-not $ended -and ((Get-Date) - $H.OpenAt).TotalSeconds -lt 60) { return }
    if ($ended) {
        $code = try { [int]$p.ExitCode } catch { -1 }
        if ($code -ne 0) { Write-ChatOverlayLog "open: ended $code" }
        $say = Get-ChatOverlayOpenBalloon $code
        if ($say -and $H.Tray) { $H.Tray.ShowBalloonTip(6000, 'chatoverlay', $say, [System.Windows.Forms.ToolTipIcon]::None) }
    }
    else { Write-ChatOverlayLog 'open: no answer after 60 s - stopped waiting' }
    $H.OpenProc = $null
    if ($H.ChipText) { $H.ChipText.Text = 'open'; $H.ChipText.Foreground = Get-ChatOverlayBrush 'text' }
    Hide-ChatOverlayChip $H
}

function Add-ChatOverlayUsage {
    # The bars: a row per usage window - window, a bar in the server's colour
    # for it, the percent, and a reset countdown that ticks every second -
    # and beside them the provider's name with, under it, when its figure is
    # from (Get-ChatOverlayUsageStatus): what took rows of its own under the
    # bars before.
    param($H, $Panel, $Usage)
    $ws = @($Usage.windows)
    $g = [System.Windows.Controls.Grid]::new()
    $g.Margin = [System.Windows.Thickness]::new(0, 1, 0, 3)
    foreach ($cw in 92, 62, 0, 38, 66) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($cw) { [System.Windows.GridLength]::new($cw) } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $g.ColumnDefinitions.Add($cd)
    }
    foreach ($w in $ws) { $g.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) }
    $tone = if ($Usage.stale) { 'faint' } else { 'text' }
    $who = [System.Windows.Controls.StackPanel]::new()
    [void]$who.Children.Add((New-ChatOverlayText ([string]$Usage.provider) $tone -Bold))
    if ($Usage.status) { [void]$who.Children.Add((New-ChatOverlayText ([string]$Usage.status) 'faint' 10.5 -Trim)) }
    [System.Windows.Controls.Grid]::SetRowSpan($who, [Math]::Max(1, $ws.Count))
    [void]$g.Children.Add($who)
    $row = 0
    foreach ($w in $ws) {
        $cells = @((New-ChatOverlayText $w.label 'dim' -Trim))
        $pct = [Math]::Max(0.0, [Math]::Min(100.0, [double]$w.percent))
        $bar = [System.Windows.Controls.Grid]::new()
        $bar.Height = 5
        $bar.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $bar.Margin = [System.Windows.Thickness]::new(2, 1, 8, 0)
        foreach ($share in $pct, (100 - $pct)) {
            $cd = [System.Windows.Controls.ColumnDefinition]::new()
            $cd.Width = [System.Windows.GridLength]::new($share, [System.Windows.GridUnitType]::Star)
            $bar.ColumnDefinitions.Add($cd)
        }
        $track = [System.Windows.Controls.Border]::new()
        $track.CornerRadius = [System.Windows.CornerRadius]::new(2.5)
        $track.Background = Get-ChatOverlayBrush 'track'
        [System.Windows.Controls.Grid]::SetColumnSpan($track, 2)
        $fill = [System.Windows.Controls.Border]::new()
        $fill.CornerRadius = [System.Windows.CornerRadius]::new(2.5)
        $fill.Background = Get-ChatOverlayBrush $(if ($Usage.stale) { 'faint' } else { [string]$w.severity })
        [void]$bar.Children.Add($track)
        [void]$bar.Children.Add($fill)
        $cells += $bar
        $p = New-ChatOverlayText "$($w.percent)%" $(if ($w.limited) { 'critical' } else { $tone }) -Bold
        $p.TextAlignment = [System.Windows.TextAlignment]::Right
        $cells += $p
        $r = New-ChatOverlayText (Format-ChatOverlayReset $w.resetsAt) 'dim' 11
        $r.TextAlignment = [System.Windows.TextAlignment]::Right
        $r.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cells += $r
        if ($w.resetsAt) { $H.Clocks.Add(@{ Block = $r; At = $w.resetsAt }) }
        for ($i = 0; $i -lt $cells.Count; $i++) {
            [System.Windows.Controls.Grid]::SetColumn($cells[$i], $i + 1)
            [System.Windows.Controls.Grid]::SetRow($cells[$i], $row)
            [void]$g.Children.Add($cells[$i])
        }
        $row++
    }
    [void]$Panel.Children.Add($g)
}

function Add-ChatOverlayUsageLine {
    # Usage as one line a provider, as the collapsed panel has it: the name,
    # each window and its percent - in the server's colour for it, now there
    # is no bar to carry that - and at the end when the figure is from.
    param($Panel, $Usage)
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.LastChildFill = $true
    $line.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
    $tone = if ($Usage.stale) { 'faint' } else { 'text' }
    $name = New-ChatOverlayText ([string]$Usage.provider) $tone -Bold
    $name.Width = 56
    [System.Windows.Controls.DockPanel]::SetDock($name, [System.Windows.Controls.Dock]::Left)
    $end = New-ChatOverlayText ([string]$Usage.status) 'faint' 11
    $end.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $end.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($end, [System.Windows.Controls.Dock]::Right)
    $mid = [System.Windows.Controls.TextBlock]::new()
    $mid.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $first = $true
    foreach ($w in @($Usage.windows)) {
        if (-not $first) { $sep = [System.Windows.Documents.Run]::new(" $($script:ChatqDot) "); $sep.Foreground = Get-ChatOverlayBrush 'faint'; $mid.Inlines.Add($sep) }
        $first = $false
        $l = [System.Windows.Documents.Run]::new("$($w.label) ")
        $l.Foreground = Get-ChatOverlayBrush 'dim'
        $mid.Inlines.Add($l)
        $p = [System.Windows.Documents.Run]::new("$($w.percent)%")
        $p.FontWeight = [System.Windows.FontWeights]::SemiBold
        # normal reads as plain text; only warning and worse take a colour
        $p.Foreground = Get-ChatOverlayBrush $(if ($Usage.stale) { 'faint' } elseif ($w.limited) { 'critical' } elseif ($w.severity -in 'warning', 'critical') { [string]$w.severity } else { 'text' })
        $mid.Inlines.Add($p)
    }
    [void]$line.Children.Add($name)
    [void]$line.Children.Add($end)
    [void]$line.Children.Add($mid)
    [void]$Panel.Children.Add($line)
}

function Add-ChatOverlayRow {
    # a dot in the state's colour, project and title, what it is doing at the
    # right, and its newest prompt beneath
    param($Panel, $Row, $Cfg)
    $wrap = [System.Windows.Controls.StackPanel]::new()
    $wrap.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
    # the row it draws, for the open chip to find under the pointer
    $wrap.Tag = $Row
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.Tag = 'line'
    $line.LastChildFill = $true
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 8
    $dot.Height = 8
    $dot.Margin = [System.Windows.Thickness]::new(0, 1, 7, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $c = Get-ChatOverlayBrush ([string]$Row.status)
    if ($Row.status -eq 'queued') { $dot.Stroke = $c; $dot.StrokeThickness = 1.5 } else { $dot.Fill = $c }
    [System.Windows.Controls.DockPanel]::SetDock($dot, [System.Windows.Controls.Dock]::Left)
    $right = New-ChatOverlayText ([string]$Row.stateText) $(if ($Row.rank -eq 0) { 'warn' } else { 'dim' }) 11
    $right.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $right.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($right, [System.Windows.Controls.Dock]::Right)
    $main = [System.Windows.Controls.TextBlock]::new()
    $main.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    if ($Row.project) {
        $run = [System.Windows.Documents.Run]::new([string]$Row.project + '  ')
        $run.Foreground = Get-ChatOverlayBrush 'project'
        $run.FontWeight = [System.Windows.FontWeights]::SemiBold
        $main.Inlines.Add($run)
    }
    $run = [System.Windows.Documents.Run]::new([string]$Row.title)
    $run.Foreground = Get-ChatOverlayBrush 'text'
    $main.Inlines.Add($run)
    [void]$line.Children.Add($dot)
    [void]$line.Children.Add($right)
    [void]$line.Children.Add($main)
    [void]$wrap.Children.Add($line)
    if ($Cfg.prompts -and $Row.prompt) {
        $p = New-ChatOverlayText ([string]$Row.prompt) 'dim' 11 -Trim
        $p.Margin = [System.Windows.Thickness]::new(15, 1, 0, 0)
        [void]$wrap.Children.Add($p)
    }
    [void]$Panel.Children.Add($wrap)
}

function Update-ChatOverlayView {
    <#
    Redraw the panel from a snapshot, but only when what it shows changed -
    the rows carry their ages, so at least once a minute. In between, only
    the reset countdowns move.
    #>
    param($H, $Snap)
    $H.Snap = $Snap
    $key = "$($H.Ctx.ViewSig)|$($H.Locked)|$($H.Ctx.Config.width)|$($H.Ctx.Config.prompts)|$($H.Collapsed)"
    if ($key -eq $H.ViewKey) { Update-ChatOverlayClock $H; return }
    $H.ViewKey = $key
    $cfg = $H.Ctx.Config
    $P = $H.Stack
    $P.Children.Clear()
    $H.Clocks = [System.Collections.Generic.List[object]]::new()
    if ($H.Collapsed) { Hide-ChatOverlayChip $H; Add-ChatOverlayCompact $P $Snap; Add-ChatOverlayUnlockedHint $H $P; return }
    foreach ($u in @($Snap.header.usage)) {
        if (-not $u) { continue }
        if ($cfg.usageView -eq 'bars') { Add-ChatOverlayUsage $H $P $u } else { Add-ChatOverlayUsageLine $P $u }
    }
    foreach ($n in @($Snap.header.notes)) {
        if (-not $n) { continue }
        $t = New-ChatOverlayText ([string]$n.text) $(if ($n.tone -eq 'dim') { 'faint' } else { [string]$n.tone }) 11 -Trim
        $t.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$P.Children.Add($t)
    }
    $rows = @($Snap.rows)
    if (@($Snap.header.usage).Count -or @($Snap.header.notes).Count) {
        $sep = [System.Windows.Controls.Border]::new()
        $sep.Height = 1
        $sep.Background = Get-ChatOverlayBrush 'edge'
        $sep.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
        [void]$P.Children.Add($sep)
    }
    $shown = @($rows | Select-Object -First $cfg.maxRows)
    foreach ($r in $shown) { Add-ChatOverlayRow $P $r $cfg }
    # the chip goes with its row; one still drawn keeps the row's new data
    if ($H.ChipKey) {
        $still = @($shown | Where-Object { $_ -and [string]$_.key -eq $H.ChipKey }) | Select-Object -First 1
        if ($still) { $H.ChipRow = $still } else { Hide-ChatOverlayChip $H }
    }
    if ($rows.Count -gt $shown.Count) {
        $rest = @($rows | Select-Object -Skip $shown.Count)
        $bits = @()
        $idle = @($rest | Where-Object { $_.status -eq 'idle' }).Count
        $q = @($rest | Where-Object { $_.status -eq 'queued' }).Count
        if ($idle) { $bits += "$idle idle" }
        if ($q) { $bits += "$q queued" }
        $more = "+$($rest.Count) more" + $(if ($bits) { " $($script:ChatqDot) " + ($bits -join ', ') } else { '' })
        [void]$P.Children.Add((New-ChatOverlayText $more 'faint' 11))
    }
    if (-not $rows) { [void]$P.Children.Add((New-ChatOverlayText 'no chats open' 'faint' 11)) }
    Add-ChatOverlayUnlockedHint $H $P
}

function Add-ChatOverlayUnlockedHint {
    param($H, $Panel)
    if ($H.Locked) { return }
    $keyName = if ($H.Hotkey) { $H.HotkeyText } else { 'the tray menu' }
    $hint = New-ChatOverlayText "unlocked - drag to move $($script:ChatqDot) $keyName locks it" 'unlocked' 11 -Trim
    $hint.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    [void]$Panel.Children.Add($hint)
}

function Add-ChatOverlayCompact {
    # Collapsed: one line - a dot in the most urgent chat's colour, how many
    # chats are in each state, and Claude's usage at the right.
    param($Panel, $Snap)
    $c = $Snap.counts
    $need = [int]$c.waiting + [int]$c.needsInput
    $bits = @()
    $cut = if ($c -and $c.PSObject.Properties['cutOff']) { [int]$c.cutOff } else { 0 }
    if ($need) { $bits += "$need waiting" }
    if ($cut) { $bits += "$cut cut off" }
    if ([int]$c.busy) { $bits += "$([int]$c.busy) working" }
    if ([int]$c.running) { $bits += "$([int]$c.running) running" }
    if ([int]$c.idle) { $bits += "$([int]$c.idle) idle" }
    if ([int]$c.queued) { $bits += "$([int]$c.queued) queued" }
    $state = if ($need) { 'waiting' } elseif ($cut) { 'cutoff' } elseif ([int]$c.busy) { 'busy' } elseif ([int]$c.running) { 'running' } else { 'idle' }
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.LastChildFill = $true
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 8
    $dot.Height = 8
    $dot.Margin = [System.Windows.Thickness]::new(0, 1, 7, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $dot.Fill = Get-ChatOverlayBrush $state
    [System.Windows.Controls.DockPanel]::SetDock($dot, [System.Windows.Controls.Dock]::Left)
    $u = @($Snap.header.usage | Where-Object { $_ -and $_.provider -eq 'Claude' })[0]
    $use = if ($u) { (@($u.windows | Select-Object -First 2 | ForEach-Object { "$($_.label) $($_.percent)%" }) -join " $($script:ChatqDot) ") } else { '' }
    $right = New-ChatOverlayText $use $(if ($u -and $u.stale) { 'faint' } else { 'dim' }) 11
    $right.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $right.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($right, [System.Windows.Controls.Dock]::Right)
    $main = New-ChatOverlayText $(if ($bits) { $bits -join " $($script:ChatqDot) " } else { 'no chats open' }) 'text' -Trim
    [void]$line.Children.Add($dot)
    [void]$line.Children.Add($right)
    [void]$line.Children.Add($main)
    [void]$Panel.Children.Add($line)
}

function Update-ChatOverlayClock {
    param($H)
    $now = Get-Date
    foreach ($c in @($H.Clocks)) { $c.Block.Text = Format-ChatOverlayReset $c.At $now }
}

function Get-ChatOverlayPlacement {
    <#
    Where the panel goes: where it was left, as long as a 48 x 24 corner of it
    still shows on some screen - a monitor unplugged or a resolution changed
    can leave it nowhere - and otherwise the main screen's top-right corner.
    Screens are working areas in physical pixels. Pure, for the tests.
    #>
    param($X, $Y, [int]$Width, [int]$Height, [object[]]$Screens)
    if ($null -ne $X -and $null -ne $Y) {
        foreach ($s in @($Screens)) {
            $vw = [Math]::Min([int]$X + $Width, $s.X + $s.Width) - [Math]::Max([int]$X, $s.X)
            $vh = [Math]::Min([int]$Y + $Height, $s.Y + $s.Height) - [Math]::Max([int]$Y, $s.Y)
            if ($vw -ge 48 -and $vh -ge 24) { return [pscustomobject]@{ X = [int]$X; Y = [int]$Y; Moved = $false } }
        }
    }
    $p = @($Screens | Where-Object { $_.Primary })[0]
    if (-not $p) { $p = @($Screens)[0] }
    if (-not $p) { return [pscustomobject]@{ X = 0; Y = 0; Moved = $true } }
    # room above it for the row of buttons, even at 200%
    return [pscustomobject]@{ X = [int]($p.X + $p.Width - $Width - 16); Y = [int]($p.Y + 56); Moved = $true }
}

function Set-ChatOverlayPlacement {
    param($H, [switch]$Corner)
    if ($H.Hwnd -eq [IntPtr]::Zero) { return }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    $wide = if ($r) { $r[2] } else { 380 }
    $tall = if ($r) { [Math]::Max($r[3], 24) } else { 120 }
    $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
            $a = $_.WorkingArea
            [pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height; Primary = $_.Primary }
        })
    $x = if ($Corner) { $null } else { $H.State.x }
    $y = if ($Corner) { $null } else { $H.State.y }
    $p = Get-ChatOverlayPlacement $x $y $wide $tall $screens
    if ($p.Moved -and $null -ne $x) { Write-ChatOverlayLog "moved back onto a screen from $x,$y" }
    [ChatOverlayNative]::MoveTo($H.Hwnd, $p.X, $p.Y)
    $H.Placed = $true
    if ($p.X -ne $H.State.x -or $p.Y -ne $H.State.y) {
        $H.State.x = $p.X
        $H.State.y = $p.Y
        Save-ChatOverlayState $H.State
    }
}

function Invoke-ChatOverlayDrag {
    # Unlocked, a press anywhere on the panel drags it (the grip has its own,
    # Start-ChatOverlayGripDrag). Passes wait meanwhile: DragMove runs its
    # own message loop, and the timer would fire inside it.
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.Locked) { return }
    $H.Dragging = $true
    try { $H.Win.DragMove() } catch {}
    $H.Dragging = $false
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if ($r) { $H.State.x = $r[0]; $H.State.y = $r[1]; Save-ChatOverlayState $H.State }
}

function Set-ChatOverlayLocked {
    # Locked: clicks go through to whatever is under it. Unlocked: it takes the
    # mouse so it can be dragged, shows a blue edge, and locks itself again
    # 2 minutes after the pointer leaves - a forgotten unlock would otherwise
    # go on swallowing clicks over that corner of the screen.
    param($H, [bool]$Locked)
    $H.Locked = $Locked
    Hide-ChatOverlayChip $H
    if ($H.Hwnd -ne [IntPtr]::Zero) { [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $Locked) }
    $H.Frame.BorderBrush = Get-ChatOverlayBrush $(if ($Locked) { 'edge' } else { 'unlocked' })
    $H.PointerIn = $false
    $H.LeftAt = if ($Locked) { $null } else { Get-Date }
    $H.State.locked = $Locked
    Save-ChatOverlayState $H.State
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayHidden {
    param($H, [bool]$Hidden)
    $H.Hidden = $Hidden
    if ($Hidden) {
        $H.Win.Hide()
        Show-ChatOverlayControls $H $false
        # the pointer check stops while hidden, so nothing else would
        Hide-ChatOverlayChip $H
    }
    else {
        $H.Win.Show()
        [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
        # one that started hidden still sits where it was made, off every screen
        if (-not $H.Placed) { Set-ChatOverlayPlacement $H }
        [ChatOverlayNative]::KeepTopmost($H.Hwnd)
    }
    $H.State.hidden = $Hidden
    Save-ChatOverlayState $H.State
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayTrayColor {
    # the tray dot takes the most urgent state's colour; the old icon handle
    # is destroyed, or every change would leak one
    param($H, [string]$Hex)
    if (-not $H.Tray -or $H.IconColor -eq $Hex) { return }
    $bmp = [System.Drawing.Bitmap]::new(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $br = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($Hex))
    $g.FillEllipse($br, 5, 5, 22, 22)
    $br.Dispose()
    $g.Dispose()
    $icon = $bmp.GetHicon()
    $bmp.Dispose()
    $H.Tray.Icon = [System.Drawing.Icon]::FromHandle($icon)
    if ($H.IconHandle -ne [IntPtr]::Zero) { [void][ChatOverlayNative]::DestroyIcon($H.IconHandle) }
    $H.IconHandle = $icon
    $H.IconColor = $Hex
}

function Update-ChatOverlayTray {
    param($H, $Snap)
    if (-not $H.Tray) { return }
    $c = $Snap.counts
    $cut = if ($c -and $c.PSObject.Properties['cutOff']) { [int]$c.cutOff } else { 0 }
    $name = if ([int]$c.waiting + [int]$c.needsInput) { 'waiting' } elseif ($cut) { 'cutoff' } elseif ($c.busy) { 'busy' } elseif ($c.running) { 'running' } else { 'idle' }
    Set-ChatOverlayTrayColor $H $script:ChatOverlayColors[$name]
    $tip = Format-ChatOverlayTooltip $Snap
    if ($H.Tray.Text -ne $tip) { $H.Tray.Text = $tip }
}

function Update-ChatOverlayMenu {
    param($H)
    if (-not $H.Menu.Lock) { return }
    $H.Menu.Lock.Text = if ($H.Locked) { 'Unlock to move' } else { 'Lock' }
    $H.Menu.Hide.Text = if ($H.Hidden) { 'Show' } else { 'Hide' }
    $H.Menu.Fold.Text = if ($H.Collapsed) { 'Expand' } else { 'Collapse to one line' }
    $H.Menu.Hotkey.Text = if ($H.Hotkey) { "hotkey  $($H.HotkeyText)" } elseif ($H.HotkeyText -and $H.HotkeyText -ne 'none') { "hotkey  $($H.HotkeyText) (taken)" } else { 'no hotkey' }
}

function New-ChatOverlayTrayIcon {
    # A dot in the notification area: left click shows or hides the panel,
    # right click has the rest. It is the one way to reach a panel that clicks
    # go through.
    param($H)
    $ni = [System.Windows.Forms.NotifyIcon]::new()
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $open = $menu.Items.Add('Open console')
    $open.Font = [System.Drawing.Font]::new($open.Font, [System.Drawing.FontStyle]::Bold)
    $open.add_Click({ Invoke-ChatOverlayVerb 'console' })
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $head = $menu.Items.Add("VS-code-chat-manager $script:ChatVersion")
    $head.Enabled = $false
    $H.Menu.Hotkey = $menu.Items.Add('hotkey')
    $H.Menu.Hotkey.Enabled = $false
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $H.Menu.Lock = $menu.Items.Add('Unlock to move')
    $H.Menu.Lock.add_Click({ Invoke-ChatOverlayVerb 'toggle' })
    $H.Menu.Hide = $menu.Items.Add('Hide')
    $H.Menu.Hide.add_Click({ Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Hidden) { 'show' } else { 'hide' }) })
    $H.Menu.Fold = $menu.Items.Add('Collapse to one line')
    $H.Menu.Fold.add_Click({ Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Collapsed) { 'expand' } else { 'collapse' }) })
    $again = $menu.Items.Add('Refresh usage')
    $again.add_Click({ Invoke-ChatOverlayRefresh })
    $corner = $menu.Items.Add('Move to top right')
    $corner.add_Click({ Invoke-ChatOverlayVerb 'reset' })
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $quit = $menu.Items.Add('Quit')
    $quit.add_Click({ Invoke-ChatOverlayVerb 'stop' })
    $ni.ContextMenuStrip = $menu
    $ni.add_MouseClick({
            param($s, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Hidden) { 'show' } else { 'hide' })
            }
        })
    $ni.Text = 'chatq'
    $H.Tray = $ni
    Set-ChatOverlayTrayColor $H $script:ChatOverlayColors.idle
    $ni.Visible = $true
    Update-ChatOverlayMenu $H
}

function Register-ChatOverlayHotkey {
    # config hotkey (Ctrl+Alt+Shift+O): shows a hidden panel, else locks or
    # unlocks it. Another program holding the same keys gets one balloon.
    param($H)
    $text = [string]$H.Ctx.Config.hotkey
    if ($H.Hotkey -and $H.HotkeyText -eq $text) { return }
    if ($H.Hotkey) { $H.Hotkey.Dispose(); $H.Hotkey = $null }
    $H.HotkeyText = $text
    $k = try { ConvertFrom-ChatOverlayHotkey $text } catch { Write-ChatOverlayLog "hotkey: $($_.Exception.Message)"; $null }
    if ($k) {
        $hk = [ChatOverlayHotkey]::new()
        $hk.add_Pressed({ Invoke-ChatOverlayVerb 'hotkey' })
        if ($hk.Register([uint32]$k.Mods, [uint32]$k.Vk)) { $H.Hotkey = $hk }
        else {
            $hk.Dispose()
            Write-ChatOverlayLog "hotkey $text is taken by another program"
            if ($H.Tray) { $H.Tray.ShowBalloonTip(8000, 'chatoverlay', "$text is taken by another program - chatoverlay -Hotkey picks another", [System.Windows.Forms.ToolTipIcon]::Info) }
        }
    }
    Update-ChatOverlayMenu $H
}

function Invoke-ChatOverlayVerb {
    # what a command, the tray menu or the hotkey asked for
    param([string]$Verb)
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    switch ($Verb) {
        'stop' { $H.Stop = $true; Stop-ChatOverlayDispatcher $H }
        'restart' { $H.Restart = $true; Stop-ChatOverlayDispatcher $H }
        'reload' {
            $H.Ctx.Config = Get-ChatOverlayConfig
            $H.Win.Width = $H.Ctx.Config.width
            $H.Win.Opacity = $H.Ctx.Config.opacity
            Register-ChatOverlayHotkey $H
            Register-ChatConsoleHotkey $H
            $H.ViewKey = $null
            # made anew, so the settings box shows what a shell just set
            $H.ThemeName = $null
            Update-ChatOverlayTheme $H
        }
        'lock' { Set-ChatOverlayLocked $H $true }
        'unlock' { Set-ChatOverlayLocked $H $false }
        'toggle' { Set-ChatOverlayLocked $H (-not $H.Locked) }
        'show' { if ($H.Hidden) { Set-ChatOverlayHidden $H $false } }
        'hide' { if (-not $H.Hidden) { Set-ChatOverlayHidden $H $true } }
        'reset' { Set-ChatOverlayPlacement $H -Corner }
        'hotkey' { if ($H.Hidden) { Set-ChatOverlayHidden $H $false } else { Set-ChatOverlayLocked $H (-not $H.Locked) } }
        'collapse' { if (-not $H.Collapsed) { Set-ChatOverlayCollapsed $H $true } }
        'expand' { if ($H.Collapsed) { Set-ChatOverlayCollapsed $H $false } }
        'console' { Show-ChatConsole $H -Activate }
    }
}

function Stop-ChatOverlayDispatcher {
    param($H)
    if ($H.ShuttingDown) { return }
    $H.ShuttingDown = $true
    if ($H.Timer) { $H.Timer.Stop() }
    if ($H.HoverTimer) { $H.HoverTimer.Stop() }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Background)
}

function Invoke-ChatOverlayTick {
    # The 1 s timer. Every other tick is a collector pass; the ones between
    # only move the countdowns. Every 5th puts the panel back on top and moves
    # it back onto a screen if the screens changed under it.
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.ShuttingDown) { return }
    try {
        $H.Tick++
        # a key just pressed in the console puts the pass off a tick - twice
        # at most - so typing there never waits behind one
        $C = $H.Con
        $typing = $C -and $C.TypedAt -and ((Get-Date) - $C.TypedAt).TotalMilliseconds -lt 400 -and $C.Skips -lt 2
        if ($H.Tick % 2 -eq 0 -and $typing) { $C.Skips++; $H.Tick-- }
        elseif ($H.Tick % 2 -eq 0 -and -not $H.Dragging) {
            if ($C) { $C.Skips = 0 }
            $snap = Invoke-ChatOverlayCycle $H.Ctx
            foreach ($v in @($H.Ctx.Verbs)) { Invoke-ChatOverlayVerb $v }
            if ($H.ShuttingDown) { return }
            Update-ChatOverlayView $H $snap
            Update-ChatOverlayTray $H $snap
            if ($C -and $C.Win.IsVisible) { Update-ChatConsole $H }
        }
        else {
            Update-ChatOverlayClock $H
            # a dropped file's copy may have finished
            if ($C -and $C.Win.IsVisible) { Update-ChatConsoleStaging $H }
        }
        if ($H.Tick % 5 -eq 0 -and -not $H.Hidden) {
            # system: follows Windows' own light or dark setting
            if ($H.Ctx.Config.theme -eq 'system') { Update-ChatOverlayTheme $H }
            [ChatOverlayNative]::KeepTopmost($H.Hwnd)
            if ($H.ControlsShown) { [ChatOverlayNative]::KeepTopmost($H.CtlHwnd) }
            # the chip after the panel, so it stays over its row
            if ($H.ChipKey -and $H.ChipHwnd -ne [IntPtr]::Zero) { [ChatOverlayNative]::KeepTopmost($H.ChipHwnd) }
            $sig = (@([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.WorkingArea)" }) -join ';')
            if ($sig -ne $H.ScreenSig) {
                if ($H.ScreenSig) { Set-ChatOverlayPlacement $H }
                $H.ScreenSig = $sig
            }
        }
        if (-not $H.Locked -and -not $H.PointerIn -and $H.LeftAt -and ((Get-Date) - $H.LeftAt).TotalSeconds -ge 120) {
            Set-ChatOverlayLocked $H $true
        }
        # an open the chip started may have finished
        if ($H.OpenProc) { Update-ChatOverlayOpen $H }
    }
    catch { Write-ChatOverlayLog "tick: $($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])" }
}

function Lock-ChatOverlay {
    # A few tries, not one: an overlay handing over to a newer copy lets go
    # of the lock only as it exits.
    for ($try = 1; $try -le 5; $try++) {
        $l = try { [System.IO.File]::Open($script:ChatOverlayLockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { $null }
        if ($l) { return $l }
        if ($try -lt 5) { Start-Sleep -Milliseconds 200 }
    }
    return $null
}

function Close-ChatOverlayWindow {
    # everything the panel holds from the OS goes back, whatever ended it
    param($H)
    try { if ($H.Timer) { $H.Timer.Stop() } } catch {}
    try { if ($H.HoverTimer) { $H.HoverTimer.Stop() } } catch {}
    try { if ($H.Hotkey) { $H.Hotkey.Dispose(); $H.Hotkey = $null } } catch {}
    try { if ($H.ConHotkey) { $H.ConHotkey.Dispose(); $H.ConHotkey = $null } } catch {}
    # the console's draft kept, then the window closed for good
    $H.ShuttingDown = $true
    try { if ($H.Con) { Save-ChatConsoleDraft $H; $H.Con.Win.Close() } } catch {}
    try { if ($H.Tray) { $H.Tray.Visible = $false; $H.Tray.Dispose(); $H.Tray = $null } } catch {}
    try { if ($H.IconHandle -ne [IntPtr]::Zero) { [void][ChatOverlayNative]::DestroyIcon($H.IconHandle); $H.IconHandle = [IntPtr]::Zero } } catch {}
    try { if ($H.CtlWin) { $H.CtlWin.Close() } } catch {}
    try { if ($H.ChipWin) { $H.ChipWin.Close() } } catch {}
    try { if ($H.Win) { $H.Win.Close() } } catch {}
}

function New-ChatOverlayHostState {
    @{
        Tick = 0; Ctx = $null; Win = $null; Hwnd = [IntPtr]::Zero; Frame = $null; Stack = $null
        State = $null; Locked = $true; Hidden = $false; Collapsed = $false; Dragging = $false; PointerIn = $false; LeftAt = $null
        CtlWin = $null; CtlHwnd = [IntPtr]::Zero; CtlStack = $null; CtlSide = 'above'; CtlButtons = @(); CtlLine = $null; GripDrag = $null; Spin = $null; Spinning = $false
        Placed = $false; EnterAt = $null
        Controls = $null; Settings = $null; ControlsShown = $false; SettingsOpen = $false; OverAt = $null
        HoverTimer = $null; PendingOpacity = $null; PendingAt = $null; OpacityText = $null; ThemeName = $null; HideTold = $false
        Tray = $null; IconHandle = [IntPtr]::Zero; IconColor = $null; Hotkey = $null; HotkeyText = $null
        Timer = $null; ViewKey = $null; Clocks = [System.Collections.Generic.List[object]]::new(); Snap = $null
        ScreenSig = $null; Stop = $false; Restart = $false; ShuttingDown = $false; Menu = @{}
        Con = $null; ConHotkey = $null; ConHotkeyText = $null
        # the open chip: its window, the row it shows for, and the pointer's
        # rest, arming and leaving (Update-ChatOverlayChip); the child an
        # open runs in (Invoke-ChatOverlayOpen)
        ChipWin = $null; ChipHwnd = [IntPtr]::Zero; ChipText = $null; ChipKey = $null; ChipRow = $null; ChipLine = $null; ChipAt = $null
        ChipUnder = $null; ChipUnderAt = $null; ChipOverAt = $null; ChipLastPos = $null; ChipSpent = $null
        ChipArmed = $false; ChipPressed = $false; OpenProc = $null; OpenAt = $null
    }
}

function Start-ChatOverlayHost {
    <#
    The Windows overlay process: a hidden powershell.exe -STA that draws the
    panel and runs the collector on the same thread, every other tick of a
    1 s timer. One thread is enough - a pass costs tens of milliseconds, and
    nobody clicks a window that clicks go through - and it keeps every
    handler on the thread PowerShell runs on, the only one with a runspace.
    -Open console: chatconsole started it, and the console opens with it.
    #>
    param([string]$Open)
    Set-StrictMode -Off
    if (-not $script:ChatqIsWindows) { Start-ChatOverlayMacHost; return }
    New-ChatqDir $script:ChatqData
    $lock = Lock-ChatOverlay
    if (-not $lock) { Write-ChatOverlayLog "overlay $PID found one already running"; return }
    $H = New-ChatOverlayHostState
    $script:ChatOverlayHost = $H
    try {
        Set-Content -LiteralPath $script:ChatOverlayPidPath -Value $PID -Encoding ASCII
        Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID started ($script:ChatVersion)"
        Initialize-ChatOverlayNative
        $H.Ctx = New-ChatOverlayContext
        Restore-ChatOverlayUsage $H.Ctx
        $H.State = Read-ChatOverlayState
        $H.Locked = [bool]$H.State.locked
        $H.Collapsed = [bool]$H.State.collapsed
        New-ChatOverlayWindow $H
        Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx)
        if (-not $H.State.hidden) {
            $H.Win.Show()
            [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
            Set-ChatOverlayPlacement $H
            [ChatOverlayNative]::KeepTopmost($H.Hwnd)
        }
        else { $H.Hidden = $true }
        if (-not $H.Locked) { Set-ChatOverlayLocked $H $false }
        New-ChatOverlayTrayIcon $H
        Update-ChatOverlayTray $H $H.Snap
        Register-ChatOverlayHotkey $H
        Register-ChatConsoleHotkey $H
        $d = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $d.add_UnhandledException({
                param($s, $e)
                Write-ChatOverlayLog "ui: $($e.Exception.Message)"
                $e.Handled = $true
            })
        $H.Timer = [System.Windows.Threading.DispatcherTimer]::new()
        $H.Timer.Interval = [TimeSpan]::FromSeconds(1)
        $H.Timer.add_Tick({ Invoke-ChatOverlayTick })
        $H.Timer.Start()
        $H.HoverTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $H.HoverTimer.Interval = [TimeSpan]::FromMilliseconds(120)
        $H.HoverTimer.add_Tick({ Update-ChatOverlayHover })
        $H.HoverTimer.Start()
        # what came in while this was starting - a -Stop right after the start,
        # chatinstall's restart - was taken by the first pass above
        foreach ($v in @($H.Ctx.Verbs)) { Invoke-ChatOverlayVerb $v }
        if ($Open -eq 'console') { Show-ChatConsole $H -Activate }
        [System.Windows.Threading.Dispatcher]::Run()
    }
    catch { Write-ChatOverlayLog "overlay failed: $($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])" }
    finally {
        Close-ChatOverlayWindow $H
        try { $lock.Dispose() } catch {}
        Remove-Item -LiteralPath $script:ChatOverlayPidPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID stopped$(if ($H.Restart) { ' - restarting on the new copy' })"
    }
    # last, once the lock is released: the new copy takes it on its way up
    if ($H.Restart) { [void](Start-ChatOverlayProcess) }
}

#endregion
