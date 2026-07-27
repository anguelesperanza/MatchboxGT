package gametank

// =============================================================================
// Direct-framebuffer helpers
// =============================================================================
//
// These write framebuffer pixels with the CPU (DMA_CPU_TO_VRAM set). It's the
// simplest way to draw and needs no sprite data, but it's the slowest — for
// anything that moves, prefer the blitter (blitter.odin). Flag setup lives in
// display.odin (set_dma / set_bank / boot).

// Fill the entire 16 KiB framebuffer with `color` via direct CPU writes.
//
// Requires CPU framebuffer access (boot/set_dma with DMA_CPU_TO_VRAM). Clobbers
// A, X, Y and the zero-page pointer at GT_PTR/GT_PTR+1.
clear_framebuffer :: proc(p: ^Program, color: u8) {
	emit_imm(p, .LDA, 0x00);          emit_zp(p, .STA, GT_PTR)      // ptr lo = $00
	emit_imm(p, .LDA, u8(VRAM >> 8)); emit_zp(p, .STA, GT_PTR + 1)  // ptr hi = $40
	emit_imm(p, .LDX, 0x40)                                          // 64 pages of 256
	emit_imm(p, .LDA, color)                                         // fill value
	emit_imm(p, .LDY, 0x00)
	loop := anon(p)
	emit_ind_y(p, .STA, GT_PTR)        // sta (ptr),y
	emit_impl(p, .INY)
	emit_branch_id(p, .BNE, loop)      // 256 bytes of this page
	emit_zp(p, .INC, GT_PTR + 1)       // next page
	emit_impl(p, .DEX)
	emit_branch_id(p, .BNE, loop)      // 64 pages -> full framebuffer
}
