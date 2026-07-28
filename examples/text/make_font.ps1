# Regenerate examples/text/font.gtg.deflate — a full-charset 8x8 font sheet.
#
#   pwsh examples/text/make_font.ps1     # from the repo root
#
# Renders an 8x8 glyph grid (white on transparent) into a sprite sheet at row 0,
# then raw-DEFLATEs it into the format inflate_asset expects. The glyph ORDER here
# must match gametank/font.odin's glyph_index: 0-9, A-Z (10-35), a-z (36-61), then
# punctuation (62+). Glyphs are drawn with GDI+ SingleBitPerPixel (crisp, no AA).

Add-Type -AssemblyName System.Drawing

$chars = @()
$chars += [char[]]"0123456789"                 # 0-9
$chars += [char[]]"ABCDEFGHIJKLMNOPQRSTUVWXYZ"  # 10-35
$chars += [char[]]"abcdefghijklmnopqrstuvwxyz"  # 36-61
$chars += [char]'.'; $chars += [char]','; $chars += [char]'!'; $chars += [char]'?'  # 62-65
$chars += [char]"'"; $chars += [char]':'; $chars += [char]';'; $chars += [char]'-'  # 66-69
$chars += [char]'('; $chars += [char]')'; $chars += [char]'/'; $chars += [char]'+'  # 70-73
$chars += [char]'='; $chars += [char]'*'; $chars += [char]'%'; $chars += [char]'"'  # 74-77
$chars += [char]'<'; $chars += [char]'>'                                            # 78-79

$bmp = New-Object System.Drawing.Bitmap 128, 128
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
# 10px (not 8px) so lowercase has enough detail to be legible; each glyph is
# clipped to its 8x8 cell so it can't bleed into a neighbour, and nudged to sit
# inside the cell (draw_string later extracts each cell individually).
$font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.GraphicsUnit]::Pixel)
for ($i = 0; $i -lt $chars.Count; $i++) {
	$cx = ($i % 16) * 8; $cy = [math]::Floor($i / 16) * 8
	$g.SetClip((New-Object System.Drawing.Rectangle $cx, $cy, 8, 8))
	$g.DrawString([string]$chars[$i], $font, [System.Drawing.Brushes]::White, ($cx + 0.5), ($cy - 1.5))
	$g.ResetClip()
}
$g.Dispose()

$TEXT = 0x07   # white
$img = New-Object byte[] 16384
for ($y = 0; $y -lt 40; $y++) {
	for ($x = 0; $x -lt 128; $x++) {
		if ($bmp.GetPixel($x, $y).R -gt 100) { $img[$y * 128 + $x] = $TEXT }
	}
}
$bmp.Dispose()

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($img, 0, $img.Length); $ds.Dispose()
$out = Join-Path $PSScriptRoot "font.gtg.deflate"
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Output "wrote $out ($($ms.ToArray().Length) bytes, $($chars.Count) glyphs)"
