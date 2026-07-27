package gametank

// =============================================================================
// Display: boot, register mirrors, vsync, and double-buffering
// =============================================================================
//
// Bank_Flags ($2005) and DMA_Flags ($2007) are write-only, so we keep RAM
// mirrors (GT_BANK / GT_DMA) and always update the mirror alongside the
// register. Page flipping is then just an EOR on the mirror.
//
// Double-buffering uses the two framebuffer pages: one is shown on the TV
// (DMA_PAGE_OUT, $2007 bit1) while the other is drawn to by the CPU/blitter
// (BANK_FB_PAGE, $2005 bit3). flip() toggles both so the freshly-drawn page
// becomes visible and drawing moves to the other page.
//
// Frame pacing uses the vblank NMI: enable DMA_NMI, install vsync_nmi as the
// NMI handler (it bumps GT_VSYNC), and call await_vsync once per frame.

// Boot straight into double-buffered rendering. Enables the blitter and the
// vblank NMI, turns on edge clipping, and — critically — starts the DRAWN page
// (BANK_FB_PAGE) opposite the DISPLAYED page (DMA_PAGE_OUT), so flip() keeps
// them opposite forever. Draw to the hidden page each frame, then flip.
//
// Getting this wrong (both pages equal) means you draw on the visible buffer:
// you see the clear/redraw happen live (flicker) and the buffer's leftover
// content from two frames ago (ghosting). `extra_dma` adds DMA flag bits if you
// need them (usually 0).
boot_double_buffered :: proc(p: ^Program, extra_dma: u8 = 0) {
	boot(p, DMA_ENABLE | DMA_NMI | extra_dma, BANK_FB_PAGE | BANK_CLIP_X | BANK_CLIP_Y)
}

// Standard reset preamble: mask IRQs, clear decimal, set the stack, zero the
// vsync flag, and initialize both register mirrors + the registers themselves.
//
// For a double-buffered game, prefer boot_double_buffered — it also establishes
// the required "drawn page opposite displayed page" invariant.
boot :: proc(p: ^Program, dma_flags: u8, bank_flags: u8) {
	emit_impl(p, .SEI)
	emit_impl(p, .CLD)
	emit_imm(p, .LDX, 0xFF)
	emit_impl(p, .TXS)
	emit_imm(p, .LDA, 0x00)
	emit_zp(p, .STA, GT_VSYNC)
	emit_imm(p, .LDA, 0x07) // VIA port A low 3 bits = output (flash bank lines)
	emit_abs(p, .STA, VIA_DDRA)
	set_dma(p, dma_flags)
	set_bank_flags(p, bank_flags)
	emit_impl(p, .CLI) // enable IRQs so blit completion reaches the blit handler
}

// Write DMA_Flags ($2007) and keep the mirror in sync.
set_dma :: proc(p: ^Program, flags: u8) {
	emit_imm(p, .LDA, flags)
	emit_zp(p, .STA, GT_DMA)
	emit_abs(p, .STA, DMA_FLAGS)
}

// Write Bank_Flags ($2005 — RAM/sprite page + blit clip) and keep the mirror in
// sync. (Distinct from set_bank, which switches flash cartridge banks.)
set_bank_flags :: proc(p: ^Program, flags: u8) {
	emit_imm(p, .LDA, flags)
	emit_zp(p, .STA, GT_BANK)
	emit_abs(p, .STA, BANK_FLAGS)
}

// The vblank NMI handler: increments GT_VSYNC then returns. Emit this outside
// the main execution path (after your main loop's jump) and point Config.nmi at
// `name`. Requires DMA_NMI to be enabled in the DMA flags.
vsync_nmi :: proc(p: ^Program, name: string) {
	mark(p, name)
	emit_zp(p, .INC, GT_VSYNC)
	emit_impl(p, .RTI)
}

// Spin until the vsync NMI fires, then clear the flag. A plain poll (no WAI) so
// it never races with the blitter's completion interrupt.
await_vsync :: proc(p: ^Program) {
	loop := anon(p)
	emit_zp(p, .LDA, GT_VSYNC)
	emit_branch_id(p, .BEQ, loop)
	emit_zp(p, .STZ, GT_VSYNC)
}

// Swap the drawn and displayed framebuffer pages (toggles BANK_FB_PAGE and
// DMA_PAGE_OUT via the mirrors). Call after drawing a frame, right after
// await_vsync, for a tear-free flip.
flip :: proc(p: ^Program) {
	emit_zp(p, .LDA, GT_BANK)
	emit_imm(p, .EOR, BANK_FB_PAGE)
	emit_zp(p, .STA, GT_BANK)
	emit_abs(p, .STA, BANK_FLAGS)

	emit_zp(p, .LDA, GT_DMA)
	emit_imm(p, .EOR, DMA_PAGE_OUT)
	emit_zp(p, .STA, GT_DMA)
	emit_abs(p, .STA, DMA_FLAGS)
}
