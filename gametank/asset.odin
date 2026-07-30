package gametank

import "core:fmt"
import m "core:rexcode/isa/mos6502"

// =============================================================================
// Assets: decompress sprite data into sprite RAM
// =============================================================================
//
// Compressed sprites (your deflate tool's .gtg.deflate output) are embedded with
// blob_file and decompressed at runtime by the bundled INFLATE routine. Build
// the ROM with Config.inflate = true so the routine is present at $E000.

// JSR to a literal address (e.g. the INFLATE entry point).
emit_jsr_abs :: proc(p: ^Program, addr: u16) {
	append(&p.insts, m.inst_m(.JSR, m.mem_abs(addr)))
}

// Point INFLATE at a blob and call it: decompress `asset` to `dest`. No graphics
// setup — use this for plain RAM targets (e.g. audio RAM). Runs to completion
// before returning.
//
// IMPORTANT: the bundled INFLATE routine uses the ENTIRE zero page ($00-$FF —
// not just the $F0-$FF pointers) as working scratch. That includes the whole
// game-variable pool ($10-$EF). So any Var you initialize (set/set16/copy_var/
// timer_set/...) BEFORE this call is wiped out. Do ALL asset decompression first,
// then allocate and initialize game state. (Allocating a Var before inflating is
// fine — that only reserves an address; it's *writing* one that gets clobbered.)
inflate_raw :: proc(p: ^Program, asset: string, dest: u16) {
	if p.var_inited {
		fmt.eprintln("gametank: WARNING — inflate_asset/inflate_raw runs AFTER a game variable was initialized.")
		fmt.eprintln("         INFLATE uses all of zero page as scratch, so those variables are now garbage.")
		fmt.eprintln("         Move every blob_file/inflate_asset call ABOVE your set/alloc game-state setup.")
	}
	src := blob_addr(p, asset)
	emit_imm(p, .LDA, u8(src));        emit_zp(p, .STA, INFLATE_ZP)
	emit_imm(p, .LDA, u8(src >> 8));   emit_zp(p, .STA, INFLATE_ZP + 1)
	emit_imm(p, .LDA, u8(dest));       emit_zp(p, .STA, INFLATE_ZP + 2)
	emit_imm(p, .LDA, u8(dest >> 8));  emit_zp(p, .STA, INFLATE_ZP + 3)
	emit_jsr_abs(p, INFLATE_ENTRY)
}

// Decompress a compressed asset blob into VRAM (default: sprite RAM at $4000).
//
// Sets the window to sprite-RAM access and resets the blitter's GX/GY counters so
// the write lands at the base of the page, then decompresses. Run this early —
// before setting up double-buffering — because INFLATE owns the graphics bus.
//
// INFLATE clobbers the whole zero page (see inflate_raw), so decompress every
// asset BEFORE you initialize any game variables.
inflate_asset :: proc(p: ^Program, asset: string, dest: u16 = VRAM) {
	// CPU -> sprite RAM (DMA bit5 = 0), page 0, DMA enabled for the counter reset
	emit_imm(p, .LDA, DMA_ENABLE); emit_abs(p, .STA, DMA_FLAGS)
	emit_imm(p, .LDA, 0x00);       emit_abs(p, .STA, BANK_FLAGS)
	blit_reset_counters(p)
	emit_imm(p, .LDA, 0x00);       emit_abs(p, .STA, DMA_FLAGS)
	inflate_raw(p, asset, dest)
}
