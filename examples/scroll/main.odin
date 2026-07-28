package main

// Scrolling tilemap: an 8x6-tile window onto a larger 12x10 map. Hold a direction
// to scroll the camera over the map (one tile at a time, at a steady rate). This is
// tile-aligned scrolling — the view moves a whole tile per step, which is exactly
// what grid-step games (roguelikes, tile RPGs) want.
//
//   odin run examples/scroll     # from the repo root; writes scroll.gtr
//
// Reuses the tilemap tileset (examples/tilemap/tiles.gtg.deflate): tile 0 = floor,
// tile 1 = wall. The map is a pillar-grid dungeon generated at build time.

import gt "../../gametank"

MAP_COLS  :: 12
MAP_ROWS  :: 10
VIEW_COLS :: u8(8)
VIEW_ROWS :: u8(6)
CAM_X_MAX :: u8(MAP_COLS) - VIEW_COLS // furthest the camera can scroll right
CAM_Y_MAX :: u8(MAP_ROWS) - VIEW_ROWS
TILE_GY   :: u8(0)
SPEED     :: u8(6) // scroll one tile every 6 frames while held

input, cam_x, cam_y, timer: gt.Var
scroll_map: [MAP_COLS * MAP_ROWS]u8

// A pillar-grid dungeon: wall border plus a wall on every even interior cell.
build_map :: proc() {
	for r in 0 ..< MAP_ROWS {
		for c in 0 ..< MAP_COLS {
			wall := r == 0 || r == MAP_ROWS - 1 || c == 0 || c == MAP_COLS - 1 || (r % 2 == 0 && c % 2 == 0)
			if wall {
				scroll_map[r * MAP_COLS + c] = 1
			} else {
				scroll_map[r * MAP_COLS + c] = 0
			}
		}
	}
}

setup :: proc(p: ^gt.Program) {
	gt.blob_file(p, "tiles", "examples/tilemap/tiles.gtg.deflate")
	gt.inflate_asset(p, "tiles")
	build_map()
	gt.blob(p, "map", scroll_map[:])
	input = gt.alloc_var(p)
	cam_x = gt.alloc_var(p)
	cam_y = gt.alloc_var(p)
	timer = gt.alloc_var(p)
	gt.set(p, cam_x, 0)
	gt.set(p, cam_y, 0)
	gt.timer_set(p, timer, SPEED)
}

frame :: proc(p: ^gt.Program) {
	gt.read_gamepad1(p, input)
	// move the camera one tile at a controlled rate while a direction is held
	tick := gt.every_n_frames(p, timer, SPEED)
	gt.move_dec(p, input, gt.PAD_LEFT,  cam_x.addr, 0)
	gt.move_inc(p, input, gt.PAD_RIGHT, cam_x.addr, CAM_X_MAX)
	gt.move_dec(p, input, gt.PAD_UP,    cam_y.addr, 0)
	gt.move_inc(p, input, gt.PAD_DOWN,  cam_y.addr, CAM_Y_MAX)
	gt.put_label(p, tick)
	gt.draw_tilemap_view(p, gt.blob_addr(p, "map"), MAP_COLS, VIEW_COLS, VIEW_ROWS, cam_x, cam_y, 0, 0, TILE_GY)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "scroll.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}
