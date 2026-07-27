# Regenerate examples/anim/coin.gtg.deflate — a 4-frame spinning-coin strip.
#
#   pwsh examples/anim/make_coin.ps1     # from the repo root
#
# Output format (what gametank's inflate_asset expects): a raw-DEFLATE stream of a
# 128x128, 1-byte-per-pixel sprite-RAM image. Each byte is a GameTank color
# (HHHSSBBB); 0 is transparent. Frame N of the strip lives at sheet X = N*16, row 0.
# .NET's DeflateStream emits standard raw DEFLATE, which the on-cart INFLATE decodes.

Add-Type -AssemblyName System.Drawing
$W = 128; $H = 128
$img = New-Object byte[] ($W * $H)   # all 0 = transparent

$GOLD = 0x3C; $LIGHT = 0x36; $GLINT = 0x07   # coin body / upper-left sheen / white glint
$rx = @(7.0, 5.0, 2.0, 5.0)                  # horizontal radius per frame: full, med, edge, med
$ry = 7.0; $cx = 7.5; $cy = 7.5

for ($f = 0; $f -lt 4; $f++) {
	for ($y = 0; $y -lt 16; $y++) {
		for ($x = 0; $x -lt 16; $x++) {
			$dx = $x - $cx; $dy = $y - $cy
			$d = ($dx * $dx) / ($rx[$f] * $rx[$f]) + ($dy * $dy) / ($ry * $ry)
			if ($d -le 1.0) {
				$col = $GOLD
				if ($d -le 0.35 -and $dx -lt 0 -and $dy -lt 0) { $col = $LIGHT }
				$img[$y * $W + $f * 16 + $x] = $col
			}
		}
	}
	if ($rx[$f] -ge 4) { $img[3 * $W + $f * 16 + 5] = $GLINT }   # glint (skip the thin edge frame)
}

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
$out = Join-Path $PSScriptRoot "coin.gtg.deflate"
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Output "wrote $out ($($ms.ToArray().Length) bytes)"
