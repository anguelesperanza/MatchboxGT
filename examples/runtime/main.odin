package main

// The whole game on the runtime: move object 0 (the player) with the D-pad and
// collect three coins that drift around, bouncing off the walls. Touch a coin to
// collect it (it vanishes); collect all three and the field turns green. The
// scaffold (build_game) handles boot, the double-buffered vsync loop, the ACP
// mixer, and the NMI — all that's left is setup + a per-frame update/draw. Shows
// every runtime piece: input movement, per-object velocity, collision, a game-loop
// sound, and a game-state variable driving a conditional.
//
//   odin run examples/runtime    # from the repo root; writes runtime.gtr
//
// Sprites come from the game's sheet: player 16x16 at (0,0), coin at (16,0).
// A tone plays on voice 0 while the player is moving (turn emulator sound on).

import gt "../../gametank"

MAX     :: u8(128 - 16) // keep a 16px object on screen
DIRS    :: gt.PAD_UP | gt.PAD_DOWN | gt.PAD_LEFT | gt.PAD_RIGHT
STEP    :: u8(60)       // MIDI note for the footstep tone
COINS   :: 3            // objects 1..3
FONT_GY :: u8(16)       // digit strip row in the sprite sheet (0-9 across)

input:     gt.Var     // this frame's gamepad byte
collected: gt.Var     // how many coins have been picked up

setup :: proc(p: ^gt.Program) {
	gt.blob_file(p, "sprites", "examples/game/sprites.gtg.deflate")
	gt.inflate_asset(p, "sprites")
	gt.set_object(p, 0, 56, 56, 0, 0)   // player  (sheet 0,0)
	gt.set_object(p, 1, 24, 24, 16, 0)  // coins   (sheet 16,0)
	gt.set_object(p, 2, 96, 24, 16, 0)
	gt.set_object(p, 3, 56, 96, 16, 0)
	gt.set_velocity(p, 0,  0,  0)       // player is driven by the D-pad, not velocity
	gt.set_velocity(p, 1,  1,  1)       // coins drift on their own
	gt.set_velocity(p, 2, -1,  1)
	gt.set_velocity(p, 3,  1, -1)
	input     = gt.alloc_var(p)
	collected = gt.alloc_var(p)
	gt.set(p, collected, 0)
}

frame :: proc(p: ^gt.Program) {

	// Once every coin is collected, repaint the field green (the scaffold already
	// cleared it to the background, so this just overrides it while won).
	won := gt.if_eq(p, collected, COINS)
	gt.clear_screen(p, gt.color(gt.HUE_GREEN, gt.SAT_FULL, 3))
	gt.put_label(p, won)

	gt.read_gamepad1(p, input)
	gt.move_dec(p, input, gt.PAD_UP,    gt.OBJ_Y + 0, 0)
	gt.move_inc(p, input, gt.PAD_DOWN,  gt.OBJ_Y + 0, MAX)
	gt.move_dec(p, input, gt.PAD_LEFT,  gt.OBJ_X + 0, 0)
	gt.move_inc(p, input, gt.PAD_RIGHT, gt.OBJ_X + 0, MAX)
	gt.move_objects(p, 1 + COINS, MAX)          // integrate velocity + bounce (player v=0)
	for coin in u8(1) ..= u8(COINS) {           // collect coins the player touches
		hit := gt.if_overlap(p, 0, coin)
		gt.hide_object(p, coin)
		gt.inc(p, collected)                    // count the pickup (fires once — coin is now hidden)
		gt.put_label(p, hit)
	}
	gt.sound_while(p, input, DIRS, 0, STEP, 60)   // footstep tone while moving
	gt.draw_objects(p, 1 + COINS)
	gt.draw_number(p, 8, 8, collected, FONT_GY, digits = 1) // live coin count, top-left
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "runtime.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			audio = true,
			setup = setup,
			frame = frame,
		},
	)
}
