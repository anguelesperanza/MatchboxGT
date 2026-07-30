// Regenerate examples/platformer/tiles.gtg.deflate — a platformer tileset + player.
//
//   odin run examples/platformer/make_platformer    # from the repo root
//
// Native replacement for make_platformer.ps1. Row 0: tile 0 = air (transparent),
// tile 1 = solid grass-topped dirt block (at X=16), player sprite (at X=32).
// solid_min = 1 in the example. Colors are GameTank HHHSSBBB bytes; 0 transparent.
package main

import "core:os"
import gt "../../../tools/gtimg"

main :: proc() {
	out := "examples/platformer/tiles.gtg.deflate"
	if len(os.args) > 1 {
		out = os.args[1]
	}

	img := gt.new_sheet()
	defer delete(img)

	GRASS :: u8(0x1C); DIRT :: u8(0x52); EDGE :: u8(0x01); DOT :: u8(0x51) // ground block
	HEAD  :: u8(0x07); BODY :: u8(0x7C); LEGS :: u8(0x01)                  // player

	// tile 0: air -> leave transparent (all zero)

	// tile 1 (X=16): grass-topped dirt block, fully opaque
	for y in 0 ..< 16 {
		for x in 0 ..< 16 {
			c := DIRT
			if y < 3 {
				c = GRASS
			}
			if y == 0 {
				c = EDGE // dark top edge
			}
			if y >= 5 && (x + y * 5) % 7 == 0 {
				c = DOT // dirt texture
			}
			gt.px(img, 16 + x, y, c)
		}
	}

	// player (X=32): white head, red body, dark legs
	for y in 1 ..= 5 {
		for x in 5 ..= 10 {
			dx := f64(x) - 7.5
			dy := f64(y) - 3
			if dx * dx + dy * dy <= 8 {
				gt.px(img, 32 + x, y, HEAD)
			}
		}
	}
	gt.px(img, 32 + 6, 3, 0x00) // eyes (transparent)
	gt.px(img, 32 + 9, 3, 0x00)
	for y in 6 ..= 12 {
		for x in 4 ..= 11 {
			gt.px(img, 32 + x, y, BODY)
		}
	}
	for y in 13 ..= 15 {
		gt.px(img, 32 + 5, y, LEGS)
		gt.px(img, 32 + 6, y, LEGS)
		gt.px(img, 32 + 9, y, LEGS)
		gt.px(img, 32 + 10, y, LEGS)
	}

	if !gt.write_gtg(out, img) {
		os.exit(1)
	}
}
