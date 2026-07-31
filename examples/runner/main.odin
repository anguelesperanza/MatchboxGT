package main

// Parallax endless-runner base: three background layers (mountains, hills, ground)
// scroll left at different speeds for depth, while a little runner animates in place
// and jumps with A. Add obstacles + collision + a score and you have a game.
//
//   odin run examples/runner     # from the repo root (or `odin run .` from this folder); writes runner.gtr
//
// Sheet (examples/runner/runner.gtg.deflate, from make_runner): 4 run frames at
// gy 0, and 128-wide seamless strips for mountains (gy 16), hills (gy 40), ground
// (gy 64).

import gt "../../gametank"

PLAYER_X :: u8(24)
GROUND_Y :: u8(48)  // player's y when standing on the ground
JUMP     :: 8       // initial upward speed
GRAVITY  :: u8(1)
RUN_STEP :: u8(6)   // animation: advance a run frame every 6 game-frames

MTN_Y  :: u8(20) // where each layer sits on screen
HILL_Y :: u8(40)
GND_Y  :: u8(60)

held, pressed, vy, anim, mtn, hill, gnd: gt.Var
py := gt.Var{addr = gt.OBJ_Y + 0} // the player's y IS object 0's Y byte

setup :: proc(p: ^gt.Program) {
	gt.blob(p, "sheet", #load("runner.gtg.deflate"))
	gt.inflate_asset(p, "sheet")
	gt.set_object(p, 0, PLAYER_X, GROUND_Y, 0, 0) // runner: frame 0 at (0,0)
	held = gt.alloc_var(p); pressed = gt.alloc_var(p); vy = gt.alloc_var(p)
	anim = gt.alloc_var(p); mtn = gt.alloc_var(p); hill = gt.alloc_var(p); gnd = gt.alloc_var(p)
	gt.set(p, held, 0)
	gt.set(p, vy, 0)
	gt.set(p, mtn, 0); gt.set(p, hill, 0); gt.set(p, gnd, 0)
	gt.timer_set(p, anim, RUN_STEP)
}

frame :: proc(p: ^gt.Program) {
	gt.poll_gamepad1(p, held, pressed)

	// jump: on A, if standing on the ground, launch upward
	tap := gt.if_just_pressed(p, pressed, gt.PAD_A)
	grounded := gt.if_eq(p, py, GROUND_Y)
	gt.set(p, vy, u8(256 - JUMP)) // vy = -JUMP
	gt.put_label(p, grounded)
	gt.put_label(p, tap)

	// integrate: move by velocity, then land (clamp) or apply gravity
	gt.add_var(p, py, vy)
	land := gt.if_ge(p, py, GROUND_Y)
	gt.set(p, py, GROUND_Y); gt.set(p, vy, 0)
	air := gt.otherwise(p, land)
	gt.add(p, vy, GRAVITY)
	gt.put_label(p, air)

	// advance the parallax scroll (different speeds = depth) and the run cycle
	gt.layer_scroll(p, mtn, 1)
	gt.layer_scroll(p, hill, 2)
	gt.layer_scroll(p, gnd, 4)
	gt.animate_object(p, 0, anim, 0, 4, RUN_STEP)

	// draw back-to-front, then the runner on top
	gt.draw_layer(p, 16, MTN_Y, 24, mtn)
	gt.draw_layer(p, 40, HILL_Y, 24, hill)
	gt.draw_layer(p, 64, GND_Y, 24, gnd)
	gt.draw_objects(p, 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "runner.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_BLUE, gt.SAT_MORE, 4), // sky
			setup = setup,
			frame = frame,
		},
	)
}
