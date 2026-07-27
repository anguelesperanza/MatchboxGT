package gametank

// =============================================================================
// Blitter
// =============================================================================
//
// The blitter copies rectangles from sprite RAM into the framebuffer (or fills
// them with a solid color) in parallel with the CPU. A draw is: set the DMA
// flags, set the parameter registers ($4000-$4007), write 1 to the trigger
// ($4006), then WAI for the completion interrupt.
//
// blit_begin/blit_go/blit_end are the low-level pieces (use them when the
// coordinates live in RAM); fill_rect and draw_sprite are the immediate-operand
// conveniences.
//
// Notes:
//   * Max blit size is 127x127.
//   * DMA_GCARRY (bit4) draws the full source image; without it the blitter
//     repeats a 16x16 tile — draw_sprite sets it.
//   * Colorfill's color register wants the INVERTED byte; fill_rect handles it.
//   * blit_begin preserves the current page (DMA_PAGE_OUT) and DMA_NMI bits from
//     the DMA mirror and forces CPU-access off so the blitter owns VRAM.

// Configure DMA_FLAGS for a blit: keep page + vblank-NMI state, enable the
// blitter and its completion IRQ, and add `extra` (DMA_COLORFILL or DMA_GCARRY).
// Does not touch the mirror — blit_end restores from it.
blit_begin :: proc(p: ^Program, extra: u8) {
	emit_zp(p, .LDA, GT_DMA)
	emit_imm(p, .AND, DMA_PAGE_OUT | DMA_NMI)          // preserve page + NMI
	emit_imm(p, .ORA, DMA_ENABLE | DMA_IRQ | extra)    // blitter on, IRQ on completion
	emit_abs(p, .STA, DMA_FLAGS)
}

// Trigger the blit and wait for it to finish.
//
// We spin on GT_BLIT (set by the blit-completion IRQ handler) rather than using
// WAI: WAI wakes on ANY interrupt, so with audio running the vblank NMI can wake
// it mid-blit, and the next blit would clobber the unfinished one (flicker). The
// flag is only set by the actual completion IRQ, so the NMI can't fool it.
// Requires IRQs enabled (boot does CLI) and the blit IRQ handler installed
// (build_rom's default IRQ vector — see emit_blit_isr).
blit_go :: proc(p: ^Program) {
	emit_zp(p, .STZ, GT_BLIT)          // clear the done flag
	emit_imm(p, .LDA, 0x01)
	emit_abs(p, .STA, BLIT_START)      // trigger (also clears any pending blit IRQ)
	loop := anon(p)
	emit_zp(p, .LDA, GT_BLIT)
	emit_branch_id(p, .BEQ, loop)      // spin until the completion IRQ sets it
}

// The blit-completion IRQ handler: mark the blit done and clear the blit IRQ.
// Installed by build_rom as the default IRQ vector.
@(private)
emit_blit_isr :: proc(p: ^Program, name: string) {
	mark(p, name)
	emit_impl(p, .PHA)
	emit_imm(p, .LDA, 0x01)
	emit_zp(p, .STA, GT_BLIT)
	emit_abs(p, .STZ, BLIT_START)      // write 0 -> clears the completion IRQ
	emit_impl(p, .PLA)
	emit_impl(p, .RTI)
}

// Restore DMA_FLAGS from the mirror after a blit (undoes blit_begin).
blit_end :: proc(p: ^Program) {
	emit_zp(p, .LDA, GT_DMA)
	emit_abs(p, .STA, DMA_FLAGS)
}

// Solid-color rectangle via colorfill. Coordinates/size are immediates; `color`
// is a normal color value (inverted here for the color register).
//
// DMA_OPAQUE is set so *every* pixel is written — without it the blitter treats
// zero-valued pixels as transparent, which makes filling with BLACK ($00) a
// silent no-op.
fill_rect :: proc(p: ^Program, x, y, w, h: u8, color: u8) {
	blit_begin(p, DMA_COLORFILL | DMA_OPAQUE)
	emit_imm(p, .LDA, x); emit_abs(p, .STA, BLIT_VX)
	emit_imm(p, .LDA, y); emit_abs(p, .STA, BLIT_VY)
	emit_imm(p, .LDA, w); emit_abs(p, .STA, BLIT_WIDTH)
	emit_imm(p, .LDA, h); emit_abs(p, .STA, BLIT_HEIGHT)
	emit_imm(p, .LDA, 0xFF - color); emit_abs(p, .STA, BLIT_COLOR) // colorfill wants inverted
	blit_go(p)
	blit_end(p)
}

// Clear the whole framebuffer to a solid color (a full-frame colorfill, the
// canonical 127x127 clear). Call once per frame on the hidden buffer.
clear_screen :: proc(p: ^Program, color: u8) {
	fill_rect(p, 0, 0, 127, 127, color)
}

// Copy a w x h sprite from sprite RAM (gx, gy) to the framebuffer (vx, vy).
// Immediate operands; the sprite data must already be in sprite RAM.
draw_sprite :: proc(p: ^Program, vx, vy, gx, gy, w, h: u8) {
	blit_begin(p, DMA_GCARRY)
	emit_imm(p, .LDA, vx); emit_abs(p, .STA, BLIT_VX)
	emit_imm(p, .LDA, vy); emit_abs(p, .STA, BLIT_VY)
	emit_imm(p, .LDA, gx); emit_abs(p, .STA, BLIT_GX)
	emit_imm(p, .LDA, gy); emit_abs(p, .STA, BLIT_GY)
	emit_imm(p, .LDA, w);  emit_abs(p, .STA, BLIT_WIDTH)
	emit_imm(p, .LDA, h);  emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)
}

// Zero the blitter's GX/GY source counters with a dummy 1x1 blit. The counters
// affect which quadrant of sprite RAM the CPU sees, so do this before writing
// sprite data to the VRAM window in sprite-RAM mode. Expects DMA already enabled.
blit_reset_counters :: proc(p: ^Program) {
	emit_abs(p, .STZ, BLIT_GX)
	emit_abs(p, .STZ, BLIT_GY)
	emit_imm(p, .LDA, 0x01)
	emit_abs(p, .STA, BLIT_WIDTH)
	emit_abs(p, .STA, BLIT_HEIGHT)
	emit_abs(p, .STA, BLIT_START)
	emit_abs(p, .STZ, BLIT_START)
}
