package main

// "HELLO, WORLD!" for the GameTank, built on the `gametank` framework.
//
//   odin run examples/hello        # from the repo root (or `odin run .` from this folder); writes hello.gtr

import gt "../../gametank"

MESSAGE :: "HELLO, WORLD!"
WIDTH   :: len(MESSAGE) * 8   // text bitmap width in pixels
HEIGHT  :: 8
START_X :: 12                 // roughly centered on the 128-wide framebuffer
START_Y :: 60                 // inside the TV-visible band

// -----------------------------------------------------------------------------
// 8x8 bitmap font
// -----------------------------------------------------------------------------

Glyph :: struct { ch: rune, rows: [8]u8 }

FONT := []Glyph{
	{' ', {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}},
	{'H', {0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00}},
	{'E', {0xFE, 0xC0, 0xC0, 0xFC, 0xC0, 0xC0, 0xFE, 0x00}},
	{'L', {0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xFE, 0x00}},
	{'O', {0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00}},
	{'W', {0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6, 0x00}},
	{'R', {0xFC, 0xC6, 0xC6, 0xFC, 0xD8, 0xCC, 0xC6, 0x00}},
	{'D', {0xF8, 0xCC, 0xC6, 0xC6, 0xC6, 0xCC, 0xF8, 0x00}},
	{',', {0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x60}},
	{'!', {0x30, 0x30, 0x30, 0x30, 0x30, 0x00, 0x30, 0x00}},
}

glyph_rows :: proc(ch: rune) -> [8]u8 {
	for g in FONT {
		if g.ch == ch { return g.rows }
	}
	return {0, 0, 0, 0, 0, 0, 0, 0}
}

// Render the message into a WIDTH x HEIGHT block of framebuffer color bytes.
build_text_bitmap :: proc() -> []u8 {
	table := make([]u8, HEIGHT * WIDTH)
	i := 0
	for ch in MESSAGE {
		rows := glyph_rows(ch)
		for r in 0 ..< HEIGHT {
			bits := rows[r]
			for c in 0 ..< 8 {
				val: u8 = gt.BLACK
				if (bits >> uint(7 - c)) & 1 == 1 {
					val = gt.WHITE
				}
				table[r*WIDTH + i*8 + c] = val
			}
		}
		i += 1
	}
	return table
}

// -----------------------------------------------------------------------------
// Copy the HEIGHT x WIDTH text bitmap from ROM into the framebuffer, row by row.
// -----------------------------------------------------------------------------

draw_text :: proc(p: ^gt.Program, src_addr: u16) {
	// src pointer ($10/$11) = src_addr
	gt.emit_imm(p, .LDA, u8(src_addr & 0xFF)); gt.emit_zp(p, .STA, 0x10)
	gt.emit_imm(p, .LDA, u8(src_addr >> 8));   gt.emit_zp(p, .STA, 0x11)
	// dst pointer ($12/$13) = framebuffer(START_X, START_Y)
	dst := gt.VRAM + u16(START_Y * gt.FB_STRIDE + START_X)
	gt.emit_imm(p, .LDA, u8(dst & 0xFF)); gt.emit_zp(p, .STA, 0x12)
	gt.emit_imm(p, .LDA, u8(dst >> 8));   gt.emit_zp(p, .STA, 0x13)
	gt.emit_imm(p, .LDX, HEIGHT)          // rows remaining

	row := gt.anon(p)
	gt.emit_imm(p, .LDY, 0x00)
	col := gt.anon(p)
	gt.emit_ind_y(p, .LDA, 0x10)          // lda (src),y
	gt.emit_ind_y(p, .STA, 0x12)          // sta (dst),y
	gt.emit_impl(p, .INY)
	gt.emit_imm(p, .CPY, WIDTH)
	gt.emit_branch_id(p, .BNE, col)

	// src += WIDTH
	gt.emit_impl(p, .CLC)
	gt.emit_zp(p, .LDA, 0x10); gt.emit_imm(p, .ADC, WIDTH);          gt.emit_zp(p, .STA, 0x10)
	gt.emit_zp(p, .LDA, 0x11); gt.emit_imm(p, .ADC, 0x00);           gt.emit_zp(p, .STA, 0x11)
	// dst += 128 (next framebuffer row)
	gt.emit_impl(p, .CLC)
	gt.emit_zp(p, .LDA, 0x12); gt.emit_imm(p, .ADC, u8(gt.FB_STRIDE)); gt.emit_zp(p, .STA, 0x12)
	gt.emit_zp(p, .LDA, 0x13); gt.emit_imm(p, .ADC, 0x00);            gt.emit_zp(p, .STA, 0x13)

	gt.emit_impl(p, .DEX)
	gt.emit_branch_id(p, .BNE, row)
}

// -----------------------------------------------------------------------------

assemble :: proc(p: ^gt.Program) {
	gt.blob(p, "text", build_text_bitmap())

	// reset preamble + give the CPU direct framebuffer access (show page 0)
	gt.boot(p, gt.DMA_CPU_TO_VRAM, 0)
	gt.clear_framebuffer(p, gt.BLACK)
	draw_text(p, gt.blob_addr(p, "text"))

	gt.mark(p, "forever")
	gt.emit_jump(p, "forever")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "hello.gtr"}, assemble)
}
