# deflate.ps1 — turn a raw sprite-RAM image into a .gtg.deflate the ROM can load.
#
#   pwsh tools/deflate.ps1 <input.bin> [output.gtg.deflate]
#
# Input is the raw bytes of a sprite-RAM image: 128 bytes per row, one byte per
# pixel, each byte a GameTank color (HHHSSBBB; 0 = transparent). A full sheet is
# 128 rows = 16384 bytes, but any length works — inflate_asset writes exactly as
# many bytes as the stream decodes to, starting at $4000. Output is raw DEFLATE
# (no zlib header), which the on-cart INFLATE routine decodes. If no output path is
# given, it writes <input>.gtg.deflate next to the input.
#
# To make sprites, produce that raw byte array however you like (draw shapes in
# code — see examples/anim/make_coin.ps1 — or map an indexed image's palette to
# GameTank color bytes) and run it through here.

param(
	[Parameter(Mandatory, Position = 0)][string]$InputPath,
	[Parameter(Position = 1)][string]$OutputPath
)

if (-not (Test-Path $InputPath)) { Write-Error "input not found: $InputPath"; exit 1 }
if (-not $OutputPath) {
	$OutputPath = [System.IO.Path]::ChangeExtension($InputPath, $null).TrimEnd('.') + ".gtg.deflate"
}

$raw = [System.IO.File]::ReadAllBytes($InputPath)
if ($raw.Length -gt 16384) {
	Write-Warning "input is $($raw.Length) bytes; a sprite-RAM page is 16384 (128x128). Extra bytes spill past the VRAM window."
}

$ms = New-Object System.IO.MemoryStream
$ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($raw, 0, $raw.Length); $ds.Dispose()
$comp = $ms.ToArray()
[System.IO.File]::WriteAllBytes($OutputPath, $comp)

Write-Output "wrote $OutputPath : $($comp.Length) bytes (from $($raw.Length))"

# sanity round-trip
$ms2 = New-Object System.IO.MemoryStream(, $comp)
$ds2 = New-Object System.IO.Compression.DeflateStream($ms2, [System.IO.Compression.CompressionMode]::Decompress)
$o2 = New-Object System.IO.MemoryStream; $ds2.CopyTo($o2); $ds2.Dispose()
if ($o2.ToArray().Length -ne $raw.Length) { Write-Warning "round-trip size mismatch!" }
