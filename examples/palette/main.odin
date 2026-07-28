package main

// Palette reference: fills the framebuffer with all 256 GameTank colors as a 16x16
// grid of 8x8 blocks — the byte at grid (col, row) is row*16 + col (reading order).
// Handy to see the real DAC palette, and used to extract it (screenshot + sample).
//
//   odin run examples/palette     # from the repo root; writes palette.gtr

import gt "../../gametank"

DST  :: u8(0x12) // $12/$13: framebuffer write pointer
BASE :: u8(0x14) // color base for the current 8-row band

assemble :: proc(p: ^gt.Program) {
	gt.boot(p, gt.DMA_CPU_TO_VRAM, 0) // CPU writes the framebuffer, show page 0

	// dst = VRAM ($4000)
	gt.emit_imm(p, .LDA, 0x00);            gt.emit_zp(p, .STA, DST)
	gt.emit_imm(p, .LDA, u8(gt.VRAM >> 8)); gt.emit_zp(p, .STA, DST + 1)
	gt.emit_imm(p, .LDX, 0) // row (0..127)

	row := gt.anon(p)
	// color base for this row = (row/8)*16 = (row & 0xF8) << 1
	gt.emit_impl(p, .TXA); gt.emit_imm(p, .AND, 0xF8); gt.emit_acc(p, .ASL); gt.emit_zp(p, .STA, BASE)
	gt.emit_imm(p, .LDY, 0) // column (0..127)
	col := gt.anon(p)
	gt.emit_impl(p, .TYA); gt.emit_acc(p, .LSR); gt.emit_acc(p, .LSR); gt.emit_acc(p, .LSR) // x/8
	gt.emit_impl(p, .CLC); gt.emit_zp(p, .ADC, BASE)                                        // color = base + x/8
	gt.emit_ind_y(p, .STA, DST)                                                             // write pixel (dst),y
	gt.emit_impl(p, .INY); gt.emit_imm(p, .CPY, 128); gt.emit_branch_id(p, .BNE, col)

	// dst += 128 (next framebuffer row)
	gt.emit_impl(p, .CLC)
	gt.emit_zp(p, .LDA, DST);     gt.emit_imm(p, .ADC, 128); gt.emit_zp(p, .STA, DST)
	gt.emit_zp(p, .LDA, DST + 1); gt.emit_imm(p, .ADC, 0);   gt.emit_zp(p, .STA, DST + 1)
	gt.emit_impl(p, .INX); gt.emit_imm(p, .CPX, 128); gt.emit_branch_id(p, .BNE, row)

	gt.mark(p, "forever")
	gt.emit_jump(p, "forever")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "palette.gtr"}, assemble)
}
