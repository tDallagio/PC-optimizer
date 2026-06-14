<#
.SYNOPSIS
    Genera WinBoost.ico — rayo cian sobre fondo oscuro redondeado.
    Resoluciones: 16 / 32 / 48 / 256 px.
    Formato: ICO con chunks PNG (compatible Windows Vista+).
    Uso: .\Create-Icon.ps1
#>

Add-Type -AssemblyName System.Drawing

function New-WinBoostBitmap {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap(
                $Size, $Size,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Fondo transparente
    $g.Clear([System.Drawing.Color]::Transparent)

    # Cuadrado redondeado oscuro (#0D0D0D)
    $radius  = [int]([math]::Max(2, $Size * 0.18))
    $bgColor = [System.Drawing.Color]::FromArgb(255, 13, 13, 13)
    $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
    $path    = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d       = $radius * 2
    $path.AddArc(0,          0,          $d, $d, 180, 90)
    $path.AddArc($Size - $d, 0,          $d, $d, 270, 90)
    $path.AddArc($Size - $d, $Size - $d, $d, $d, 0,   90)
    $path.AddArc(0,          $Size - $d, $d, $d, 90,  90)
    $path.CloseFigure()
    $g.FillPath($bgBrush, $path)
    $bgBrush.Dispose()
    $path.Dispose()

    # Rayo (#00C8FF) — poligono de 6 puntos
    $pad  = [float]($Size * 0.16)
    $w    = [float]($Size - $pad * 2)
    $h    = [float]($Size - $pad * 2)

    $pts = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($pad + $w * 0.63, $pad             ),  # punta superior
        [System.Drawing.PointF]::new($pad + $w * 0.20, $pad + $h * 0.53),  # izquierda arriba
        [System.Drawing.PointF]::new($pad + $w * 0.50, $pad + $h * 0.53),  # centro arriba
        [System.Drawing.PointF]::new($pad + $w * 0.37, $pad + $h        ),  # punta inferior
        [System.Drawing.PointF]::new($pad + $w * 0.80, $pad + $h * 0.47),  # derecha abajo
        [System.Drawing.PointF]::new($pad + $w * 0.50, $pad + $h * 0.47)   # centro abajo
    )

    $cyanBrush = New-Object System.Drawing.SolidBrush(
                     [System.Drawing.Color]::FromArgb(255, 0, 200, 255))
    $g.FillPolygon($cyanBrush, $pts)
    $cyanBrush.Dispose()
    $g.Dispose()

    return $bmp
}

function Get-PngBytes {
    param([System.Drawing.Bitmap]$Bmp)
    $ms = New-Object System.IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return ,$ms.ToArray()
}

# ----------------------------------------------------------------
# Generar PNG por tamano
# ----------------------------------------------------------------
$sizes   = @(16, 32, 48, 256)
$pngMap  = @{}

foreach ($sz in $sizes) {
    $bmp        = New-WinBoostBitmap -Size $sz
    $pngMap[$sz] = Get-PngBytes -Bmp $bmp
    $bmp.Dispose()
    Write-Host ("  {0,3}x{0,-3}  {1,6} bytes" -f $sz, $pngMap[$sz].Length) -ForegroundColor Gray
}

# ----------------------------------------------------------------
# Ensamblar ICO binario (PNG chunks, Vista+)
# Estructura: ICONDIR (6) + N*ICONDIRENTRY (16) + N*PNG_DATA
# ----------------------------------------------------------------
$n       = $sizes.Count
$dirSize = 6 + $n * 16
$offset  = [uint32]$dirSize
$offsets = @{}
foreach ($sz in $sizes) { $offsets[$sz] = $offset; $offset += [uint32]$pngMap[$sz].Length }

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

# ICONDIR
$bw.Write([uint16]0)       # reserved
$bw.Write([uint16]1)       # type = ICO
$bw.Write([uint16]$n)      # count

# ICONDIRENTRY x N
foreach ($sz in $sizes) {
    $b = if ($sz -eq 256) { [byte]0 } else { [byte]$sz }
    $bw.Write($b)                              # bWidth
    $bw.Write($b)                              # bHeight
    $bw.Write([byte]0)                         # bColorCount (0 = true color)
    $bw.Write([byte]0)                         # bReserved
    $bw.Write([uint16]1)                       # wPlanes
    $bw.Write([uint16]32)                      # wBitCount
    $bw.Write([uint32]$pngMap[$sz].Length)     # dwBytesInRes
    $bw.Write([uint32]$offsets[$sz])           # dwImageOffset
}

# Datos PNG
foreach ($sz in $sizes) { $bw.Write($pngMap[$sz]) }

$bw.Flush()
$icoBytes = $ms.ToArray()
$bw.Dispose()
$ms.Dispose()

# ----------------------------------------------------------------
# Guardar
# ----------------------------------------------------------------
$out = Join-Path $PSScriptRoot "WinBoost.ico"
[System.IO.File]::WriteAllBytes($out, $icoBytes)
Write-Host ""
Write-Host ("WinBoost.ico creado  ({0:N1} KB)  ->  {1}" -f ($icoBytes.Length/1KB), $out) -ForegroundColor Green
