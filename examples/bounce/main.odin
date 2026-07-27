package main

// A box bouncing around the screen — a double-buffered, blitter-drawn animation
// on the GameTank, built with the `gametank` framework.
//
//   odin run examples/bounce      # from the repo root; writes bounce.gtr
//
// Each frame: wait for vblank, flip buffers, move the box, then redraw the
// background and the box into the now-hidden page with colorfill blits.

import gt "../../gametank"

// Zero-page variables (framework reserves $00-$0F, so app vars start at $10).
BOX_X :: u8(0x10)
BOX_Y :: u8(0x11)
VEL_X :: u8(0x12)
VEL_Y :: u8(0x13)

BOX_SIZE :: u8(16)
X_LIMIT  :: u8(128 - 16 + 1) // bounce when BOX_X reaches this (0..112 valid)
Y_LIMIT  :: u8(100 - 16 + 1) // visible height ~100 (0..84 valid)

// Advance one axis by its velocity and bounce (reverse + step back) at the edge.
// `limit` is the first out-of-range value; the low bound (wrap to >=128) is
// covered by the same unsigned compare.
update_axis :: proc(p: ^gt.Program, pos, vel, limit: u8) {
	gt.emit_zp(p, .LDA, pos)
	gt.emit_impl(p, .CLC)
	gt.emit_zp(p, .ADC, vel)
	gt.emit_zp(p, .STA, pos)
	gt.emit_imm(p, .CMP, limit)
	in_range := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BCC, in_range) // pos < limit -> still on screen

	// out of range: negate velocity (two's complement) and undo the step
	gt.emit_zp(p, .LDA, vel)
	gt.emit_imm(p, .EOR, 0xFF)
	gt.emit_impl(p, .CLC)
	gt.emit_imm(p, .ADC, 0x01)
	gt.emit_zp(p, .STA, vel)
	gt.emit_zp(p, .LDA, pos)
	gt.emit_impl(p, .CLC)
	gt.emit_zp(p, .ADC, vel)
	gt.emit_zp(p, .STA, pos)

	gt.put_label(p, in_range)
}

// Colorfill the box at (BOX_X, BOX_Y), reading the coordinates from zero page.
draw_box :: proc(p: ^gt.Program, color: u8) {
	gt.blit_begin(p, gt.DMA_COLORFILL | gt.DMA_OPAQUE)
	gt.emit_zp(p, .LDA, BOX_X);  gt.emit_abs(p, .STA, gt.BLIT_VX)
	gt.emit_zp(p, .LDA, BOX_Y);  gt.emit_abs(p, .STA, gt.BLIT_VY)
	gt.emit_imm(p, .LDA, BOX_SIZE)
	gt.emit_abs(p, .STA, gt.BLIT_WIDTH)
	gt.emit_abs(p, .STA, gt.BLIT_HEIGHT)
	gt.emit_imm(p, .LDA, 0xFF - color) // colorfill wants the inverted byte
	gt.emit_abs(p, .STA, gt.BLIT_COLOR)
	gt.blit_go(p)
	gt.blit_end(p)
}

assemble :: proc(p: ^gt.Program) {
	bg  := gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1) // dark indigo background
	box := gt.color(gt.HUE_YELLOW, gt.SAT_FULL, 4) // bright yellow box

	// Boot double-buffered: draw page starts opposite the displayed page.
	gt.boot_double_buffered(p)

	// Initial box state: near the middle, moving down-right.
	gt.set_zp(p, BOX_X, 0x40)
	gt.set_zp(p, BOX_Y, 0x30)
	gt.set_zp(p, VEL_X, 0x01)
	gt.set_zp(p, VEL_Y, 0x01)

	// Paint both buffers with the background so neither shows garbage.
	gt.clear_screen(p, bg)
	gt.flip(p)
	gt.clear_screen(p, bg)
	gt.flip(p)

	// --- main loop: draw the hidden buffer, wait for vblank, then flip -------
	gt.mark(p, "loop")
	update_axis(p, BOX_X, VEL_X, X_LIMIT)
	update_axis(p, BOX_Y, VEL_Y, Y_LIMIT)
	gt.clear_screen(p, bg) // clear the hidden buffer
	draw_box(p, box)                    // draw the box on top
	gt.await_vsync(p)                   // wait for vblank
	gt.flip(p)                          // reveal the freshly-drawn frame
	gt.emit_jump(p, "loop")

	// --- NMI handler (out of the execution path; reached only via the vector)
	gt.vsync_nmi(p, "nmi")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "bounce.gtr", nmi = "nmi"}, assemble)
}
