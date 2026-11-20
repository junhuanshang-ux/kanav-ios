# Generates the AppIcon PNG set from a procedurally drawn 1024px master.
# Usage: pwsh -File tools/make_icons.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "KanAV\Resources\Assets.xcassets\AppIcon.appiconset"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$master = 2048
$bmp = New-Object System.Drawing.Bitmap($master, $master, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$rect = New-Object System.Drawing.Rectangle(0, 0, $master, $master)
$colTop = [System.Drawing.Color]::FromArgb(255, 255, 51, 102)
$colBottom = [System.Drawing.Color]::FromArgb(255, 26, 6, 24)
$gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $colTop, $colBottom, 65.0)
$g.FillRectangle($gradient, $rect)

# soft vignette
$vignette = New-Object System.Drawing.Drawing2D.GraphicsPath
$vignette.AddEllipse(220, 220, 1608, 1608)
$vBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($vignette)
$vBrush.CenterColor = [System.Drawing.Color]::FromArgb(40, 255, 255, 255)
$vBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
$g.FillPath($vBrush, $vignette)

# play triangle, optically centred
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
$triangle = [System.Drawing.PointF[]]@(
  (New-Object System.Drawing.PointF(790, 660)),
  (New-Object System.Drawing.PointF(790, 1388)),
  (New-Object System.Drawing.PointF(1416, 1024))
)
$g.FillPolygon($white, $triangle)

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
