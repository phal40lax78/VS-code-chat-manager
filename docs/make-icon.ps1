# Draws extension/icon.png, the Marketplace icon: a chat bubble holding a
# short queue, the next one to go in amber, on a dark rounded square. 256 px
# square: the Marketplace wants at least 128 and never an SVG. Run it again
# after changing it:
#
#     powershell -NoProfile -File docs\make-icon.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $root 'extension\icon.png'
$n = 256

function New-RoundRect([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $R
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}
function New-Brush([int]$R, [int]$G, [int]$B) { New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, $R, $G, $B)) }

$bmp = New-Object System.Drawing.Bitmap $n, $n
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillPath((New-Brush 31 41 55), (New-RoundRect 0 0 $n $n 48))
# the bubble, and its tail at the lower left
$paper = New-Brush 245 245 244
$g.FillPath($paper, (New-RoundRect 36 44 184 132 28))
$tail = New-Object System.Drawing.Drawing2D.GraphicsPath
$tail.AddPolygon([System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(70, 168), [System.Drawing.PointF]::new(66, 216), [System.Drawing.PointF]::new(118, 168)))
$g.FillPath($paper, $tail)
# the queue: three lines, the first in amber
$g.FillPath((New-Brush 245 158 11), (New-RoundRect 66 76 124 18 9))
$g.FillPath((New-Brush 107 114 128), (New-RoundRect 66 104 104 18 9))
$g.FillPath((New-Brush 107 114 128), (New-RoundRect 66 132 78 18 9))
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"wrote $out"
