package gametank

import "core:fmt"

// =============================================================================
// Tilemaps
// =============================================================================
//
// A tilemap is a grid of 16x16 tiles drawn from a byte array of tile indices
// (row-major, one byte per cell). Tiles come from a tileset in sprite RAM: an
// 8-wide grid of 16x16 cells at row `tile_gy`, so tile N sits at sheet
// (X=(N&7)*16, Y=tile_gy+(N>>3)*16) — up to 64 tile types.
//
// The map bytes can live in ROM (a `blob` of a fixed layout) or in RAM (a block
// from `alloc_bytes` you fill/edit at run time — walls you dig, fog you reveal).
// draw_tilemap redraws the whole grid, so call it each frame (after the scaffold
// clears the screen); a single screen is a handful of blits.

@(private) TM_X    :: u8(0x06) // cursor X   (reuses GT_TMP scratch)
@(private) TM_Y    :: u8(0x07) // cursor Y   (reuses GT_NUM_VAL scratch)
@(private) TM_TILE :: u8(0x0A) // tile index (reuses GT_NUM_DIG scratch)
// the map pointer reuses GT_PTR ($03/$04).

// Draw a `cols` x `rows` tilemap from `addr` (row-major tile-index bytes) with its
// top-left at screen (x, y); tiles are read from the tileset at row `tile_gy`.
// Each tile is 16x16, drawn with transparency. Limits: cols*rows <= 256, tile
// indices 0..63, and x + cols*16 <= 255 (a 128px screen holds 8 columns).
draw_tilemap :: proc(p: ^Program, addr: u16, cols, rows, x, y, tile_gy: u8) {
	total := int(cols) * int(rows)
	if total > 256 {
		fmt.eprintfln("gametank: tilemap has %d tiles (max 256)", total)
		return
	}
	if int(x) + int(cols) * 16 > 255 {
		fmt.eprintfln("gametank: tilemap runs off the right edge (x=%d, cols=%d)", x, cols)
		return
	}

	emit_imm(p, .LDA, u8(addr));      emit_zp(p, .STA, GT_PTR)
	emit_imm(p, .LDA, u8(addr >> 8)); emit_zp(p, .STA, GT_PTR + 1)
	emit_imm(p, .LDA, x); emit_zp(p, .STA, TM_X)
	emit_imm(p, .LDA, y); emit_zp(p, .STA, TM_Y)
	emit_imm(p, .LDY, 0)

	loop := anon(p)
	emit_ind_y(p, .LDA, GT_PTR); emit_zp(p, .STA, TM_TILE)   // this cell's tile index

	// blit the 16x16 tile: src ((tile&7)*16, tile_gy + (tile>>3)*16) -> (TM_X, TM_Y)
	blit_begin(p, DMA_GCARRY)
	emit_zp(p, .LDA, TM_X); emit_abs(p, .STA, BLIT_VX)
	emit_zp(p, .LDA, TM_Y); emit_abs(p, .STA, BLIT_VY)
	emit_zp(p, .LDA, TM_TILE); emit_imm(p, .AND, 0x07)
	emit_acc(p, .ASL); emit_acc(p, .ASL); emit_acc(p, .ASL); emit_acc(p, .ASL)
	emit_abs(p, .STA, BLIT_GX)                              // gx = (tile & 7) * 16
	emit_zp(p, .LDA, TM_TILE); emit_imm(p, .AND, 0xF8); emit_acc(p, .ASL)
	emit_impl(p, .CLC); emit_imm(p, .ADC, tile_gy); emit_abs(p, .STA, BLIT_GY) // gy = tile_gy + (tile>>3)*16
	emit_imm(p, .LDA, 16); emit_abs(p, .STA, BLIT_WIDTH); emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)

	// advance the cursor: X += 16, wrapping to the next row at the right edge
	emit_zp(p, .LDA, TM_X); emit_impl(p, .CLC); emit_imm(p, .ADC, 16)
	emit_imm(p, .CMP, x + cols * 16)
	keep := anon_fwd(p)
	emit_branch_id(p, .BCC, keep)
	emit_zp(p, .LDA, TM_Y); emit_impl(p, .CLC); emit_imm(p, .ADC, 16); emit_zp(p, .STA, TM_Y)
	emit_imm(p, .LDA, x)              // reset X to the left edge for the new row
	put_label(p, keep)
	emit_zp(p, .STA, TM_X)

	emit_impl(p, .INY)
	emit_imm(p, .CPY, u8(total))     // u8(256) == 0, which still terminates after 256 tiles
	emit_branch_id(p, .BNE, loop)
}
