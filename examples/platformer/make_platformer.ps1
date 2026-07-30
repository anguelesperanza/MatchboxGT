# Regenerate examples/platformer/tiles.gtg.deflate — a platformer tileset + player.
#
#   pwsh examples/platformer/make_platformer.ps1
#
# Row 0: tile 0 = air (transparent), tile 1 = solid ground block, and the player
# sprite at X=32. Tile 0 is left blank so it draws nothing (passable); tile 1 is a
# grass-topped dirt block (solid). solid_min = 1 in the example.

Add-Type -AssemblyName System.Drawing
$W = 128
$img = New-Object byte[] 16384
function Px($x, $y, $c) { $script:img[$y * $W + $x] = $c }

$GRASS = 0x1C; $DIRT = 0x52; $EDGE = 0x01; $DOT = 0x51   # ground block
$HEAD = 0x07; $BODY = 0x7C; $LEGS = 0x01                 # player

# tile 0: air -> leave transparent (all zero)

# tile 1 (X=16): grass-topped dirt block, fully opaque
for ($y = 0; $y -lt 16; $y++) {
	for ($x = 0; $x -lt 16; $x++) {
		$c = $DIRT
		if ($y -lt 3) { $c = $GRASS }
		if ($y -eq 0) { $c = $EDGE }                       # dark top edge
		if ($y -ge 5 -and (($x + $y * 5) % 7 -eq 0)) { $c = $DOT } # dirt texture
		Px (16 + $x) $y $c
	}
}

# player (X=32): white head, red body, dark legs
for ($y = 1; $y -le 5; $y++) { for ($x = 5; $x -le 10; $x++) { $dx = $x - 7.5; $dy = $y - 3; if ($dx * $dx + $dy * $dy -le 8) { Px (32 + $x) $y $HEAD } } }
Px (32 + 6) 3 0x00; Px (32 + 9) 3 0x00                    # eyes (transparent)
for ($y = 6; $y -le 12; $y++) { for ($x = 4; $x -le 11; $x++) { Px (32 + $x) $y $BODY } }
for ($y = 13; $y -le 15; $y++) { Px (32 + 5) $y $LEGS; Px (32 + 6) $y $LEGS; Px (32 + 9) $y $LEGS; Px (32 + 10) $y $LEGS }

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
$out = Join-Path $PSScriptRoot "tiles.gtg.deflate"
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Output "wrote $out ($($ms.ToArray().Length) bytes)"
