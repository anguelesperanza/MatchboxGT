package gametank

// =============================================================================
// Pseudo-random numbers
// =============================================================================
//
// A single global generator — an 8-bit Galois LFSR whose state lives in one
// reserved zero-page byte (GT_RNG). It's cheap (a shift and a conditional EOR)
// and has a period of 255. Seed it once in setup with any NONZERO byte (a zero
// seed sticks the generator at zero forever), then pull bytes with random/
// random_var/random_into. Calling random once per frame as well keeps the stream
// tied to how long the player has been going, so outcomes aren't identical every
// run.

@(private) RNG_TAPS :: u8(0xB8) // maximal-length 8-bit LFSR feedback polynomial

// Seed the global RNG. Call once in setup with a nonzero byte.
random_seed :: proc(p: ^Program, seed: u8) {
	emit_imm(p, .LDA, seed)
	emit_zp(p, .STA, GT_RNG)
}

// Advance the RNG one step; the new byte is left in A (and in GT_RNG).
random :: proc(p: ^Program) {
	emit_zp(p, .LDA, GT_RNG)
	emit_acc(p, .LSR)
	skip := anon_fwd(p)
	emit_branch_id(p, .BCC, skip)   // bit shifted out was 0 -> no feedback
	emit_imm(p, .EOR, RNG_TAPS)
	put_label(p, skip)
	emit_zp(p, .STA, GT_RNG)
}

// Advance the RNG and store the new byte to a Var.
random_var :: proc(p: ^Program, dst: Var) {
	random(p)
	ld_var(p, .STA, dst)
}

// Advance the RNG, AND the new byte with `mask`, and store it to `addr`. The mask
// picks the range and alignment — e.g. 0x70 gives 0..112 in steps of 16, handy for
// a random on-screen position or object-table slot (OBJ_X + i, OBJ_Y + i).
random_into :: proc(p: ^Program, addr: u16, mask: u8) {
	random(p)
	emit_imm(p, .AND, mask)
	if addr < 0x0100 {
		emit_zp(p, .STA, u8(addr))
	} else {
		emit_abs(p, .STA, addr)
	}
}
