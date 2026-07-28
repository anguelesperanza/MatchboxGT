package gametank

// =============================================================================
// Game-loop runtime + object table
// =============================================================================
//
// A thin scaffold over the boilerplate every example repeats: boot, clear both
// buffers, then loop { clear, update+draw, wait vblank, flip } forever, with the
// vsync NMI installed (and, if Game.audio is set, the ACP mixer started). You
// supply two procs — `setup` (run once) and `frame` (run every frame) — via a
// Game and build_game.
//
// Plus a tiny object table: up to 256 sprites stored in parallel RAM arrays, drawn
// in one call, with optional per-object velocity (integrate + wall-bounce) and an
// AABB overlap test for pickups/hits. Objects live in RAM pages $0300-$08FF
// (X, Y, GX, GY, VX, VY).

Game :: struct {
	bg:    u8,                   // background color; the frame starts pre-cleared to it
	audio: bool,                 // if set, the ACP mixer is started at boot (audio_init)
	setup: proc(p: ^Program),    // once, before video is up: load assets, init state
	frame: proc(p: ^Program),    // every frame: update + draw (screen already cleared)
}

@(private) GAME_NMI :: "__gt_game_nmi"
@(private) game_state: Game

// Build a standard double-buffered game around a Game. The scaffold does the
// reset, the two-buffer clear, the vblank-paced flip loop, and the NMI; Config
// still controls size/out/inflate.
build_game :: proc(cfg: Config, g: Game) -> bool {
	game_state = g
	c := cfg
	c.nmi = GAME_NMI
	return build_rom(c, game_gen)
}

@(private)
game_gen :: proc(p: ^Program) {
	emit_impl(p, .SEI)
	emit_impl(p, .CLD)
	emit_imm(p, .LDX, 0xFF)
	emit_impl(p, .TXS)
	if game_state.audio { audio_init(p) }               // start the ACP mixer before anything else
	if game_state.setup != nil { game_state.setup(p) }  // assets load before video comes up

	boot_double_buffered(p)
	clear_screen(p, game_state.bg); flip(p)
	clear_screen(p, game_state.bg); flip(p)

	mark(p, "__gt_game_loop")
	emit_zp(p, .INC, GT_FRAME)                           // free-running frame counter (timer.odin)
	clear_screen(p, game_state.bg)
	if game_state.frame != nil { game_state.frame(p) }
	await_vsync(p)
	flip(p)
	emit_jump(p, "__gt_game_loop")

	vsync_nmi(p, GAME_NMI)
}

// -----------------------------------------------------------------------------
// Clamped movement — decrement/increment a RAM byte while a button is held.
// `input` is a read_gamepad / poll_gamepad Var; `addr` is any RAM byte (OBJ_X + i).
// -----------------------------------------------------------------------------

move_dec :: proc(p: ^Program, input: Var, mask: u8, addr: u16, min: u8) {
	emit_imm(p, .LDA, mask); ld_var(p, .BIT, input)
	skip := anon_fwd(p)
	emit_branch_id(p, .BEQ, skip)          // button not held
	emit_abs(p, .LDA, addr); emit_imm(p, .CMP, min + 1)
	emit_branch_id(p, .BCC, skip)          // at/below min
	emit_abs(p, .DEC, addr)
	put_label(p, skip)
}

move_inc :: proc(p: ^Program, input: Var, mask: u8, addr: u16, max: u8) {
	emit_imm(p, .LDA, mask); ld_var(p, .BIT, input)
	skip := anon_fwd(p)
	emit_branch_id(p, .BEQ, skip)
	emit_abs(p, .LDA, addr); emit_imm(p, .CMP, max)
	emit_branch_id(p, .BCS, skip)          // at/above max
	emit_abs(p, .INC, addr)
	put_label(p, skip)
}

// -----------------------------------------------------------------------------
// Game-loop audio: play a note while an input is held, silence it otherwise.
// Pairs with move_dec/move_inc for a one-call movement "footstep" tone. Needs
// Game.audio = true (so the ACP mixer is running). `input` is a read_gamepad Var;
// `mask` is any OR of PAD_* bits; `voice` is 0..3.
// -----------------------------------------------------------------------------

sound_while :: proc(p: ^Program, input: Var, mask, voice, note, vol: u8) {
	emit_imm(p, .LDA, mask); ld_var(p, .BIT, input)
	quiet := anon_fwd(p)
	emit_branch_id(p, .BEQ, quiet)         // nothing held -> silence the voice
	voice_note(p, voice, note, vol)
	done := anon_fwd(p)
	emit_jump_id(p, done)
	put_label(p, quiet)
	voice_off(p, voice)
	put_label(p, done)
}

// -----------------------------------------------------------------------------
// Object table: parallel RAM arrays indexed 0..count-1. Set Y >= OBJ_HIDDEN to
// hide an object. Each object is drawn as a 16x16 sprite from (GX,GY).
// -----------------------------------------------------------------------------

OBJ_X      :: u16(0x0300)
OBJ_Y      :: u16(0x0400)
OBJ_GX     :: u16(0x0500)
OBJ_GY     :: u16(0x0600)
OBJ_VX     :: u16(0x0700) // signed per-object X velocity (see move_objects)
OBJ_VY     :: u16(0x0800) // signed per-object Y velocity
OBJ_HIDDEN :: u8(0xF0)

// Set one object's position + sprite (all constants).
set_object :: proc(p: ^Program, index, x, y, gx, gy: u8) {
	emit_imm(p, .LDA, x);  emit_abs(p, .STA, OBJ_X + u16(index))
	emit_imm(p, .LDA, y);  emit_abs(p, .STA, OBJ_Y + u16(index))
	emit_imm(p, .LDA, gx); emit_abs(p, .STA, OBJ_GX + u16(index))
	emit_imm(p, .LDA, gy); emit_abs(p, .STA, OBJ_GY + u16(index))
}

// Hide an object (draw_objects and move_objects skip it) by parking its Y off
// the bottom of the playfield. The canonical "collected / destroyed" response.
hide_object :: proc(p: ^Program, index: u8) {
	emit_imm(p, .LDA, OBJ_HIDDEN)
	emit_abs(p, .STA, OBJ_Y + u16(index))
}

// Blit every visible object (Y < OBJ_HIDDEN) as a 16x16 sprite.
draw_objects :: proc(p: ^Program, count: u8) {
	emit_imm(p, .LDX, count - 1)
	loop := anon(p)
	emit_abs_x(p, .LDA, OBJ_Y)
	emit_imm(p, .CMP, OBJ_HIDDEN)
	skip := anon_fwd(p)
	emit_branch_id(p, .BCS, skip)           // hidden
	blit_begin(p, DMA_GCARRY)               // (does not touch X)
	emit_abs_x(p, .LDA, OBJ_X);  emit_abs(p, .STA, BLIT_VX)
	emit_abs_x(p, .LDA, OBJ_Y);  emit_abs(p, .STA, BLIT_VY)
	emit_abs_x(p, .LDA, OBJ_GX); emit_abs(p, .STA, BLIT_GX)
	emit_abs_x(p, .LDA, OBJ_GY); emit_abs(p, .STA, BLIT_GY)
	emit_imm(p, .LDA, 16); emit_abs(p, .STA, BLIT_WIDTH); emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)
	put_label(p, skip)
	emit_impl(p, .DEX)
	emit_branch_id(p, .BPL, loop)
}

// -----------------------------------------------------------------------------
// Sprite animation: cycle an object's source cell through a strip of 16px frames
// laid out horizontally in sprite RAM (X = base_gx, base_gx+16, ...). The current
// frame is just the object's GX, so no extra per-object state is needed.
// -----------------------------------------------------------------------------

// Advance object `index` to the next frame in its strip, wrapping after `frames`
// back to `base_gx`. Call it on a timer (via animate_object, or gate it yourself
// with every_n_frames) — not every frame. `base_gx + frames*16` must be <= 255.
next_frame :: proc(p: ^Program, index, base_gx, frames: u8) {
	emit_abs(p, .LDA, OBJ_GX + u16(index))
	emit_impl(p, .CLC); emit_imm(p, .ADC, 16)
	emit_imm(p, .CMP, base_gx + frames * 16)  // ran off the end of the strip?
	store := anon_fwd(p)
	emit_branch_id(p, .BCC, store)            // no -> keep the advanced cell
	emit_imm(p, .LDA, base_gx)                // yes -> wrap to the first frame
	put_label(p, store)
	emit_abs(p, .STA, OBJ_GX + u16(index))
}

// Animate object `index` through its `frames`-frame strip (16px cells from
// base_gx), advancing one frame every `period` game-frames. `timer` is a counter
// Var you allocate and init once in setup with timer_set(p, timer, period). The
// object's GY (set by set_object) picks which row the strip lives on.
animate_object :: proc(p: ^Program, index: u8, timer: Var, base_gx, frames, period: u8) {
	skip := every_n_frames(p, timer, period)
	next_frame(p, index, base_gx, frames)
	put_label(p, skip)
}

// -----------------------------------------------------------------------------
// Collision: axis-aligned overlap test between two objects (constant indices).
// -----------------------------------------------------------------------------

// Emit |A - B| into the accumulator for the object bytes at base+a / base+b,
// so a following CMP #size / BCS decides overlap on that axis.
@(private)
abs_delta :: proc(p: ^Program, base: u16, a, b: u8) {
	emit_abs(p, .LDA, base + u16(a)); emit_impl(p, .SEC); emit_abs(p, .SBC, base + u16(b))
	pos := anon_fwd(p)
	emit_branch_id(p, .BCS, pos)            // A >= B: difference already positive
	emit_imm(p, .EOR, 0xFF); emit_imm(p, .ADC, 0x01) // A < B: negate (carry is clear here)
	put_label(p, pos)
}

// Begin an "if objects a and b overlap" block. The test is AABB on two `size`-px
// boxes (16 for the default object sprite): they overlap when both |Xa-Xb| < size
// and |Ya-Yb| < size. Emit the collision response after this call, then close the
// block with put_label(p, <returned id>):
//
//   hit := gt.if_overlap(p, 0, coin)
//   gt.hide_object(p, coin)          // ... what happens on a hit ...
//   gt.put_label(p, hit)
//
// Both indices are build-time constants. Clobbers A. A hidden object (Y >=
// OBJ_HIDDEN) is far off-screen, so it naturally stops registering hits.
if_overlap :: proc(p: ^Program, a, b: u8, size: u8 = 16) -> u32 {
	skip := anon_fwd(p)
	abs_delta(p, OBJ_X, a, b)
	emit_imm(p, .CMP, size); emit_branch_id(p, .BCS, skip) // |dx| >= size -> miss
	abs_delta(p, OBJ_Y, a, b)
	emit_imm(p, .CMP, size); emit_branch_id(p, .BCS, skip) // |dy| >= size -> miss
	return skip
}

// -----------------------------------------------------------------------------
// Per-object velocity: signed VX/VY added to the position each frame, bouncing
// off the playfield walls. Velocities live in OBJ_VX/OBJ_VY and are two's-
// complement (0xFF = -1). RAM is not zeroed at power-on, so set every active
// object's velocity (0 for stationary ones) before the first move_objects.
// -----------------------------------------------------------------------------

// Set one object's signed velocity (constants; e.g. set_velocity(p, i, 1, -2)).
set_velocity :: proc(p: ^Program, index: u8, vx, vy: i8) {
	emit_imm(p, .LDA, u8(vx)); emit_abs(p, .STA, OBJ_VX + u16(index))
	emit_imm(p, .LDA, u8(vy)); emit_abs(p, .STA, OBJ_VY + u16(index))
}

// Advance objects 0..count-1 by their velocity, bouncing at the [0, max] walls on
// each axis (max = the largest top-left coordinate that keeps the sprite in the
// playfield, e.g. 128-16). On a wall the axis velocity is negated in place and
// the object steps back inward the same frame, so it never sticks. Hidden objects
// (Y >= OBJ_HIDDEN) are skipped. Keep `max` < 255. Stationary objects (velocity 0)
// are safe to include — they don't move.
move_objects :: proc(p: ^Program, count: u8, max: u8) {
	emit_imm(p, .LDX, count - 1)
	loop := anon(p)
	emit_abs_x(p, .LDA, OBJ_Y); emit_imm(p, .CMP, OBJ_HIDDEN)
	skip := anon_fwd(p)
	emit_branch_id(p, .BCS, skip)           // hidden -> don't move it
	step_axis(p, OBJ_X, OBJ_VX, max)
	step_axis(p, OBJ_Y, OBJ_VY, max)
	put_label(p, skip)
	emit_impl(p, .DEX)
	emit_branch_id(p, .BPL, loop)
}

// One axis of move_objects (object index in X): pos += vel; if the result leaves
// [0, max], negate vel and re-step from the original pos. `max`+1 as an unsigned
// compare catches both walls — an underflow past 0 wraps to >= 0xFF, which is
// also > max. Assumes the object index is in the X register.
@(private)
step_axis :: proc(p: ^Program, pos, vel: u16, max: u8) {
	emit_abs_x(p, .LDA, pos); emit_impl(p, .CLC); emit_abs_x(p, .ADC, vel)
	store := anon_fwd(p)
	emit_imm(p, .CMP, max + 1); emit_branch_id(p, .BCC, store) // in [0, max] -> keep
	emit_imm(p, .LDA, 0x00); emit_impl(p, .SEC); emit_abs_x(p, .SBC, vel); emit_abs_x(p, .STA, vel) // vel = -vel
	emit_abs_x(p, .LDA, pos); emit_impl(p, .CLC); emit_abs_x(p, .ADC, vel) // step inward
	put_label(p, store)
	emit_abs_x(p, .STA, pos)
}
