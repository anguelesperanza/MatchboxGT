package main

// Tilemap: a walled room drawn from a byte map, with a hero you walk around inside
// it. draw_tilemap blits the whole grid each frame from the tile-index array; the
// player is a normal object drawn on top. This is the base for roguelike rooms and
// RPG maps — swap the map bytes (in ROM or RAM) to change the level.
//
//   odin run examples/tilemap     # from the repo root (or `odin run .` from this folder); writes tilemap.gtr
//
// Sheet (examples/tilemap/tiles.gtg.deflate, from make_tiles): tile 0 = floor,
// tile 1 = wall, and a player sprite at sheet X=32, all at row 0.

import gt "../../gametank"

COLS :: u8(8)
ROWS :: u8(6)
W :: u8(1) // wall tile
F :: u8(0) // floor tile

// the room: a wall border around an open floor (8 x 6 = 48 tiles, row-major)
room := [?]u8{
	W, W, W, W, W, W, W, W,
	W, F, F, F, F, F, F, W,
	W, F, F, F, F, F, F, W,
	W, F, F, F, F, F, F, W,
	W, F, F, F, F, F, F, W,
	W, W, W, W, W, W, W, W,
}

input: gt.Var

setup :: proc(p: ^gt.Program) {
	gt.blob(p, "tiles", #load("tiles.gtg.deflate"))
	gt.inflate_asset(p, "tiles")
	gt.blob(p, "room", room[:])
	gt.set_object(p, 0, 40, 40, 32, 0) // hero (sheet 32,0) starting on the floor
	input = gt.alloc_var(p)
}

frame :: proc(p: ^gt.Program) {
	gt.read_gamepad1(p, input)
	// keep the 16x16 hero on the floor (inside the 1-tile wall border)
	gt.move_dec(p, input, gt.PAD_UP,    gt.OBJ_Y + 0, 16)
	gt.move_inc(p, input, gt.PAD_DOWN,  gt.OBJ_Y + 0, 64)
	gt.move_dec(p, input, gt.PAD_LEFT,  gt.OBJ_X + 0, 16)
	gt.move_inc(p, input, gt.PAD_RIGHT, gt.OBJ_X + 0, 96)

	gt.draw_tilemap(p, gt.blob_addr(p, "room"), COLS, ROWS, 0, 0, 0)
	gt.draw_objects(p, 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "tilemap.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}
