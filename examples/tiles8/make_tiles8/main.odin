// Regenerate examples/tiles8/tiles8.gtg.deflate — an 8x8 tileset + a 16px hero.
//
//   odin run examples/tiles8/make_tiles8     # from the repo root
//
// 8px tiles use a 16-wide grid, so tile N sits at sheet (X=(N&15)*8, Y=(N>>4)*8).
// Row 0 holds tile 0 = floor, 1 = wall, 2 = accent floor. The 16x16 hero sits at
// sheet (0,16), below the 8px tile row so it doesn't collide with any tile cell.
package main

import "core:os"
import gt "../../../tools/gtimg"

main :: proc() {
	out := "examples/tiles8/tiles8.gtg.deflate"
	if len(os.args) > 1 {
		out = os.args[1]
	}

	img := gt.new_sheet()
	defer delete(img)

	FLOOR  :: u8(0x02); GRID   :: u8(0x01)          // floor: dark grey + grid line
	WALL   :: u8(0x52); MORTAR :: u8(0x01)          // wall: brick + mortar
	DOT    :: u8(0x36)                              // accent-floor centre dot
	HEAD   :: u8(0x07); BODY   :: u8(0x7C); LEGS :: u8(0x01) // hero

	// --- 8x8 tiles in row 0 ---
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			// tile 0 (0,0): floor with a top-left grid line
			fc := FLOOR
			if x == 0 || y == 0 { fc = GRID }
			gt.px(img, x, y, fc)
			// tile 1 (8,0): brick wall
			wc := WALL
			if (x + y) % 4 == 0 { wc = MORTAR }
			gt.px(img, 8 + x, y, wc)
			// tile 2 (16,0): accent floor (floor + a bright centre block)
			ac := FLOOR
			if x >= 2 && x <= 5 && y >= 2 && y <= 5 { ac = DOT }
			gt.px(img, 16 + x, y, ac)
		}
	}

	// --- 16x16 hero at sheet (0,16): head, body, legs ---
	for y in 2 ..= 6 { for x in 5 ..= 10 { gt.px(img, x, 16 + y, HEAD) } }
	gt.px(img, 6, 16 + 4, 0x00); gt.px(img, 9, 16 + 4, 0x00) // eyes (transparent)
	for y in 7 ..= 12 { for x in 4 ..= 11 { gt.px(img, x, 16 + y, BODY) } }
	for y in 13 ..= 15 {
		gt.px(img, 5, 16 + y, LEGS); gt.px(img, 6, 16 + y, LEGS)
		gt.px(img, 9, 16 + y, LEGS); gt.px(img, 10, 16 + y, LEGS)
	}

	if !gt.write_gtg(out, img) {
		os.exit(1)
	}
}
