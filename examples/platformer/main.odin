package main

// A single-screen platformer: run with the D-pad, jump with A. Gravity pulls you
// down; you land on and are blocked by solid tiles. The physics is the runner's
// jump plus tile collision (if_solid / snap_to_tile_below) against the level map.
//
//   odin run examples/platformer     # from the repo root (or `odin run .` from this folder); writes platformer.gtr
//
// Tileset (examples/platformer/tiles.gtg.deflate, from make_platformer):
// tile 0 = air (passable), tile 1 = solid ground; player sprite at sheet X=32.

import gt "../../gametank"

COLS    :: 8
ROWS    :: 8
SOLID   :: u8(1)     // tiles with index >= this are solid
TILE_GY :: u8(0)
SPEED   :: u8(2)     // run speed (px/frame)
JUMP    :: 9         // initial jump speed
GRAVITY :: u8(1)

A :: u8(0) // air
W :: u8(1) // wall / ground

// the level: a walled arena with a floor and a few platforms (row-major, 8x8)
level := [?]u8{
	A, A, A, A, A, A, A, A,
	A, A, A, A, A, A, A, A,
	W, A, A, A, W, W, A, W,
	W, A, A, A, A, A, A, W,
	W, A, W, W, A, A, A, W,
	W, A, A, A, A, W, W, W,
	W, W, W, W, W, W, W, W,
	W, W, W, W, W, W, W, W,
}

held, pressed, vy, grounded: gt.Var
px := gt.Var{addr = gt.OBJ_X + 0} // the player's X/Y ARE object 0's position bytes
py := gt.Var{addr = gt.OBJ_Y + 0}

setup :: proc(p: ^gt.Program) {
	gt.blob(p, "tiles", #load("tiles.gtg.deflate"))
	gt.inflate_asset(p, "tiles")
	gt.blob(p, "level", level[:])
	gt.set_object(p, 0, 24, 8, 32, 0) // player (sheet 32,0), spawned in the air to fall in
	held = gt.alloc_var(p); pressed = gt.alloc_var(p); vy = gt.alloc_var(p); grounded = gt.alloc_var(p)
	gt.set(p, held, 0)
	gt.set(p, vy, 0)
}

LEVEL :: proc(p: ^gt.Program) -> u16 { return gt.blob_addr(p, "level") }

frame :: proc(p: ^gt.Program) {
	gt.poll_gamepad1(p, held, pressed)

	// --- run left/right, blocked by solid tiles (move, then undo if it hit a wall) ---
	r := gt.if_pressed(p, held, gt.PAD_RIGHT)
	gt.add(p, px, SPEED)
	hitr := gt.if_solid(p, LEVEL(p), COLS, px, 15, py, 8, SOLID) // right edge in a wall?
	gt.sub(p, px, SPEED)
	gt.put_label(p, hitr)
	gt.put_label(p, r)

	l := gt.if_pressed(p, held, gt.PAD_LEFT)
	gt.sub(p, px, SPEED)
	hitl := gt.if_solid(p, LEVEL(p), COLS, px, 0, py, 8, SOLID) // left edge in a wall?
	gt.add(p, px, SPEED)
	gt.put_label(p, hitl)
	gt.put_label(p, l)

	// --- jump on A, but only when standing on something ---
	j := gt.if_just_pressed(p, pressed, gt.PAD_A)
	g := gt.if_nonzero(p, grounded)
	gt.set(p, vy, u8(256 - JUMP)) // vy = -JUMP (upward)
	gt.put_label(p, g)
	gt.put_label(p, j)

	// --- gravity, then land on / rest against the ground ---
	gt.set(p, grounded, 0)
	gt.add(p, vy, GRAVITY)
	gt.add_var(p, py, vy)
	land := gt.if_solid(p, LEVEL(p), COLS, px, 8, py, 16, SOLID) // solid just below the feet?
	gt.snap_to_tile_below(p, py, 16)
	gt.set(p, vy, 0)
	gt.set(p, grounded, 1)
	gt.put_label(p, land)

	// --- draw the level, then the player on top ---
	gt.draw_tilemap(p, LEVEL(p), COLS, ROWS, 0, 0, TILE_GY)
	gt.draw_objects(p, 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "platformer.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_BLUE, gt.SAT_MORE, 4), // sky
			setup = setup,
			frame = frame,
		},
	)
}
