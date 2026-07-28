package gametank

// =============================================================================
// Timing: a frame counter, countdown timers, and periodic events
// =============================================================================
//
// build_game bumps a free-running frame counter (GT_FRAME) once per frame. On top
// of it:
//   * frame_var()               — the counter as a Var, for phase effects
//   * tick(t)                   — a saturating countdown (a one-shot / cooldown)
//   * every_n_frames(t, n)      — run a block once every n frames (periodic)
//
// A countdown timer is just a Var: timer_set it to a frame count, tick it every
// frame (it stops at 0 rather than wrapping like dec), and gate on it with
// if_nonzero (still counting) / if_zero (elapsed).

// The free-running frame counter as a Var (wraps every 256 frames). Only bumped
// under build_game. Test it like any Var — e.g. blink with if_pressed(p, frame_var(),
// 0x10) — or display it with draw_number.
frame_var :: proc() -> Var { return Var{addr = u16(GT_FRAME)} }

// Start (or restart) a countdown timer: t = frames.
timer_set :: proc(p: ^Program, t: Var, frames: u8) { set(p, t, frames) }

// Advance a countdown timer one frame: decrement `t` unless it is already 0, so it
// settles at 0 instead of wrapping around (which plain dec would). Gate behaviour
// on it with if_nonzero (still running) or if_zero (done).
tick :: proc(p: ^Program, t: Var) {
	running := if_nonzero(p, t)   // already 0 -> leave it
	dec(p, t)
	put_label(p, running)
}

// Begin a block that runs once every `n` frames, driven by the counter Var `t`.
// Emit the periodic work after this call, then close with put_label(p, <id>).
// Initialise `t` once in setup (e.g. timer_set(p, t, n)); each time it counts down
// to 0 the block runs and `t` reloads to `n`. `n` must be >= 1.
//
//   spawn := gt.every_n_frames(p, spawn_timer, 90)
//   ... spawn something ...
//   gt.put_label(p, spawn)
every_n_frames :: proc(p: ^Program, t: Var, n: u8) -> u32 {
	dec(p, t)
	skip := anon_fwd(p)
	ld_var(p, .LDA, t)
	emit_branch_id(p, .BNE, skip)   // not time yet -> skip the block
	set(p, t, n)                    // reload for the next cycle
	return skip                     // t hit 0: fall through into the block
}
