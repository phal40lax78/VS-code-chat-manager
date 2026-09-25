# Makes extension/icon.png, the Marketplace icon, from docs/icon-source.jpg.
# The photo is wider than tall, so it is scaled to the full width and the
# bands above and below are filled with its own background colour - never
# cropped - on a square with rounded corners. 256 px: the Marketplace
# wants at least 128 and never an SVG. Run it again after changing the
# photo:
#
#     powershell -NoProfile -File docs\make-icon.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $root 'docs\icon-source.jpg'
$out = Join-Path $root 'extension\icon.png'
$n = 256
# the photo's background, the median of its rows just inside the dark edge
$fill = [System.Drawing.Color]::FromArgb(255, 19, 10, 30)

$img = [System.Drawing.Image]::FromFile($src)
$scale = [Math]::Min($n / $img.Width, $n / $img.Height)
$w = [int][Math]::Round($img.Width * $scale)
$h = [int][Math]::Round($img.Height * $scale)
$dest = New-Object System.Drawing.Rectangle ([int](($n - $w) / 2)), ([int](($n - $h) / 2)), $w, $h

$bmp = New-Object System.Drawing.Bitmap $n, $n
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear($fill)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
# without it bicubic pulls a faint light fringe in from outside the photo
$attr = New-Object System.Drawing.Imaging.ImageAttributes
$attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
$g.DrawImage($img, $dest, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
# The photo's outermost rows are darker than its background, which a flat
# fill shows as a line at each seam; each band instead shades from the
# background into the colour of the row it meets.
function Get-RowColor([int]$Y) {
    $px = 0..($n - 1) | ForEach-Object { $bmp.GetPixel($_, $Y) }
    $mid = [int]($n / 2)
    [System.Drawing.Color]::FromArgb(255,
        ($px | ForEach-Object R | Sort-Object)[$mid],
        ($px | ForEach-Object G | Sort-Object)[$mid],
        ($px | ForEach-Object B | Sort-Object)[$mid])
}
function Fill-Band([int]$Y, [int]$H, $From, $To) {
    $band = New-Object System.Drawing.Rectangle 0, $Y, $n, $H
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $band, $From, $To, 90
    # stops GDI+ wrapping the far colour back in as a 1 px line at the edge
    $brush.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY
    $g.FillRectangle($brush, $band)
    $brush.Dispose()
}
$g.Flush()
if ($dest.Y -gt 0) {
    Fill-Band 0 $dest.Y $fill (Get-RowColor $dest.Y)
    Fill-Band $dest.Bottom ($n - $dest.Bottom) (Get-RowColor ($dest.Bottom - 1)) $fill
}
$g.Dispose()
$img.Dispose()

# Rounded corners, transparent outside: neither VS Code nor the Marketplace
# rounds an icon itself. The square is painted through a rounded path so
# its edge is antialiased, which clipping would not be.
$d = 2 * 48
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc($n - $d, 0, $d, $d, 270, 90)
$path.AddArc($n - $d, $n - $d, $d, $d, 0, 90)
$path.AddArc(0, $n - $d, $d, $d, 90, 90)
$path.CloseFigure()
$icon = New-Object System.Drawing.Bitmap $n, $n
$g = [System.Drawing.Graphics]::FromImage($icon)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
# else the outermost row and column come out half transparent
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillPath((New-Object System.Drawing.TextureBrush $bmp), $path)
$g.Dispose()
$bmp.Dispose()
$icon.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$icon.Dispose()
"wrote $out"
