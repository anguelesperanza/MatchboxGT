package gametank

// =============================================================================
// Menus: a cursor over a vertical list of options
// =============================================================================
//
// A menu is a `cursor` Var (the selected row, 0..count-1) plus the rows you draw
// yourself (with draw_string / draw_text). menu_navigate moves the cursor with the
// D-pad; menu_cursor draws the ">" marker beside the selected row; if_chosen fires
// when the player confirms a particular option. Feed these the `pressed` edge Var
// from poll_gamepad so a tap moves/selects once, not every frame.

// Move `cursor` (0..count-1) up/down with the D-pad, one step per press, clamped at
// both ends. `pressed` is a poll_gamepad edge Var; `count` is the number of options.
menu_navigate :: proc(p: ^Program, cursor: Var, count: u8, pressed: Var) {
	up := if_just_pressed(p, pressed, PAD_UP)
	top := if_nonzero(p, cursor)     // already at the top? don't move
	dec(p, cursor)
	put_label(p, top)
	put_label(p, up)

	down := if_just_pressed(p, pressed, PAD_DOWN)
	bot := if_lt(p, cursor, count - 1) // already at the bottom? don't move
	inc(p, cursor)
	put_label(p, bot)
	put_label(p, down)
}

// Draw the ">" cursor marker beside the selected row, at (x, y + cursor*spacing) —
// use the same `y` and `spacing` you laid the option rows out with. `cursor` must
// be a zero-page Var. The ">" comes from the font at row `font_gy`.
menu_cursor :: proc(p: ^Program, x, y: u8, cursor: Var, spacing, font_gy: u8) {
	gi, _ := glyph_index('>')
	gx := u8((gi % 16) * 8)
	gy := font_gy + u8((gi / 16) * 8)

	// GT_TMP = y + cursor*spacing (add spacing `cursor` times)
	emit_imm(p, .LDA, y)
	emit_zp(p, .LDX, u8(cursor.addr))
	done := anon_fwd(p)
	emit_branch_id(p, .BEQ, done)      // cursor == 0 -> no offset
	loop := anon(p)
	emit_impl(p, .CLC); emit_imm(p, .ADC, spacing)
	emit_impl(p, .DEX)
	emit_branch_id(p, .BNE, loop)
	put_label(p, done)
	emit_zp(p, .STA, GT_TMP)

	blit_begin(p, DMA_GCARRY)
	emit_imm(p, .LDA, x);      emit_abs(p, .STA, BLIT_VX)
	emit_zp(p, .LDA, GT_TMP);  emit_abs(p, .STA, BLIT_VY)
	emit_imm(p, .LDA, gx);     emit_abs(p, .STA, BLIT_GX)
	emit_imm(p, .LDA, gy);     emit_abs(p, .STA, BLIT_GY)
	emit_imm(p, .LDA, 8); emit_abs(p, .STA, BLIT_WIDTH); emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)
}

// Begin a block that runs when `button` was just pressed while `cursor` == `index`
// — i.e. the player confirmed that option. Emit the option's action after this,
// then close with put_label(p, <returned id>). One if_chosen per option.
if_chosen :: proc(p: ^Program, cursor: Var, index: u8, pressed: Var, button: u8) -> u32 {
	skip  := anon_fwd(p) // far: JMP'd to when not chosen (block can be any size)
	miss  := anon_fwd(p) // near
	enter := anon_fwd(p)
	emit_imm(p, .LDA, button); ld_var(p, .BIT, pressed); emit_branch_id(p, .BEQ, miss)  // not pressed
	ld_var(p, .LDA, cursor);   emit_imm(p, .CMP, index); emit_branch_id(p, .BEQ, enter) // pressed on this option
	put_label(p, miss)
	emit_jump_id(p, skip)
	put_label(p, enter)
	return skip
}
