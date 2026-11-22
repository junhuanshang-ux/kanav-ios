# Generates the AppIcon PNG set from a procedurally drawn 1024px master.
# Podcast-style mark: purple gradient + white dot with three expanding arcs.
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "KanAV\Resources\Assets.xcassets\AppIcon.appiconset"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$master = 2048
$bmp = New-Object System.Drawing.Bitmap($master, $master, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

# 背景：紫罗兰渐变
$rect = New-Object System.Drawing.Rectangle(0, 0, $master, $master)
$colTop = [System.Drawing.Color]::FromArgb(255, 186, 88, 240)
$colBottom = [System.Drawing.Color]::FromArgb(255, 96, 32, 200)
$gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $colTop, $colBottom, 90.0)
$g.FillRectangle($gradient, $rect)

# 轻微径向高光
$vignette = New-Object System.Drawing.Drawing2D.GraphicsPath
$vignette.AddEllipse(300, 240, 1448, 1448)
$vBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($vignette)
$vBrush.CenterColor = [System.Drawing.Color]::FromArgb(46, 255, 255, 255)
$vBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
$g.FillPath($vBrush, $vignette)

# 图形：一个圆点 + 三道向下张开的同心弧
$cx = 1024
$cy = 780
$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)

$dotBrush = New-Object System.Drawing.SolidBrush($white)
$g.FillEllipse($dotBrush, ($cx - 74), ($cy - 74), 148, 148)

$arcs = @(
  @{ Radius = 250; Width = 68 },
  @{ Radius = 432; Width = 68 },
  @{ Radius = 614; Width = 68 }
)
foreach ($arc in $arcs) {
    $r = $arc.Radius
    $pen = New-Object System.Drawing.Pen($white, $arc.Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $bounds = New-Object System.Drawing.Rectangle(($cx - $r), ($cy - $r), (2 * $r), (2 * $r))
    $g.DrawArc($pen, $bounds, 18, 144)
    $pen.Dispose()
}

$g.Dispose()

$sizes = @{
  "icon-20@2x.png"       = 40
  "icon-20@3x.png"       = 60
  "icon-29@2x.png"       = 58
  "icon-29@3x.png"       = 87
  "icon-40@2x.png"       = 80
  "icon-40@3x.png"       = 120
  "icon-60@2x.png"       = 120
  "icon-60@3x.png"       = 180
  "icon-20@1x-ipad.png"  = 20
  "icon-20@2x-ipad.png"  = 40
  "icon-29@1x-ipad.png"  = 29
  "icon-29@2x-ipad.png"  = 58
  "icon-40@1x-ipad.png"  = 40
  "icon-40@2x-ipad.png"  = 80
  "icon-76@1x-ipad.png"  = 76
  "icon-76@2x-ipad.png"  = 152
  "icon-83.5@2x-ipad.png" = 167
  "icon-1024.png"        = 1024
}

foreach ($name in $sizes.Keys) {
    $size = $sizes[$name]
    $dst = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $dg = [System.Drawing.Graphics]::FromImage($dst)
    $dg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $dg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $dg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $dg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $dg.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
    $dg.Dispose()
    $dst.Save((Join-Path $outDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
    Write-Output ("wrote {0} ({1}x{1})" -f $name, $size)
}

$bmp.Dispose()
Write-Output ("done -> " + $outDir)
