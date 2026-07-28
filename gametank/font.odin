package gametank

// =============================================================================
// Font / glyph drawing
// =============================================================================
//
// Text on the GameTank is just sprites. Lay your glyphs out as a horizontal
// strip of 8x8 cells in sprite RAM (e.g. digits 0-9 in one row), then draw the
// glyph for a value with draw_glyph.
//
// The font grid is 16 glyphs per row starting at (0, font_gy): index 0-9 = '0'-'9',
// 10-35 = 'A'-'Z'. draw_glyph handles a single digit (0-9) from row 0; draw_text
// draws a whole (build-time) string, mapping each character into that grid.

// Blit the 8x8 glyph for `value` (a zero-page variable) from a horizontal glyph
// strip that starts at sprite-sheet (strip_gx, strip_gy). Glyph N is at
// (strip_gx + N*8, strip_gy). screen_x/screen_y are the on-screen position.
//
// Transparency is on, so the glyph's background (color 0) shows through.
draw_glyph :: proc(p: ^Program, screen_x, screen_y: u8, value_zp: u8, strip_gx, strip_gy: u8) {
	blit_begin(p, DMA_GCARRY)
	emit_imm(p, .LDA, screen_x); emit_abs(p, .STA, BLIT_VX)
	emit_imm(p, .LDA, screen_y); emit_abs(p, .STA, BLIT_VY)
	// source X = strip_gx + value*8
	emit_zp(p, .LDA, value_zp)
	emit_acc(p, .ASL); emit_acc(p, .ASL); emit_acc(p, .ASL) // *8
	emit_impl(p, .CLC)
	emit_imm(p, .ADC, strip_gx)
	emit_abs(p, .STA, BLIT_GX)
	emit_imm(p, .LDA, strip_gy); emit_abs(p, .STA, BLIT_GY)
	emit_imm(p, .LDA, 8)
	emit_abs(p, .STA, BLIT_WIDTH)
	emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)
}

// Draw the decimal value of a Var as `digits` zero-padded glyphs, 8px apart,
// starting at (x, y). Digit glyphs come from the same grid as draw_text (row 0 =
// '0'..'9' at font_gy). `digits` is 1-3: fewer shows the low places (digits = 2
// shows value mod 100), so use digits = 1 for a 0-9 counter, 3 for a 0-255 value.
//
// The value is a single byte, so the range is 0-255; a wider score needs a 16-bit
// value (not yet supported). Non-destructive to `v`; clobbers A, X, and the number
// scratch (GT_NUM_VAL/GT_NUM_DIG). The digit glyphs must already be in sprite RAM.
draw_number :: proc(p: ^Program, x, y: u8, v: Var, font_gy: u8, digits: u8 = 3) {
	ld_var(p, .LDA, v)
	emit_zp(p, .STA, GT_NUM_VAL)     // work on a copy so `v` is untouched
	cursor := x

	extract_place(p, 100)            // X = hundreds digit, GT_NUM_VAL = value % 100
	if digits >= 3 {
		emit_zp(p, .STX, GT_NUM_DIG)
		draw_glyph(p, cursor, y, GT_NUM_DIG, 0, font_gy)
		cursor += 8
	}
	extract_place(p, 10)             // X = tens digit, GT_NUM_VAL = value % 10
	if digits >= 2 {
		emit_zp(p, .STX, GT_NUM_DIG)
		draw_glyph(p, cursor, y, GT_NUM_DIG, 0, font_gy)
		cursor += 8
	}
	if digits >= 1 {                 // ones digit is whatever remains
		emit_zp(p, .LDA, GT_NUM_VAL); emit_zp(p, .STA, GT_NUM_DIG)
		draw_glyph(p, cursor, y, GT_NUM_DIG, 0, font_gy)
	}
}

// Subtract `place` (100 or 10) from GT_NUM_VAL as many times as it fits, leaving
// the count in X and the remainder in GT_NUM_VAL — one decimal digit per call.
@(private)
extract_place :: proc(p: ^Program, place: u8) {
	emit_imm(p, .LDX, 0)
	loop := anon(p)
	emit_zp(p, .LDA, GT_NUM_VAL); emit_imm(p, .CMP, place)
	done := anon_fwd(p)
	emit_branch_id(p, .BCC, done)    // remainder < place -> this digit is done
	emit_zp(p, .LDA, GT_NUM_VAL); emit_impl(p, .SEC); emit_imm(p, .SBC, place); emit_zp(p, .STA, GT_NUM_VAL)
	emit_impl(p, .INX)
	emit_jump_id(p, loop)
	put_label(p, done)
}

// Draw the decimal value of a 16-bit Var16 (0-65535) as `digits` zero-padded
// glyphs, 8px apart, from (x, y). Like draw_number but for scores past 255. Use
// digits = 5 for the full range, or fewer to show the low places. Non-destructive
// to `v`; clobbers A, X, and the number scratch. Digit glyphs must be in sprite RAM.
draw_number16 :: proc(p: ^Program, x, y: u8, v: Var16, font_gy: u8, digits: u8 = 5) {
	ld16(p, .LDA, v, false); emit_zp(p, .STA, GT_NUM_VAL)     // working copy (lo)
	ld16(p, .LDA, v, true);  emit_zp(p, .STA, GT_NUM_VAL + 1) // (hi)
	cursor := x

	// ten-thousands, thousands, hundreds, tens — each leaves its digit in X
	places := [4]u16{10000, 1000, 100, 10}
	needs  := [4]u8{5, 4, 3, 2}
	for i in 0 ..< 4 {
		extract16(p, places[i])
		if digits >= needs[i] {
			emit_zp(p, .STX, GT_NUM_DIG)
			draw_glyph(p, cursor, y, GT_NUM_DIG, 0, font_gy)
			cursor += 8
		}
	}
	if digits >= 1 { // ones = whatever remains in the low byte (high byte is now 0)
		emit_zp(p, .LDA, GT_NUM_VAL); emit_zp(p, .STA, GT_NUM_DIG)
		draw_glyph(p, cursor, y, GT_NUM_DIG, 0, font_gy)
	}
}

// Subtract the 16-bit `place` (a power of ten) from the 16-bit working value
// (GT_NUM_VAL lo/hi) as many times as it fits, counting in X — one decimal digit.
@(private)
extract16 :: proc(p: ^Program, place: u16) {
	lo := u8(place)
	hi := u8(place >> 8)
	emit_imm(p, .LDX, 0)
	loop := anon(p)
	// trial subtract: (working - place); commit only if it didn't underflow
	emit_zp(p, .LDA, GT_NUM_VAL);     emit_impl(p, .SEC); emit_imm(p, .SBC, lo); emit_zp(p, .STA, GT_NUM_TMP)
	emit_zp(p, .LDA, GT_NUM_VAL + 1);                     emit_imm(p, .SBC, hi)  // A = tentative hi, C = no borrow
	done := anon_fwd(p)
	emit_branch_id(p, .BCC, done)     // working < place -> this digit is done
	emit_zp(p, .STA, GT_NUM_VAL + 1)  // commit hi
	emit_zp(p, .LDA, GT_NUM_TMP); emit_zp(p, .STA, GT_NUM_VAL) // commit lo
	emit_impl(p, .INX)
	emit_jump_id(p, loop)
	put_label(p, done)
}

// Map a character to its font-grid index, matching the layout the font sheets use:
// 0-9 (0-9), A-Z (10-35), a-z (36-61), punctuation (62-79). The 0-35 range is the
// original layout, so older uppercase-only sheets still work; lowercase and
// punctuation need a sheet that has those glyphs (see examples/text/make_font.ps1).
@(private)
glyph_index :: proc(c: rune) -> (int, bool) {
	switch {
	case c >= '0' && c <= '9': return int(c - '0'), true       // 0-9
	case c >= 'A' && c <= 'Z': return 10 + int(c - 'A'), true  // 10-35
	case c >= 'a' && c <= 'z': return 36 + int(c - 'a'), true  // 36-61
	}
	switch c {                                                 // 62-79
	case '.':  return 62, true
	case ',':  return 63, true
	case '!':  return 64, true
	case '?':  return 65, true
	case '\'': return 66, true
	case ':':  return 67, true
	case ';':  return 68, true
	case '-':  return 69, true
	case '(':  return 70, true
	case ')':  return 71, true
	case '/':  return 72, true
	case '+':  return 73, true
	case '=':  return 74, true
	case '*':  return 75, true
	case '%':  return 76, true
	case '"':  return 77, true
	case '<':  return 78, true
	case '>':  return 79, true
	}
	return 0, false // space / unsupported: leave a gap
}

// Draw a constant string as a row of 8x8 glyphs starting at (x, y). The string is
// known at build time, so this just emits one glyph blit per character (no
// runtime string handling). `font_gy` is the font grid's top row in sprite RAM.
// Characters advance 8px; unmapped characters (e.g. space) leave a blank cell.
draw_text :: proc(p: ^Program, x, y: u8, text: string, font_gy: u8) {
	cx := x
	for c in text {
		if idx, ok := glyph_index(c); ok {
			gx := u8((idx % 16) * 8)
			gy := font_gy + u8((idx / 16) * 8)
			draw_sprite(p, cx, y, gx, gy, 8, 8)
		}
		cx += 8
	}
}

// -----------------------------------------------------------------------------
// Runtime strings: draw text stored in memory (a ROM blob or RAM), decided at run
// time rather than baked in at build time. This is what data-driven text needs —
// dialogue tables, item/monster names, messages chosen by the game. Strings are
// stored as glyph indices (one byte each) with a space marker and a terminator, so
// the draw loop is just "read a byte, blit its glyph". Same charset as draw_text.
// -----------------------------------------------------------------------------

@(private) TEXT_SPACE :: u8(0xFE) // advance the cursor without drawing
@(private) TEXT_END   :: u8(0xFF) // end of string

// Encode `text` into a drawable string blob (glyph indices + terminator) named
// `name`, so draw_string can render it from blob_addr(p, name). Charset is the
// same as draw_text (0-9, A-Z); anything else becomes a space.
string_blob :: proc(p: ^Program, name: string, text: string) {
	data := make([dynamic]u8)
	for c in text {
		if idx, ok := glyph_index(c); ok {
			append(&data, u8(idx))
		} else {
			append(&data, TEXT_SPACE)
		}
	}
	append(&data, TEXT_END)
	blob(p, name, data[:])
}

// Draw a terminated string from `addr` (a string_blob, or any RAM/ROM bytes in the
// same glyph-index encoding) as 8x8 glyphs starting at (x, y). Unlike draw_text
// this is a real runtime loop, so the string's content and length can change while
// the game runs. Clobbers A, Y, and the text scratch (GT_TEXT_PTR/GT_TEXT_X, GT_TMP).
draw_string :: proc(p: ^Program, x, y: u8, addr: u16, font_gy: u8) {
	emit_imm(p, .LDA, u8(addr));      emit_zp(p, .STA, GT_TEXT_PTR)
	emit_imm(p, .LDA, u8(addr >> 8)); emit_zp(p, .STA, GT_TEXT_PTR + 1)
	emit_imm(p, .LDA, x);             emit_zp(p, .STA, GT_TEXT_X)
	emit_imm(p, .LDY, 0)

	loop := anon(p)
	emit_ind_y(p, .LDA, GT_TEXT_PTR)                 // A = next glyph byte
	done := anon_fwd(p)
	emit_imm(p, .CMP, TEXT_END);   emit_branch_id(p, .BEQ, done)
	space := anon_fwd(p)
	emit_imm(p, .CMP, TEXT_SPACE); emit_branch_id(p, .BEQ, space)

	// blit the 8x8 glyph for index A: source (gx, gy) = ((idx%16)*8, font_gy+(idx/16)*8)
	emit_zp(p, .STA, GT_TMP)                         // save the index (blit clobbers A)
	blit_begin(p, DMA_GCARRY)                        // transparency on; leaves Y and text scratch alone
	emit_zp(p, .LDA, GT_TEXT_X); emit_abs(p, .STA, BLIT_VX)
	emit_imm(p, .LDA, y);        emit_abs(p, .STA, BLIT_VY)
	emit_zp(p, .LDA, GT_TMP); emit_imm(p, .AND, 0x0F); emit_acc(p, .ASL); emit_acc(p, .ASL); emit_acc(p, .ASL)
	emit_abs(p, .STA, BLIT_GX)                       // gx = (idx & 15) * 8
	emit_zp(p, .LDA, GT_TMP); emit_imm(p, .AND, 0xF0); emit_acc(p, .LSR); emit_impl(p, .CLC); emit_imm(p, .ADC, font_gy)
	emit_abs(p, .STA, BLIT_GY)                       // gy = font_gy + (idx >> 4) * 8
	emit_imm(p, .LDA, 8); emit_abs(p, .STA, BLIT_WIDTH); emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)

	put_label(p, space)
	emit_zp(p, .LDA, GT_TEXT_X); emit_impl(p, .CLC); emit_imm(p, .ADC, 8); emit_zp(p, .STA, GT_TEXT_X)
	emit_impl(p, .INY)
	emit_jump_id(p, loop)
	put_label(p, done)
}
