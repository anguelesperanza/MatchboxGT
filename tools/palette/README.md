# GameTank palette (for art tools)

The GameTank's 256-color palette (`HHHSSBBB` bytes), as **the emulator's DAC
actually renders them** — sampled from `examples/palette` in the emulator, not the
rough `HHHSSBBB → RGB` math. So art you draw with these swatches matches what shows
on screen. Note the DAC is dim: `$07` "white" is a light grey `(185,185,185)`, and
the hue names don't match their labels (see `gametank/color.odin`).

## Files

| File | Format | Use in |
|---|---|---|
| `gametank.gpl` | GIMP palette (256 swatches, each named `$HH` = its GameTank byte) | Aseprite, GIMP, Krita, Lospec, Piskel, … |
| `gametank-hex.txt` | plain `RRGGBB`, one per line; line *N* = byte *N* | anything that imports a hex list |
| `gametank.pal.txt` | `RRGGBB HH` (RGB → GameTank byte), 215 unique colors | `tools/png_to_sheet --palette` |

## Workflow

1. Import `gametank.gpl` (or `gametank-hex.txt`) into your art tool and draw your
   sprites/tiles/glyphs at the grid positions your code reads.
2. Leave empty areas **transparent** (alpha 0). Also note **`$00` (black) is
   transparent to the blitter** — a black pixel won't draw, so use it for holes.
3. Export a PNG and convert it with the exact-palette mode, which maps those RGBs
   straight back to GameTank bytes:

   ```bash
   odin run tools/png_to_sheet -- art.png sheet.gtg.deflate --palette tools/palette/gametank.pal.txt
   ```

Round-trip verified: a PNG painted with these colors converts back to the intended
bytes exactly.

## Regenerating

These were extracted by screenshotting `examples/palette` (a 16×16 grid of all 256
bytes) in the emulator and sampling each cell. If the emulator's DAC changes,
re-screenshot and re-sample.
