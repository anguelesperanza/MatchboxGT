package main

// Banking demo: bank 0 and bank 1 each store a marker color at $8000. Every
// second we flip which bank is mapped and fill the screen with the color read
// from $8000 — so the screen alternates cyan/gold, proving the bank switched.
//
//   odin run examples/banking    # from the repo root (or `odin run .` from this folder); writes banking.gtr (2 MiB)

import gt "../../gametank"

CUR    :: u8(0x10) // current bank (0 or 1)
FRAMES :: u8(0x11)
COL    :: u8(0x12) // color read from the mapped bank

// Fill the whole screen with the color held in a zero-page byte.
fill_screen :: proc(p: ^gt.Program, color_zp: u8) {
	gt.blit_begin(p, gt.DMA_COLORFILL | gt.DMA_OPAQUE)
	gt.emit_imm(p, .LDA, 0);   gt.emit_abs(p, .STA, gt.BLIT_VX); gt.emit_abs(p, .STA, gt.BLIT_VY)
	gt.emit_imm(p, .LDA, 127); gt.emit_abs(p, .STA, gt.BLIT_WIDTH); gt.emit_abs(p, .STA, gt.BLIT_HEIGHT)
	gt.emit_zp(p, .LDA, color_zp); gt.emit_imm(p, .EOR, 0xFF); gt.emit_abs(p, .STA, gt.BLIT_COLOR)
	gt.blit_go(p)
	gt.blit_end(p)
}

assemble :: proc(p: ^gt.Program) {
	cyan := gt.color(gt.HUE_BLUE, gt.SAT_FULL, 6)
	gold := gt.color(gt.HUE_YELLOW, gt.SAT_FULL, 4)

	// A marker byte at $8000 of each bank (its color).
	m0 := make([]u8, 1); m0[0] = cyan
	m1 := make([]u8, 1); m1[0] = gold
	gt.bank_blob(p, "b0", 0, m0)
	gt.bank_blob(p, "b1", 1, m1)

	gt.boot_double_buffered(p) // also inits the VIA bank lines
	gt.set_zp(p, CUR, 0)
	gt.set_zp(p, FRAMES, 0)
	gt.set_bank(p, 0)

	gt.mark(p, "loop")
	gt.emit_zp(p, .INC, FRAMES)
	gt.emit_zp(p, .LDA, FRAMES)
	gt.emit_imm(p, .CMP, 60)
	no_flip := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BNE, no_flip)
	gt.set_zp(p, FRAMES, 0)
	gt.emit_zp(p, .LDA, CUR); gt.emit_imm(p, .EOR, 0x01); gt.emit_zp(p, .STA, CUR)
	gt.set_bank_var(p, CUR)
	gt.put_label(p, no_flip)

	gt.emit_abs(p, .LDA, 0x8000); gt.emit_zp(p, .STA, COL) // read the bank's marker
	fill_screen(p, COL)
	gt.await_vsync(p)
	gt.flip(p)
	gt.emit_jump(p, "loop")

	gt.vsync_nmi(p, "nmi")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .Flash2M, out = "banking.gtr", nmi = "nmi"}, assemble)
}
