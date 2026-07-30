// Regenerate examples/tilemap/tiles.gtg.deflate — a small tileset + player sprite.
//
//   odin run examples/tilemap/make_tiles    # from the repo root
//
// Native replacement for make_tiles.ps1. Row 0 of the sheet, three 16x16 cells:
// tile 0 = floor, tile 1 = wall (at X=16), and the player sprite (at X=32).
// Colors are GameTank HHHSSBBB bytes; 0 is transparent.
package main

import "core:os"
import gt "../../../tools/gtimg"

main :: proc() {
	out := "examples/tilemap/tiles.gtg.deflate"
	if len(os.args) > 1 {
		out = os.args[1]
	}

	img := gt.new_sheet()
	defer delete(img)

	FLOOR  :: u8(0x02); GRID   :: u8(0x01)          // floor: dark gray + darker grid
	BRICK  :: u8(0x52); MORTAR :: u8(0x01)          // wall: brown brick, dark mortar
	SKIN   :: u8(0x07); BODY   :: u8(0x7C); LEGS :: u8(0x01) // player

	for y in 0 ..< 16 {
		for x in 0 ..< 16 {
			// tile 0: floor
			c := FLOOR
			if x == 0 || y == 0 {
				c = GRID
			}
			gt.px(img, x, y, c)

			// tile 1 (X=16): wall, brick courses offset every other row
			c = BRICK
			if y % 8 == 0 {
				c = MORTAR
			}
			off := 0
			if (y / 8) % 2 == 1 {
				off = 4
			}
			if ((x - off) % 8 + 8) % 8 == 0 {
				c = MORTAR
			}
			gt.px(img, 16 + x, y, c)
		}
	}

	// player sprite at X=32: head, body, legs
	for y in 2 ..= 6 {
		for x in 5 ..= 10 {
			gt.px(img, 32 + x, y, SKIN)
		}
	}
	gt.px(img, 32 + 6, 4, 0x00) // eyes (transparent)
	gt.px(img, 32 + 9, 4, 0x00)
	for y in 7 ..= 12 {
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
