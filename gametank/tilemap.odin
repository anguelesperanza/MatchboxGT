package gametank

import "core:fmt"

// =============================================================================
// Tilemaps
// =============================================================================
//
// A tilemap is a grid of square tiles drawn from a byte array of tile indices
// (row-major, one byte per cell). Tiles are `tile_px` on a side — 16 by default,
// or pass tile_px = 8 (any power of two in 4..64 works). Tiles come from a tileset
// in sprite RAM: a (128/tile_px)-wide grid of tile_px cells at row `tile_gy`, so
// tile N sits at sheet (X = (N & col_mask)*tile_px, Y = tile_gy + (N >> col_bits)*
// tile_px). At 16px that's an 8-wide grid (indices 0..63); at 8px a 16-wide grid.
//
// The map bytes can live in ROM (a `blob` of a fixed layout) or in RAM (a block
// from `alloc_bytes` you fill/edit at run time — walls you dig, fog you reveal).
// draw_tilemap redraws the whole grid, so call it each frame (after the scaffold
// clears the screen); a single screen is a handful of blits.
//
// Whatever tile_px you draw a map with, use the SAME tile_px on the collision
// helpers (if_solid / tile_at / snap_to_tile_below) so pixel<->tile math agrees.

@(private) TM_X    :: u8(0x06) // cursor X   (reuses GT_TMP scratch)
@(private) TM_Y    :: u8(0x07) // cursor Y   (reuses GT_NUM_VAL scratch)
@(private) TM_ROW  :: u8(0x09) // row counter (reuses GT_NUM_TMP scratch)
@(private) TM_TILE :: u8(0x0A) // tile index (reuses GT_NUM_DIG scratch)
// the map pointer reuses GT_PTR ($03/$04).

// log2 of a power-of-two tile size (8 -> 3, 16 -> 4).
@(private)
tm_log2 :: proc(n: u8) -> uint {
	s: uint = 0
	v := n
	for v > 1 { v >>= 1; s += 1 }
	return s
}

// A tile size must be a power of two in 4..64, so 128/tile_px is a whole
// power-of-two column count. Warns and returns false otherwise.
@(private)
tm_valid :: proc(tile_px: u8) -> bool {
	if tile_px < 4 || tile_px > 64 || (tile_px & (tile_px - 1)) != 0 {
		fmt.eprintfln("gametank: tile_px must be a power of two in 4..64 (got %d)", tile_px)
		return false
	}
	return true
}

// Emit `n` accumulator shifts (ASL or LSR) — a build-time multiply/divide by 2^n.
@(private)
emit_shifts :: proc(p: ^Program, mn: Mnemonic, n: uint) {
	for _ in 0 ..< n { emit_acc(p, mn) }
}

// Blit a tile_px-square tile (index in A) to screen (BLIT_VX/VY already set) from
// the tileset at row tile_gy. Leaves Y and the text/map scratch alone.
@(private)
tm_blit_tile :: proc(p: ^Program, tile_gy, tile_px: u8) {
	px_shift  := tm_log2(tile_px)   // 3 for 8, 4 for 16 (pixels per tile = 1<<shift)
	grid_cols := u8(128) / tile_px  // tiles per tileset row: 16 for 8, 8 for 16
	col_bits  := tm_log2(grid_cols) // 4 for 8, 3 for 16
	col_mask  := grid_cols - 1      // low bits of the index = tileset column
	high_mask := ~col_mask          // high bits = tileset row

	emit_zp(p, .STA, TM_TILE)
	blit_begin(p, DMA_GCARRY)
	emit_zp(p, .LDA, TM_X); emit_abs(p, .STA, BLIT_VX)
	emit_zp(p, .LDA, TM_Y); emit_abs(p, .STA, BLIT_VY)
	// gx = (N & col_mask) * tile_px
	emit_zp(p, .LDA, TM_TILE); emit_imm(p, .AND, col_mask)
	emit_shifts(p, .ASL, px_shift)
	emit_abs(p, .STA, BLIT_GX)
	// gy = (N >> col_bits) * tile_px + tile_gy. (N & high_mask) already equals
	// (row << col_bits), so a net shift of (px_shift - col_bits) finishes it.
	emit_zp(p, .LDA, TM_TILE); emit_imm(p, .AND, high_mask)
	d := int(px_shift) - int(col_bits)
	if d > 0 {
		emit_shifts(p, .ASL, uint(d))
	} else if d < 0 {
		emit_shifts(p, .LSR, uint(-d))
	}
	emit_impl(p, .CLC); emit_imm(p, .ADC, tile_gy); emit_abs(p, .STA, BLIT_GY)
	emit_imm(p, .LDA, tile_px); emit_abs(p, .STA, BLIT_WIDTH); emit_abs(p, .STA, BLIT_HEIGHT)
	blit_go(p)
	blit_end(p)
}

// Draw a `cols` x `rows` tilemap from `addr` (row-major tile-index bytes) with its
// top-left at screen (x, y); tiles are read from the tileset at row `tile_gy`.
// Tiles are tile_px on a side (default 16; pass 8 for 8x8). Limits: cols*rows <=
// 256, and x + cols*tile_px <= 255 (a 128px screen holds 128/tile_px columns — 8
// at 16px, 16 at 8px).
draw_tilemap :: proc(p: ^Program, addr: u16, cols, rows, x, y, tile_gy: u8, tile_px: u8 = 16) {
	if !tm_valid(tile_px) {
		return
	}
	total := int(cols) * int(rows)
	if total > 256 {
		fmt.eprintfln("gametank: tilemap has %d tiles (max 256)", total)
		return
	}
	if int(x) + int(cols) * int(tile_px) > 255 {
		fmt.eprintfln("gametank: tilemap runs off the right edge (x=%d, cols=%d, tile_px=%d)", x, cols, tile_px)
		return
	}

	emit_imm(p, .LDA, u8(addr));      emit_zp(p, .STA, GT_PTR)
	emit_imm(p, .LDA, u8(addr >> 8)); emit_zp(p, .STA, GT_PTR + 1)
	emit_imm(p, .LDA, x); emit_zp(p, .STA, TM_X)
	emit_imm(p, .LDA, y); emit_zp(p, .STA, TM_Y)
	emit_imm(p, .LDY, 0)

	loop := anon(p)
	emit_ind_y(p, .LDA, GT_PTR)     // this cell's tile index
	tm_blit_tile(p, tile_gy, tile_px) // -> (TM_X, TM_Y)

	// advance the cursor: X += tile_px, wrapping to the next row at the right edge
	emit_zp(p, .LDA, TM_X); emit_impl(p, .CLC); emit_imm(p, .ADC, tile_px)
	emit_imm(p, .CMP, x + cols * tile_px)
	keep := anon_fwd(p)
	emit_branch_id(p, .BCC, keep)
	emit_zp(p, .LDA, TM_Y); emit_impl(p, .CLC); emit_imm(p, .ADC, tile_px); emit_zp(p, .STA, TM_Y)
	emit_imm(p, .LDA, x)              // reset X to the left edge for the new row
	put_label(p, keep)
	emit_zp(p, .STA, TM_X)

	emit_impl(p, .INY)
	emit_imm(p, .CPY, u8(total))     // u8(256) == 0, which still terminates after 256 tiles
	emit_branch_id(p, .BNE, loop)
}

// Scroll a view_cols x view_rows window over a larger map (`map_cols` wide,
// row-major tile bytes at `addr`), showing the tiles at map cell (cam_x, cam_y) in
// the top-left, drawn at screen (x, y). cam_x/cam_y are Vars in TILE units, so
// scrolling moves the view a whole tile at a time — clamp them to
// [0, map_cols-view_cols] and [0, map_rows-view_rows] yourself (e.g. move_dec/inc,
// gated with every_n_frames for a controlled speed). Tiles from row `tile_gy`,
// tile_px on a side (default 16).
draw_tilemap_view :: proc(p: ^Program, addr: u16, map_cols, view_cols, view_rows: u8, cam_x, cam_y: Var, x, y, tile_gy: u8, tile_px: u8 = 16) {
	if !tm_valid(tile_px) {
		return
	}
	px_shift := tm_log2(tile_px)
	if int(x) + int(view_cols) * int(tile_px) > 255 {
		fmt.eprintfln("gametank: tilemap view too wide (x=%d, view_cols=%d, tile_px=%d)", x, view_cols, tile_px)
		return
	}

	// map pointer = addr + cam_x + cam_y*map_cols (start of the top-left visible cell)
	emit_imm(p, .LDA, u8(addr));      emit_zp(p, .STA, GT_PTR)
	emit_imm(p, .LDA, u8(addr >> 8)); emit_zp(p, .STA, GT_PTR + 1)
	emit_zp(p, .LDA, GT_PTR); emit_impl(p, .CLC); ld_var(p, .ADC, cam_x); emit_zp(p, .STA, GT_PTR)
	c1 := anon_fwd(p); emit_branch_id(p, .BCC, c1); emit_zp(p, .INC, GT_PTR + 1); put_label(p, c1)
	emit_zp(p, .LDX, u8(cam_y.addr))             // add map_cols cam_y times
	cyd := anon_fwd(p); emit_branch_id(p, .BEQ, cyd)
	cyl := anon(p)
	emit_zp(p, .LDA, GT_PTR); emit_impl(p, .CLC); emit_imm(p, .ADC, map_cols); emit_zp(p, .STA, GT_PTR)
	c2 := anon_fwd(p); emit_branch_id(p, .BCC, c2); emit_zp(p, .INC, GT_PTR + 1); put_label(p, c2)
	emit_impl(p, .DEX); emit_branch_id(p, .BNE, cyl)
	put_label(p, cyd)

	emit_imm(p, .LDA, y); emit_zp(p, .STA, TM_Y)  // screen-y cursor
	emit_imm(p, .LDA, 0); emit_zp(p, .STA, TM_ROW)

	outer := anon(p)
	emit_imm(p, .LDY, 0)                          // column index into the map row
	inner := anon(p)
	emit_impl(p, .TYA); emit_shifts(p, .ASL, px_shift)
	emit_impl(p, .CLC); emit_imm(p, .ADC, x); emit_zp(p, .STA, TM_X)  // screen_x = x + col*tile_px
	emit_ind_y(p, .LDA, GT_PTR)                   // tile = map_row[col]
	tm_blit_tile(p, tile_gy, tile_px)             // preserves Y
	emit_impl(p, .INY); emit_imm(p, .CPY, view_cols); emit_branch_id(p, .BNE, inner)

	emit_zp(p, .LDA, TM_Y); emit_impl(p, .CLC); emit_imm(p, .ADC, tile_px); emit_zp(p, .STA, TM_Y)
	emit_zp(p, .LDA, GT_PTR); emit_impl(p, .CLC); emit_imm(p, .ADC, map_cols); emit_zp(p, .STA, GT_PTR)
	c3 := anon_fwd(p); emit_branch_id(p, .BCC, c3); emit_zp(p, .INC, GT_PTR + 1); put_label(p, c3)
	emit_zp(p, .INC, TM_ROW); emit_zp(p, .LDA, TM_ROW); emit_imm(p, .CMP, view_rows); emit_branch_id(p, .BNE, outer)
}

// =============================================================================
// Tile collision — query the map at a pixel point (for platformers, etc.)
// =============================================================================
//
// These read the tile under a *pixel* position (a moving object) rather than a
// fixed cell: they take an object coordinate Var plus a build-time offset, so you
// probe points around a sprite — feet at (px+8, py+16), a wall at (px+15, py+8).
// A tile's index decides its role: `solid_min` splits passable (index < solid_min)
// from solid (>= solid_min), so a common layout is tile 0 = empty, 1+ = solid.
// Pass the same tile_px you drew the map with (default 16).

// GT_PTR = addr + tile_x + tile_y*map_cols for pixel point (x+dx, y+dy); A = tile.
@(private)
load_tile :: proc(p: ^Program, addr: u16, map_cols: u8, x: Var, dx: u8, y: Var, dy: u8, tile_px: u8) {
	px_shift := tm_log2(tile_px)
	emit_imm(p, .LDA, u8(addr));      emit_zp(p, .STA, GT_PTR)
	emit_imm(p, .LDA, u8(addr >> 8)); emit_zp(p, .STA, GT_PTR + 1)
	// += tile_x = (x + dx) / tile_px
	ld_var(p, .LDA, x); emit_impl(p, .CLC); emit_imm(p, .ADC, dx)
	emit_shifts(p, .LSR, px_shift)
	emit_impl(p, .CLC); emit_zp(p, .ADC, GT_PTR); emit_zp(p, .STA, GT_PTR)
	c1 := anon_fwd(p); emit_branch_id(p, .BCC, c1); emit_zp(p, .INC, GT_PTR + 1); put_label(p, c1)
	// += tile_y * map_cols  (tile_y = (y + dy) / tile_px, added via repeated add)
	ld_var(p, .LDA, y); emit_impl(p, .CLC); emit_imm(p, .ADC, dy)
	emit_shifts(p, .LSR, px_shift)
	emit_impl(p, .TAX)
	td := anon_fwd(p); emit_branch_id(p, .BEQ, td)
	tl := anon(p)
	emit_zp(p, .LDA, GT_PTR); emit_impl(p, .CLC); emit_imm(p, .ADC, map_cols); emit_zp(p, .STA, GT_PTR)
	c2 := anon_fwd(p); emit_branch_id(p, .BCC, c2); emit_zp(p, .INC, GT_PTR + 1); put_label(p, c2)
	emit_impl(p, .DEX); emit_branch_id(p, .BNE, tl)
	put_label(p, td)
	emit_imm(p, .LDY, 0); emit_ind_y(p, .LDA, GT_PTR)   // A = tile index
}

// Read the tile index at pixel (x+dx, y+dy) of the map (map_cols wide at addr)
// into `dst`. Clobbers A, X, Y and GT_PTR. Pass the map's tile_px (default 16).
tile_at :: proc(p: ^Program, addr: u16, map_cols: u8, x: Var, dx: u8, y: Var, dy: u8, dst: Var, tile_px: u8 = 16) {
	if !tm_valid(tile_px) {
		return
	}
	load_tile(p, addr, map_cols, x, dx, y, dy, tile_px)
	ld_var(p, .STA, dst)
}

// Begin an "if the tile at pixel (x+dx, y+dy) is solid" block (its index >=
// solid_min). Emit the response after this, then close with put_label(p, <id>).
// e.g. ground: if_solid(p, LEVEL, COLS, px, 8, py, 16, 1). Pass the map's tile_px.
if_solid :: proc(p: ^Program, addr: u16, map_cols: u8, x: Var, dx: u8, y: Var, dy: u8, solid_min: u8, tile_px: u8 = 16) -> u32 {
	if !tm_valid(tile_px) {
		return anon_fwd(p) // keep the caller's put_label balanced even on a bad size
	}
	load_tile(p, addr, map_cols, x, dx, y, dy, tile_px)
	emit_imm(p, .CMP, solid_min)
	return begin_if(p, .BCS)   // tile >= solid_min -> solid -> enter the block
}

// Snap `pos` (an object's Y or X) so an object `height` tall/wide rests flush
// against the solid tile its far edge is inside: pos = ((pos + height) & ~(tile_px
// -1)) - height. Use after landing (with the player's height) to sit cleanly on a
// tile. Pass the map's tile_px (default 16).
snap_to_tile_below :: proc(p: ^Program, pos: Var, height: u8, tile_px: u8 = 16) {
	if !tm_valid(tile_px) {
		return
	}
	ld_var(p, .LDA, pos); emit_impl(p, .CLC); emit_imm(p, .ADC, height)
	emit_imm(p, .AND, ~(tile_px - 1))
	emit_impl(p, .SEC); emit_imm(p, .SBC, height)
	ld_var(p, .STA, pos)
}
