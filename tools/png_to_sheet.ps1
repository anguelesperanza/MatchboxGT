# png_to_sheet.ps1 — convert an image into a GameTank sprite sheet (.gtg.deflate).
#
#   # exact: you supply an RGB -> GameTank-byte palette (recommended for real art)
#   pwsh tools/png_to_sheet.ps1 art.png sheet.gtg.deflate -Palette pal.txt
#
#   # approximate: auto-map each pixel to the nearest GameTank color (prototyping)
#   pwsh tools/png_to_sheet.ps1 art.png sheet.gtg.deflate -Quantize
#
# The image is copied pixel-for-pixel to the top-left of a 128x128 sprite-RAM sheet
# (the rest transparent), so lay your sprites/tiles/glyphs out in the image at the
# grid positions your code reads (16x16 objects & tiles, 8x8 glyphs). Fully
# transparent pixels (alpha 0) become GameTank color 0 (transparent). Colours are
# GameTank HHHSSBBB bytes — see examples/palette for the real on-screen palette.
#
# Palette file format (exact mode): one "RRGGBB HH" per line (hex RGB, hex byte);
# blank lines and # comments ignored. Map your transparent/background colour to 00.

param(
	[Parameter(Mandatory, Position = 0)][string]$InputPath,
	[Parameter(Position = 1)][string]$OutputPath,
	[string]$Palette,
	[switch]$Quantize
)

if (-not (Test-Path $InputPath)) { Write-Error "input not found: $InputPath"; exit 1 }
if (-not $Palette -and -not $Quantize) { Write-Error "pick a mode: -Palette <file> or -Quantize"; exit 1 }
if (-not $OutputPath) { $OutputPath = [System.IO.Path]::ChangeExtension($InputPath, $null).TrimEnd('.') + ".gtg.deflate" }

Add-Type -AssemblyName System.Drawing

# --- GameTank color (HHHSSBBB) -> approximate RGB, for -Quantize nearest matching ---
$hueDeg = @(120, 60, 30, 0, 300, 260, 240, 180)  # green,yellow,orange,red,magenta,indigo,blue,cyan (rough)
function ByteToRGB([int]$b) {
	$h = ($b -shr 5) -band 7; $s = ($b -shr 3) -band 3; $br = $b -band 7
	$v = $br / 7.0
	if ($s -eq 0) { $g = [int]($v * 255); return , @($g, $g, $g) }
	$sat = $s / 3.0
	if ($br -gt 4) { $sat = $sat * (7 - $br) / 3.0 }   # high brightness washes toward white
	$hh = $hueDeg[$h] / 60.0; $c = $v * $sat; $xx = $c * (1 - [math]::Abs(($hh % 2) - 1)); $m = $v - $c
	switch ([math]::Floor($hh)) {
		0 { $r = $c; $gc = $xx; $bl = 0 } 1 { $r = $xx; $gc = $c; $bl = 0 } 2 { $r = 0; $gc = $c; $bl = $xx }
		3 { $r = 0; $gc = $xx; $bl = $c } 4 { $r = $xx; $gc = 0; $bl = $c } default { $r = $c; $gc = 0; $bl = $xx }
	}
	return , @([int](($r + $m) * 255), [int](($gc + $m) * 255), [int](($bl + $m) * 255))
}

# precompute the 256 palette RGBs once (quantize mode)
$palRGB = $null
if ($Quantize) { $palRGB = for ($i = 0; $i -lt 256; $i++) { , (ByteToRGB $i) } }

# exact palette map RRGGBB(int) -> byte
$map = @{}
if ($Palette) {
	if (-not (Test-Path $Palette)) { Write-Error "palette not found: $Palette"; exit 1 }
	foreach ($line in Get-Content $Palette) {
		$t = $line.Trim(); if ($t -eq "" -or $t.StartsWith("#")) { continue }
		$parts = $t -split '\s+'; $rgb = [Convert]::ToInt32($parts[0], 16); $byte = [Convert]::ToInt32($parts[1], 16)
		$map[$rgb] = $byte
	}
}

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $InputPath))
$W = [Math]::Min($src.Width, 128); $H = [Math]::Min($src.Height, 128)
$img = New-Object byte[] 16384
$unmatched = 0
for ($y = 0; $y -lt $H; $y++) {
	for ($x = 0; $x -lt $W; $x++) {
		$px = $src.GetPixel($x, $y)
		if ($px.A -lt 128) { continue }   # transparent -> byte 0
		if ($Palette) {
			$key = ([int]$px.R -shl 16) -bor ([int]$px.G -shl 8) -bor [int]$px.B
			if ($map.ContainsKey($key)) { $img[$y * 128 + $x] = $map[$key] } else { $unmatched++ }
		} else {
			$best = 0; $bd = [int]::MaxValue
			for ($i = 1; $i -lt 256; $i++) {
				$c = $palRGB[$i]; $dr = $px.R - $c[0]; $dg = $px.G - $c[1]; $db = $px.B - $c[2]
				$d = $dr * $dr + $dg * $dg + $db * $db
				if ($d -lt $bd) { $bd = $d; $best = $i }
			}
			$img[$y * 128 + $x] = $best
		}
	}
}
$src.Dispose()
if ($unmatched -gt 0) { Write-Warning "$unmatched pixel(s) had no palette entry (left transparent)" }

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
[System.IO.File]::WriteAllBytes($OutputPath, $ms.ToArray())
Write-Output "wrote $OutputPath ($(($ms.ToArray()).Length) bytes) from ${W}x${H} image"
