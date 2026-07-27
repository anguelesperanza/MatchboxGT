package gametank

// =============================================================================
// Gamepad input
// =============================================================================
//
// The GameTank uses Sega Genesis-style pads. Fully reading a port takes two
// successive reads of the same address: each read toggles the port's "select"
// line, and reading the *other* port resets this one's select to a known state.
//   * 1st read exposes: Up, Down, A, Start
//   * 2nd read exposes: Up, Down, Left, Right, B, C
// Buttons are grounded when pressed (active-low), so we invert to 1 = pressed.
//
// read_gamepad1/2 combine both reads into one byte using the PAD_* layout below.

PAD_RIGHT :: u8(0x01)
PAD_LEFT  :: u8(0x02)
PAD_DOWN  :: u8(0x04)
PAD_UP    :: u8(0x08)
PAD_B     :: u8(0x10)
PAD_C     :: u8(0x20)
PAD_A     :: u8(0x40)
PAD_START :: u8(0x80)

@(private)
read_pad :: proc(p: ^Program, port, other: u16, dest: u8) {
	emit_abs(p, .LDA, other)   // reading the other port resets this port's select
	emit_abs(p, .LDA, port)    // 1st read: A ($10) + Start ($20) (+ up/down)
	emit_imm(p, .EOR, 0xFF)    // active-low -> 1 = pressed
	emit_imm(p, .AND, 0x30)    // keep A + Start
	emit_acc(p, .ASL)
	emit_acc(p, .ASL)          // A -> $40 (PAD_A), Start -> $80 (PAD_START)
	emit_zp(p, .STA, dest)
	emit_abs(p, .LDA, port)    // 2nd read: U/D/L/R/B/C
	emit_imm(p, .EOR, 0xFF)
	emit_imm(p, .AND, 0x3F)    // bits 0-5 already match PAD_RIGHT..PAD_C
	emit_zp(p, .ORA, dest)
	emit_zp(p, .STA, dest)
}

// Read gamepad 1 into zero-page `dest`: a byte of PAD_* flags, 1 = pressed.
read_gamepad1 :: proc(p: ^Program, dest: u8) { read_pad(p, GAMEPAD1, GAMEPAD2, dest) }

// Read gamepad 2 into zero-page `dest`.
read_gamepad2 :: proc(p: ^Program, dest: u8) { read_pad(p, GAMEPAD2, GAMEPAD1, dest) }

// Begin an "if this button is pressed" block. Emit the guarded instructions
// after this call, then close the block with put_label(p, <returned id>):
//
//   skip := gt.if_pressed(p, INPUT, gt.PAD_START)
//   ... emit what happens when Start is held ...
//   gt.put_label(p, skip)
//
// (BIT sets Z from mask AND state; BEQ skips when the button isn't pressed.)
if_pressed :: proc(p: ^Program, state: u8, mask: u8) -> u32 {
	emit_imm(p, .LDA, mask)
	emit_zp(p, .BIT, state)
	skip := anon_fwd(p)
	emit_branch_id(p, .BEQ, skip)
	return skip
}

// -----------------------------------------------------------------------------
// Edge-triggered input: "held" vs "just pressed this frame". poll_gamepad reads
// the pad into a `held` Var and also fills a `pressed` Var with only the buttons
// that went down since last frame — so a tap fires once, not every frame it's
// held. Then test with if_held (on held) and if_just_pressed (on pressed).
// -----------------------------------------------------------------------------

// Read gamepad 1 into `held` (buttons down now) and set `pressed` to the buttons
// that transitioned up->down since the previous poll. Call once per frame with the
// SAME two Vars (held carries last frame's state between calls, so don't write to
// them yourself). Both must be zero-page Vars (the default from alloc_var). Init
// `held` to 0 once in setup so the first frame is clean. Clobbers A.
poll_gamepad1 :: proc(p: ^Program, held, pressed: Var) { poll_pad(p, GAMEPAD1, GAMEPAD2, held, pressed) }

// Read gamepad 2 the same way.
poll_gamepad2 :: proc(p: ^Program, held, pressed: Var) { poll_pad(p, GAMEPAD2, GAMEPAD1, held, pressed) }

@(private)
poll_pad :: proc(p: ^Program, port, other: u16, held, pressed: Var) {
	copy_var(p, pressed, held)               // stash last frame's held state in `pressed`
	read_pad(p, port, other, u8(held.addr))  // held = this frame's state
	ld_var(p, .LDA, pressed)                 // old
	emit_imm(p, .EOR, 0xFF)                  // ~old
	ld_var(p, .AND, held)                    // new AND ~old = buttons that just went down
	ld_var(p, .STA, pressed)
}

// Begin an "if any of `mask` is currently held" block (test a poll_gamepad `held`
// Var). Close with put_label(p, <returned id>), like if_pressed.
if_held :: proc(p: ^Program, held: Var, mask: u8) -> u32 {
	emit_imm(p, .LDA, mask)
	ld_var(p, .BIT, held)
	skip := anon_fwd(p)
	emit_branch_id(p, .BEQ, skip)
	return skip
}

// Begin an "if any of `mask` was just pressed this frame" block (test a
// poll_gamepad `pressed` Var). Close with put_label(p, <returned id>).
if_just_pressed :: proc(p: ^Program, pressed: Var, mask: u8) -> u32 {
	emit_imm(p, .LDA, mask)
	ld_var(p, .BIT, pressed)
	skip := anon_fwd(p)
	emit_branch_id(p, .BEQ, skip)
	return skip
}
