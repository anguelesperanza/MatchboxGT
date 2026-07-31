package main

// 8x8 tilemap: a decorated walled room you walk a hero around, drawn with
// draw_tilemap(..., tile_px = 8). This is the tilemap example at half the tile
// size — a 16x12 grid of 8px tiles fills the screen (vs 8x6 at 16px), so maps get
// twice the detail. Every tilemap/collision helper takes the same optional tile_px.
//
//   odin run examples/tiles8     # from the repo root (or `odin run .` from this folder); writes tiles8.gtr
//
// Sheet (examples/tiles8/tiles8.gtg.deflate, from make_tiles8): tile 0 = floor,
// 1 = wall, 2 = accent floor; a 16x16 hero at sheet (0,16).

import gt "../../gametank"

COLS :: u8(16)
ROWS :: u8(12)
W :: u8(1) // wall tile
F :: u8(0) // floor tile
A :: u8(2) // accent-floor tile (decorative; you walk over it)

// A 16x12 room: wall border, open floor, and accent tiles for detail (192 tiles).
room := [?]u8{
	W, W, W, W, W, W, W, W, W, W, W, W, W, W, W, W,
	W, A, F, F, F, F, F, F, F, F, F, F, F, F, A, W,
	W, F, F, F, F, F, F, F, F, F, F, F, F, F, F, W,
	W, F, F, A, F, F, F, F, F, F, F, F, A, F, F, W,
	W, F, F, F, F, F, F, F, F, F, F, F, F, F, F, W,
	W, F, F, F, F, F, A, A, A, A, F, F, F, F, F, W,
	W, F, F, F, F, F, A, F, F, A, F, F, F, F, F, W,
	W, F, F, F, F, F, A, A, A, A, F, F, F, F, F, W,
	W, F, F, F, F, F, F, F, F, F, F, F, F, F, F, W,
	W, F, F, A, F, F, F, F, F, F, F, F, A, F, F, W,
	W, A, F, F, F, F, F, F, F, F, F, F, F, F, A, W,
	W, W, W, W, W, W, W, W, W, W, W, W, W, W, W, W,
}

input: gt.Var

setup :: proc(p: ^gt.Program) {
	gt.blob(p, "tiles", #load("tiles8.gtg.deflate"))
	gt.inflate_asset(p, "tiles")
	gt.blob(p, "room", room[:])
	gt.set_object(p, 0, 56, 40, 0, 16) // hero (sheet 0,16) on the floor
	input = gt.alloc_var(p)
}

frame :: proc(p: ^gt.Program) {
	gt.read_gamepad1(p, input)
	// keep the 16px hero inside the 8px (1-tile) wall border
	gt.move_dec(p, input, gt.PAD_UP,    gt.OBJ_Y + 0, 8)
	gt.move_inc(p, input, gt.PAD_DOWN,  gt.OBJ_Y + 0, 72)
	gt.move_dec(p, input, gt.PAD_LEFT,  gt.OBJ_X + 0, 8)
	gt.move_inc(p, input, gt.PAD_RIGHT, gt.OBJ_X + 0, 104)

	gt.draw_tilemap(p, gt.blob_addr(p, "room"), COLS, ROWS, 0, 0, 0, 8) // tile_px = 8
	gt.draw_objects(p, 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "tiles8.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}
