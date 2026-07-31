package main

// A tiny game, built entirely on the gametank runtime API — no hand-written 6502:
// move the player with the D-pad and touch the coin to collect it. The coin
// teleports to a new spot, your score ticks up, and a little two-note jingle
// plays. Tap A to reroll the coin (rate-limited by a cooldown), and if you dawdle
// the coin escapes on its own every few seconds. A frame counter ticks bottom-left.
//
//   odin run examples/game       # from the repo root (or `odin run .` from this folder); writes game.gtr
//
// Sprites (examples/game/sprites.gtg.deflate): player 16x16 at sheet (0,0), coin
// at (16,0), and the digit/letter font grid at row 16.

import gt "../../gametank"

PLAYER  :: u8(0)        // object-table slots
COIN    :: u8(1)
POS_MAX :: u8(128 - 16) // 112: keep a 16px sprite fully on screen
FONT_GY :: u8(16)       // font grid row in the sprite sheet

JINGLE_N1    :: u8(83) // coin jingle: first note (B5)
JINGLE_N2    :: u8(88) // second note (E6), a perfect fourth up
JINGLE_LEN   :: u8(14) // total frames
JINGLE_N2_AT :: u8(10) // switch to note 2 when the countdown reaches this

ESCAPE :: u8(180)      // coin relocates on its own this often (~3s at 60fps)
REROLL :: u8(20)       // frames you must wait between manual A-rerolls

held, pressed, jingle, cooldown, escape: gt.Var
score: gt.Var16   // 16-bit so it counts past 255

setup :: proc(p: ^gt.Program) {
	gt.blob(p, "sprites", #load("sprites.gtg.deflate"))
	gt.inflate_asset(p, "sprites")
	gt.set_object(p, PLAYER, 56, 56, 0, 0)   // player sprite at sheet (0,0)
	gt.set_object(p, COIN,   96, 32, 16, 0)  // coin sprite at sheet (16,0)
	held     = gt.alloc_var(p)
	pressed  = gt.alloc_var(p)
	jingle   = gt.alloc_var(p)
	cooldown = gt.alloc_var(p)
	escape   = gt.alloc_var(p)
	score    = gt.alloc_var16(p)
	gt.set(p, held, 0)             // clean first frame for edge detection
	gt.set16(p, score, 0)
	gt.set(p, jingle, 0)           // no jingle playing yet
	gt.set(p, cooldown, 0)         // reroll ready immediately
	gt.timer_set(p, escape, ESCAPE)
	gt.random_seed(p, 0x7E)        // nonzero RNG seed
}

frame :: proc(p: ^gt.Program) {
	gt.poll_gamepad1(p, held, pressed) // held = buttons down, pressed = just-pressed this frame
	gt.random(p)                       // churn the RNG every frame so coins land unpredictably

	gt.move_dec(p, held, gt.PAD_UP,    gt.OBJ_Y + u16(PLAYER), 0)
	gt.move_inc(p, held, gt.PAD_DOWN,  gt.OBJ_Y + u16(PLAYER), POS_MAX)
	gt.move_dec(p, held, gt.PAD_LEFT,  gt.OBJ_X + u16(PLAYER), 0)
	gt.move_inc(p, held, gt.PAD_RIGHT, gt.OBJ_X + u16(PLAYER), POS_MAX)

	// tap A to reroll the coin — edge-triggered, and rate-limited by a cooldown timer
	gt.tick(p, cooldown)                       // count the cooldown down toward 0
	ready := gt.if_zero(p, cooldown)           // only act once it has elapsed
	tap := gt.if_just_pressed(p, pressed, gt.PAD_A)
	place_coin(p)
	gt.set(p, cooldown, REROLL)                // start cooling down again
	gt.put_label(p, tap)
	gt.put_label(p, ready)

	// if you're too slow, the coin escapes on its own every ESCAPE frames
	escaped := gt.every_n_frames(p, escape, ESCAPE)
	place_coin(p)
	gt.put_label(p, escaped)

	// touch the coin -> collect it
	miss := gt.if_overlap(p, PLAYER, COIN)
	place_coin(p)                       // teleport to a new random cell
	gt.inc16(p, score)                  // +1 (16-bit: counts well past 255)
	gt.audio_note(p, JINGLE_N1)         // start the jingle
	gt.set(p, jingle, JINGLE_LEN)
	gt.put_label(p, miss)

	jingle_tick(p)

	gt.draw_objects(p, 2)
	gt.draw_text(p, 8, 8, "SCORE", FONT_GY)
	gt.draw_number16(p, 56, 8, score, FONT_GY, digits = 4)
	gt.draw_number(p, 8, 112, gt.frame_var(), FONT_GY, digits = 3) // frame counter, bottom-left
}

// Teleport the coin (object 1) to a random 16px-aligned cell on screen.
place_coin :: proc(p: ^gt.Program) {
	gt.random_into(p, gt.OBJ_X + u16(COIN), 0x70) // 0..112
	gt.random_into(p, gt.OBJ_Y + u16(COIN), 0x60) // 0..96
}

// Advance the two-note coin jingle one frame: count down, switch to the higher
// note partway through, and silence the voice when it reaches the end.
jingle_tick :: proc(p: ^gt.Program) {
	playing := gt.if_nonzero(p, jingle)   // only work while the jingle is counting
	gt.tick(p, jingle)                    // count down (saturating at 0)
	at2 := gt.if_eq(p, jingle, JINGLE_N2_AT)
	gt.audio_note(p, JINGLE_N2)
	gt.put_label(p, at2)
	done := gt.if_zero(p, jingle)         // just reached 0 -> silence the voice
	gt.audio_silence(p)
	gt.put_label(p, done)
	gt.put_label(p, playing)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "game.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			audio = true,
			setup = setup,
			frame = frame,
		},
	)
}
