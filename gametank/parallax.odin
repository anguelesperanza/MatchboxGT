package gametank

// =============================================================================
// Parallax: horizontally-scrolling background layers
// =============================================================================
//
// A layer is a 128-wide repeating strip in sprite RAM (a full band of rows at
// src_gy) that scrolls sideways. Each layer keeps its own `offset` Var (0..127);
// advance several layers at different speeds and you get parallax depth. Draw them
// back-to-front (far/slow first) — each is blitted with transparency, so a layer's
// 0-pixels show whatever's behind it. Your strip art must be **128px wide and
// seamless** (left edge meets right edge) so the wrap is invisible.

// Advance a layer's scroll offset by `speed` pixels (wraps at 128). Higher speed =
// nearer/faster layer. Call once per frame per layer.
layer_scroll :: proc(p: ^Program, offset: Var, speed: u8) {
	ld_var(p, .LDA, offset); emit_impl(p, .CLC); emit_imm(p, .ADC, speed)
	emit_imm(p, .AND, 0x7F)   // period 128
	ld_var(p, .STA, offset)
}

// Draw a 128-wide scrolling strip: the band of sprite RAM at (0, src_gy), `height`
// tall, blitted to the screen at (0, screen_y) offset horizontally by `offset`.
// Two partial blits cover the wrap. (At offset 0 the rightmost column is skipped —
// the blitter's width maxes at 127 — a 1px seam for one frame in the cycle.)
draw_layer :: proc(p: ^Program, src_gy, screen_y, height: u8, offset: Var) {
	// w1 = min(128 - offset, 127)  -> GT_TMP
	emit_imm(p, .LDA, 128); emit_impl(p, .SEC); ld_var(p, .SBC, offset)
	cap := anon_fwd(p); emit_branch_id(p, .BPL, cap) // 128-offset == 128 only when offset==0
	emit_imm(p, .LDA, 127)
	put_label(p, cap)
	emit_zp(p, .STA, GT_TMP)

	// blit 1: screen [0, w1) <- source columns [offset, 128)
	blit_begin(p, DMA_GCARRY)
	emit_imm(p, .LDA, 0);          emit_abs(p, .STA, BLIT_VX)
	emit_imm(p, .LDA, screen_y);   emit_abs(p, .STA, BLIT_VY)
	ld_var(p, .LDA, offset);       emit_abs(p, .STA, BLIT_GX)
	emit_imm(p, .LDA, src_gy);     emit_abs(p, .STA, BLIT_GY)
	emit_zp(p, .LDA, GT_TMP);      emit_abs(p, .STA, BLIT_WIDTH)
	emit_imm(p, .LDA, height);     emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p); blit_end(p)

	// blit 2 (only when offset != 0): screen [128-offset, 128) <- source [0, offset)
	skip := if_nonzero(p, offset)
	blit_begin(p, DMA_GCARRY)
	emit_zp(p, .LDA, GT_TMP);      emit_abs(p, .STA, BLIT_VX)   // 128 - offset
	emit_imm(p, .LDA, screen_y);   emit_abs(p, .STA, BLIT_VY)
	emit_imm(p, .LDA, 0);          emit_abs(p, .STA, BLIT_GX)
	emit_imm(p, .LDA, src_gy);     emit_abs(p, .STA, BLIT_GY)
	ld_var(p, .LDA, offset);       emit_abs(p, .STA, BLIT_WIDTH)
	emit_imm(p, .LDA, height);     emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p); blit_end(p)
	put_label(p, skip)
}
