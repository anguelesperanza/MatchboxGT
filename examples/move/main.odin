package main

// D-pad controlled box on the GameTank, built with the `gametank` framework.
// Move the box with the directional pad; press Start to recenter it.
//
//   odin run examples/move        # from the repo root; writes move.gtr

import gt "../../gametank"

// Zero-page variables (framework reserves $00-$0F; app vars start at $10).
PLAYER_X :: u8(0x10)
PLAYER_Y :: u8(0x11)
INPUT    := gt.Var{addr = 0x12} // the gamepad Var read_gamepad1/if_pressed use

BOX_SIZE :: u8(16)
POS_MAX  :: u8(128 - 16) // furthest top-left corner that keeps the box on screen
CENTER   :: u8(56)       // (128 - 16) / 2, roughly

// Decrement `pos` if `mask` is held and we're not already at 0.
move_neg :: proc(p: ^gt.Program, mask, pos: u8) {
	gt.emit_imm(p, .LDA, mask); gt.emit_zp(p, .BIT, u8(INPUT.addr))
	skip := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BEQ, skip)   // button not held
	gt.emit_zp(p, .LDA, pos)
	gt.emit_branch_id(p, .BEQ, skip)   // already at 0 -> don't underflow
	gt.emit_zp(p, .DEC, pos)
	gt.put_label(p, skip)
}

// Increment `pos` if `mask` is held and we're below `maxv`.
move_pos :: proc(p: ^gt.Program, mask, pos, maxv: u8) {
	gt.emit_imm(p, .LDA, mask); gt.emit_zp(p, .BIT, u8(INPUT.addr))
	skip := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BEQ, skip)   // button not held
	gt.emit_zp(p, .LDA, pos)
	gt.emit_imm(p, .CMP, maxv)
	gt.emit_branch_id(p, .BCS, skip)   // pos >= max -> don't move
	gt.emit_zp(p, .INC, pos)
	gt.put_label(p, skip)
}

// Colorfill the box at (PLAYER_X, PLAYER_Y), reading coords from zero page.
draw_box :: proc(p: ^gt.Program, color: u8) {
	gt.blit_begin(p, gt.DMA_COLORFILL | gt.DMA_OPAQUE)
	gt.emit_zp(p, .LDA, PLAYER_X); gt.emit_abs(p, .STA, gt.BLIT_VX)
	gt.emit_zp(p, .LDA, PLAYER_Y); gt.emit_abs(p, .STA, gt.BLIT_VY)
	gt.emit_imm(p, .LDA, BOX_SIZE)
	gt.emit_abs(p, .STA, gt.BLIT_WIDTH)
	gt.emit_abs(p, .STA, gt.BLIT_HEIGHT)
	gt.emit_imm(p, .LDA, 0xFF - color) // colorfill wants the inverted byte
	gt.emit_abs(p, .STA, gt.BLIT_COLOR)
	gt.blit_go(p)
	gt.blit_end(p)
}

assemble :: proc(p: ^gt.Program) {
	bg  := gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1) // dark indigo field
	// Hue $C0 renders as cyan on the DAC (the SDK's HUE_* labels don't all match
	// what the emulator shows — $C0 is true cyan, $E0/"HUE_CYAN" shows green).
	box := gt.color(0xC0, gt.SAT_FULL, 6)          // bright aqua-cyan box

	gt.boot_double_buffered(p)
	gt.set_zp(p, PLAYER_X, CENTER)
	gt.set_zp(p, PLAYER_Y, CENTER)

	// Clear both buffers so neither shows garbage.
	gt.clear_screen(p, bg); gt.flip(p)
	gt.clear_screen(p, bg); gt.flip(p)

	// --- main loop -----------------------------------------------------------
	gt.mark(p, "loop")
	gt.read_gamepad1(p, INPUT)

	move_neg(p, gt.PAD_UP,    PLAYER_Y)
	move_pos(p, gt.PAD_DOWN,  PLAYER_Y, POS_MAX)
	move_neg(p, gt.PAD_LEFT,  PLAYER_X)
	move_pos(p, gt.PAD_RIGHT, PLAYER_X, POS_MAX)

	// Start recenters the box (uses the first-read A/Start data path).
	recenter := gt.if_pressed(p, INPUT, gt.PAD_START)
	gt.set_zp(p, PLAYER_X, CENTER)
	gt.set_zp(p, PLAYER_Y, CENTER)
	gt.put_label(p, recenter)

	gt.clear_screen(p, bg)   // clear the hidden buffer
	draw_box(p, box)
	gt.await_vsync(p)
	gt.flip(p)
	gt.emit_jump(p, "loop")

	// --- NMI handler (out of the execution path) ----------------------------
	gt.vsync_nmi(p, "nmi")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "move.gtr", nmi = "nmi"}, assemble)
}
