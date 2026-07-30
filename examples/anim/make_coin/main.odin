// Regenerate examples/anim/coin.gtg.deflate — a 4-frame spinning-coin strip.
//
//   odin run examples/anim/make_coin       # from the repo root
//   odin run examples/anim/make_coin -- <output.gtg.deflate>
//
// Native replacement for make_coin.ps1. Output is a raw-DEFLATE 128x128, 1-byte-
// per-pixel sprite-RAM image (GameTank HHHSSBBB; 0 = transparent). Frame N of the
// strip lives at sheet X = N*16, row 0.
package main

import "core:os"
import gt "../../../tools/gtimg"

main :: proc() {
	out := "examples/anim/coin.gtg.deflate"
	if len(os.args) > 1 {
		out = os.args[1]
	}

	img := gt.new_sheet()
	defer delete(img)

	GOLD  :: u8(0x3C) // coin body
	LIGHT :: u8(0x36) // upper-left sheen
	GLINT :: u8(0x07) // white glint
	rx := [4]f64{7.0, 5.0, 2.0, 5.0} // horizontal radius per frame: full, med, edge, med
	ry :: 7.0
	cx :: 7.5
	cy :: 7.5

	for f in 0 ..< 4 {
		for y in 0 ..< 16 {
			for x in 0 ..< 16 {
				dx := f64(x) - cx
				dy := f64(y) - cy
				d := (dx * dx) / (rx[f] * rx[f]) + (dy * dy) / (ry * ry)
				if d <= 1.0 {
					col := GOLD
					if d <= 0.35 && dx < 0 && dy < 0 {
						col = LIGHT
					}
					gt.px(img, f * 16 + x, y, col)
				}
			}
		}
		if rx[f] >= 4 {
			gt.px(img, f * 16 + 5, 3, GLINT) // glint (skip the thin edge frame)
		}
	}

	if !gt.write_gtg(out, img) {
		os.exit(1)
	}
}
