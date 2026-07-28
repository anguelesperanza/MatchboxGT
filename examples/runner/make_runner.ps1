# Regenerate examples/runner/runner.gtg.deflate — a parallax-runner sprite sheet.
#
#   pwsh examples/runner/make_runner.ps1
#
# Layout (128x128 sprite RAM):
#   gy 0   : 4 player run frames, 16x16 (at X = 0,16,32,48)
#   gy 16  : mountains strip  128x24  (far layer)
#   gy 40  : hills strip      128x24  (mid layer)
#   gy 64  : ground strip     128x24  (near layer)
# The three strips are 128px wide and seamless so they wrap invisibly.

Add-Type -AssemblyName System.Drawing
$W = 128
$img = New-Object byte[] 16384
function Px($x, $y, $c) { if ($x -ge 0 -and $x -lt 128 -and $y -ge 0 -and $y -lt 128) { $script:img[$y * $W + $x] = $c } }

$BODY = 0x7C; $HEAD = 0x07; $LEG = 0x01                    # player
$MTN = 0xC2                                                # mountains (blue-grey)
$HILL = 0x13                                               # hills (green)
$GRASS = 0x1C; $DIRT = 0x52; $DOT = 0x51                   # ground

# --- player: 4 run frames (legs together / apart) ---
$legFrames = @(@(6, 9), @(4, 11), @(6, 9), @(4, 11))
for ($f = 0; $f -lt 4; $f++) {
	$ox = $f * 16
	for ($y = 1; $y -le 5; $y++) { for ($x = 5; $x -le 10; $x++) { $dx = $x - 7.5; $dy = $y - 3; if ($dx * $dx + $dy * $dy -le 8) { Px ($ox + $x) $y $HEAD } } } # head
	for ($y = 6; $y -le 11; $y++) { for ($x = 5; $x -le 10; $x++) { Px ($ox + $x) $y $BODY } }   # body
	for ($y = 7; $y -le 9; $y++) { Px ($ox + 3) $y $BODY; Px ($ox + 4) $y $BODY; Px ($ox + 11) $y $BODY; Px ($ox + 12) $y $BODY } # arms
	$l = $legFrames[$f]
	for ($y = 12; $y -le 15; $y++) { Px ($ox + $l[0]) $y $LEG; Px ($ox + $l[0] + 1) $y $LEG; Px ($ox + $l[1]) $y $LEG; Px ($ox + $l[1] + 1) $y $LEG }
}

# --- mountains strip (gy 16, 24 tall): triangular peaks, period 32 ---
for ($x = 0; $x -lt 128; $x++) {
	$dist = [math]::Abs(($x % 32) - 16)   # 0 at peak, 16 at valley
	for ($y = $dist; $y -lt 24; $y++) { Px $x (16 + $y) $MTN }
}

# --- hills strip (gy 40, 24 tall): rounded humps, period 64 ---
for ($x = 0; $x -lt 128; $x++) {
	$hump = [int][math]::Round(10 * [math]::Sin([math]::PI * ($x % 64) / 64))
	for ($y = 14 - $hump; $y -lt 24; $y++) { if ($y -ge 0) { Px $x (40 + $y) $HILL } }
}

# --- ground strip (gy 64, 24 tall): grass top, dirt below, texture dots ---
for ($x = 0; $x -lt 128; $x++) {
	for ($y = 0; $y -lt 24; $y++) {
		$c = $DIRT; if ($y -lt 4) { $c = $GRASS }
		if ($y -ge 6 -and (($x + $y * 3) % 11 -eq 0)) { $c = $DOT }
		Px $x (64 + $y) $c
	}
}

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
$out = Join-Path $PSScriptRoot "runner.gtg.deflate"
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Output "wrote $out ($($ms.ToArray().Length) bytes)"

# preview the 128x88 art region scaled 4x
$scale = 4; $pv = New-Object System.Drawing.Bitmap (128 * $scale), (88 * $scale); $g = [System.Drawing.Graphics]::FromImage($pv)
$pal = @{ 0x00 = [System.Drawing.Color]::FromArgb(20, 20, 50); 0x01 = [System.Drawing.Color]::FromArgb(40, 40, 40); 0x07 = [System.Drawing.Color]::White;
	0x7C = [System.Drawing.Color]::FromArgb(210, 60, 60); 0xC2 = [System.Drawing.Color]::FromArgb(120, 130, 160); 0x13 = [System.Drawing.Color]::FromArgb(60, 150, 70);
	0x1C = [System.Drawing.Color]::FromArgb(90, 200, 90); 0x52 = [System.Drawing.Color]::FromArgb(150, 100, 55); 0x51 = [System.Drawing.Color]::FromArgb(110, 75, 40)
}
for ($y = 0; $y -lt 88; $y++) { for ($x = 0; $x -lt 128; $x++) {
		$v = $img[$y * $W + $x]; $c = if ($pal.ContainsKey([int]$v)) { $pal[[int]$v] } else { [System.Drawing.Color]::Magenta }
		$br = New-Object System.Drawing.SolidBrush $c; $g.FillRectangle($br, $x * $scale, $y * $scale, $scale, $scale); $br.Dispose()
	} }
$g.Dispose()
$pv.Save((Join-Path $env:TEMP "runner_preview.png"), [System.Drawing.Imaging.ImageFormat]::Png); $pv.Dispose()
Write-Output ("preview: " + (Join-Path $env:TEMP "runner_preview.png"))
