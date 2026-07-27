package gametank

// =============================================================================
// Flash-cartridge banking
// =============================================================================
//
// A 2 MB cart exposes a 16 KB window at $8000-$BFFF, switchable among 128 banks;
// $C000-$FFFF is always the last 16 KB (bank 127) and holds all code. Big data
// (sprite sheets, levels, sampled audio) lives in banks 0-126: select a bank
// with set_bank, then read/inflate from $8000. (Banked data only — code stays in
// the fixed region.)
//
// The bank number is shifted MSB-first into the cart's register through the VIA:
// per bit, set DATA and pulse CLK; then pulse CS to latch. build_rom installs the
// bank_switch subroutine (in the fixed region) when size = .Flash2M.

// Emit the bank-switch subroutine: shift the page number in A into the cart.
@(private)
emit_bank_switch :: proc(p: ^Program, name: string) {
	mark(p, name)
	emit_zp(p, .STA, GT_TMP)      // page number to shift out
	emit_imm(p, .LDX, 0x08)       // 8 bits (low 7 are used)
	loop := anon(p)
	emit_imm(p, .LDA, 0x00)       // DATA=0, CLK=0, CS=0
	emit_zp(p, .ASL, GT_TMP)      // next bit (MSB first) -> carry
	nodata := anon_fwd(p)
	emit_branch_id(p, .BCC, nodata)
	emit_imm(p, .LDA, BANK_DATA)  // DATA=1
	put_label(p, nodata)
	emit_abs(p, .STA, VIA_ORA)    // present DATA with CLK low
	emit_imm(p, .ORA, BANK_CLK)
	emit_abs(p, .STA, VIA_ORA)    // CLK 0->1: shifts DATA in
	emit_impl(p, .DEX)
	emit_branch_id(p, .BNE, loop)
	emit_imm(p, .LDA, 0x00);     emit_abs(p, .STA, VIA_ORA) // CS low
	emit_imm(p, .LDA, BANK_CS);  emit_abs(p, .STA, VIA_ORA) // CS 0->1: latch
	emit_impl(p, .RTS)
}

@(private) BANK_SWITCH_NAME :: "__gt_banksw"

// Select the 16 KB bank (0..126) mapped at $8000-$BFFF. Requires size = .Flash2M.
set_bank :: proc(p: ^Program, page: u8) {
	emit_imm(p, .LDA, page)
	emit_jsr(p, BANK_SWITCH_NAME)
}

// Select the bank from a zero-page variable.
set_bank_var :: proc(p: ^Program, page_zp: u8) {
	emit_zp(p, .LDA, page_zp)
	emit_jsr(p, BANK_SWITCH_NAME)
}
