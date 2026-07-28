# Regenerate examples/tilemap/tiles.gtg.deflate — a small tileset + a player sprite.
#
#   pwsh examples/tilemap/make_tiles.ps1     # from the repo root
#
# Row 0 of the sheet, three 16x16 cells: tile 0 = floor, tile 1 = wall, and (at
# X=32) the player sprite. Colors are GameTank HHHSSBBB bytes; 0 is transparent.

Add-Type -AssemblyName System.Drawing
$W = 128
$img = New-Object byte[] 16384
function Px($tileX, $lx, $ly, $col) { $script:img[$ly * $W + $tileX + $lx] = $col }

$FLOOR = 0x02; $GRID = 0x01              # floor: dark gray with darker grid lines
$BRICK = 0x52; $MORTAR = 0x01            # wall: brown brick, dark mortar
$SKIN = 0x07; $BODY = 0x7C; $LEGS = 0x01 # player: white head, red body, dark legs

for ($y = 0; $y -lt 16; $y++) {
	for ($x = 0; $x -lt 16; $x++) {
		# tile 0: floor
		$c = $FLOOR; if ($x -eq 0 -or $y -eq 0) { $c = $GRID }
		Px 0 $x $y $c

		# tile 1: wall (brick courses, offset every other row)
		$c = $BRICK
		if ($y % 8 -eq 0) { $c = $MORTAR }
		$off = 0; if ([math]::Floor($y / 8) % 2 -eq 1) { $off = 4 }
		if ((($x - $off) % 8 + 8) % 8 -eq 0) { $c = $MORTAR }
		Px 16 $x $y $c
	}
}

# player sprite at X=32: head, body, legs
for ($y = 2; $y -le 6; $y++) { for ($x = 5; $x -le 10; $x++) { Px 32 $x $y $SKIN } } # head
Px 32 6 4 0x00; Px 32 9 4 0x00                                                        # eyes (transparent)
for ($y = 7; $y -le 12; $y++) { for ($x = 4; $x -le 11; $x++) { Px 32 $x $y $BODY } } # body
for ($y = 13; $y -le 15; $y++) { Px 32 5 $y $LEGS; Px 32 6 $y $LEGS; Px 32 9 $y $LEGS; Px 32 10 $y $LEGS } # legs

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
$out = Join-Path $PSScriptRoot "tiles.gtg.deflate"
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Output "wrote $out ($($ms.ToArray().Length) bytes)"

# preview: the 48x16 sheet region scaled 10x
$scale = 10; $pv = New-Object System.Drawing.Bitmap (48 * $scale), (16 * $scale)
$g = [System.Drawing.Graphics]::FromImage($pv)
$pal = @{ 0x00 = [System.Drawing.Color]::FromArgb(20, 20, 40); 0x01 = [System.Drawing.Color]::FromArgb(60, 60, 60);
	0x02 = [System.Drawing.Color]::FromArgb(110, 110, 110); 0x07 = [System.Drawing.Color]::White;
	0x52 = [System.Drawing.Color]::FromArgb(170, 110, 60); 0x7C = [System.Drawing.Color]::FromArgb(210, 60, 60) }
for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 48; $x++) {
		$v = $img[$y * $W + $x]; $c = if ($pal.ContainsKey([int]$v)) { $pal[[int]$v] } else { [System.Drawing.Color]::Magenta }
		$br = New-Object System.Drawing.SolidBrush $c; $g.FillRectangle($br, $x * $scale, $y * $scale, $scale, $scale); $br.Dispose()
	} }
$g.Dispose()
$pv.Save((Join-Path $env:TEMP "tiles_preview.png"), [System.Drawing.Imaging.ImageFormat]::Png); $pv.Dispose()
Write-Output ("preview: " + (Join-Path $env:TEMP "tiles_preview.png"))
