package gametank

import "core:fmt"

// =============================================================================
// Game state: variables + arithmetic + control flow
// =============================================================================
//
// This is the layer that lets you write game logic without hand-rolling 6502.
// A Var is one byte of RAM the framework hands you (no more picking $10, $11, …
// by hand); the set/inc/add/… helpers do the arithmetic; and the if_* helpers
// give you conditionals in the same shape as if_pressed:
//
//   skip := gt.if_ge(p, score, 100)
//   ... what happens when score >= 100 ...
//   gt.put_label(p, skip)
//
// with gt.otherwise for an else-clause. Because you author in Odin, ordinary
// `for`/`if` in your build program still unroll at zero runtime cost — reach for
// these only when the *game* needs to branch on a value that isn't known until
// it runs.
//
// RAM is not cleared at power-on, so a fresh Var holds garbage: `set` it (or
// otherwise write it) before you read it.

// A game variable: one byte of RAM at a framework-assigned address. Hold the Var
// an alloc_* returns in an Odin variable and pass it to the helpers below. The
// raw address is `v.addr` (for the older helpers that take a bare zero-page byte,
// e.g. read_gamepad1, pass `u8(v.addr)`).
Var :: struct {
	addr: u16,
}

@(private) VAR_ZP_BASE  :: u8(0x10)     // zero-page vars start here ($00-$0F reserved)
@(private) VAR_ZP_END   :: u16(0x00F0)  // exclusive: $F0-$FF is INFLATE scratch
@(private) VAR_RAM_BASE :: u16(0x0200)  // general RAM: the page between stack and objects
@(private) VAR_RAM_END  :: u16(0x0300)  // exclusive: $0300+ is the object table

// Allocate one byte for a game variable. Zero-page bytes ($10-$EF) are handed out
// first (they get the fast, compact instructions); once those run out it falls
// back to general RAM. Allocate in `setup` (or `assemble`) and keep the Var in an
// Odin variable. Allocation is deterministic across the builder's two passes, so
// the same call order always yields the same addresses.
alloc_var :: proc(p: ^Program) -> Var {
	if u16(p.zp_next) < VAR_ZP_END {
		a := u16(p.zp_next)
		p.zp_next += 1
		return Var{addr = a}
	}
	return Var{addr = alloc_bytes(p, 1)}
}

// Reserve `n` contiguous bytes of general RAM ($0200-$02FF) and return the base
// address — for hand-rolled arrays/tables. (The built-in object table lives
// separately at $0300+.)
alloc_bytes :: proc(p: ^Program, n: u16) -> u16 {
	if p.ram_next + n > VAR_RAM_END {
		fmt.eprintfln("gametank: out of general RAM ($0200-$02FF); %d more byte(s) requested", n)
		return VAR_RAM_BASE
	}
	a := p.ram_next
	p.ram_next += n
	return a
}

// Load/store/etc. a Var, picking zero-page or absolute addressing from its address.
@(private)
ld_var :: proc(p: ^Program, mn: Mnemonic, v: Var) {
	if v.addr < 0x0100 {
		emit_zp(p, mn, u8(v.addr))
	} else {
		emit_abs(p, mn, v.addr)
	}
}

// -----------------------------------------------------------------------------
// Assignment + arithmetic. Everything except inc/dec clobbers A.
// -----------------------------------------------------------------------------

set      :: proc(p: ^Program, v: Var, n: u8) { p.var_inited = true; emit_imm(p, .LDA, n); ld_var(p, .STA, v) }     // v = n
copy_var :: proc(p: ^Program, dst, src: Var) { p.var_inited = true; ld_var(p, .LDA, src); ld_var(p, .STA, dst) }  // dst = src
inc     :: proc(p: ^Program, v: Var)          { ld_var(p, .INC, v) }                                // v += 1 (255 -> 0)
dec     :: proc(p: ^Program, v: Var)          { ld_var(p, .DEC, v) }                                // v -= 1 (0 -> 255)

add     :: proc(p: ^Program, v: Var, n: u8)   { ld_var(p, .LDA, v); emit_impl(p, .CLC); emit_imm(p, .ADC, n); ld_var(p, .STA, v) } // v += n
sub     :: proc(p: ^Program, v: Var, n: u8)   { ld_var(p, .LDA, v); emit_impl(p, .SEC); emit_imm(p, .SBC, n); ld_var(p, .STA, v) } // v -= n
add_var :: proc(p: ^Program, v, o: Var)       { ld_var(p, .LDA, v); emit_impl(p, .CLC); ld_var(p, .ADC, o); ld_var(p, .STA, v) }   // v += o
sub_var :: proc(p: ^Program, v, o: Var)       { ld_var(p, .LDA, v); emit_impl(p, .SEC); ld_var(p, .SBC, o); ld_var(p, .STA, v) }   // v -= o

// -----------------------------------------------------------------------------
// Conditionals. Each opens an "if" block: emit the body, then close it with
// put_label(p, <returned id>). Comparisons are unsigned and clobber A. Use
// `otherwise` between the body and its put_label for an else-clause.
// -----------------------------------------------------------------------------

if_eq :: proc(p: ^Program, v: Var, n: u8) -> u32 { // v == n
	ld_var(p, .LDA, v); emit_imm(p, .CMP, n); return begin_if(p, .BEQ)
}
if_ne :: proc(p: ^Program, v: Var, n: u8) -> u32 { // v != n
	ld_var(p, .LDA, v); emit_imm(p, .CMP, n); return begin_if(p, .BNE)
}
if_lt :: proc(p: ^Program, v: Var, n: u8) -> u32 { // v < n (unsigned)
	ld_var(p, .LDA, v); emit_imm(p, .CMP, n); return begin_if(p, .BCC)
}
if_ge :: proc(p: ^Program, v: Var, n: u8) -> u32 { // v >= n (unsigned)
	ld_var(p, .LDA, v); emit_imm(p, .CMP, n); return begin_if(p, .BCS)
}
if_zero :: proc(p: ^Program, v: Var) -> u32 {      // v == 0
	ld_var(p, .LDA, v); return begin_if(p, .BEQ)
}
if_nonzero :: proc(p: ^Program, v: Var) -> u32 {   // v != 0
	ld_var(p, .LDA, v); return begin_if(p, .BNE)
}

// -----------------------------------------------------------------------------
// 16-bit variables (0..65535) — for scores and counters that outgrow a byte.
// Two consecutive RAM bytes: low at addr, high at addr+1.
// -----------------------------------------------------------------------------

Var16 :: struct {
	addr: u16,
}

// Allocate a 16-bit variable (two consecutive bytes; zero page first). Init it
// with set16 before reading — RAM is not power-on-zeroed.
alloc_var16 :: proc(p: ^Program) -> Var16 {
	if u16(p.zp_next) + 1 < VAR_ZP_END {
		a := u16(p.zp_next)
		p.zp_next += 2
		return Var16{addr = a}
	}
	return Var16{addr = alloc_bytes(p, 2)}
}

// Load/store a byte of a Var16 (lo = offset 0, hi = offset 1), zero-page or abs.
@(private)
ld16 :: proc(p: ^Program, mn: Mnemonic, v: Var16, hi: bool) {
	a := v.addr
	if hi { a += 1 }
	if a < 0x100 {
		emit_zp(p, mn, u8(a))
	} else {
		emit_abs(p, mn, a)
	}
}

set16 :: proc(p: ^Program, v: Var16, n: u16) { // v = n; clobbers A
	p.var_inited = true
	emit_imm(p, .LDA, u8(n)); ld16(p, .STA, v, false)
	emit_imm(p, .LDA, u8(n >> 8)); ld16(p, .STA, v, true)
}

inc16 :: proc(p: ^Program, v: Var16) { // v += 1 (carries into the high byte)
	ld16(p, .INC, v, false)
	skip := anon_fwd(p)
	emit_branch_id(p, .BNE, skip)      // low byte didn't wrap -> done
	ld16(p, .INC, v, true)
	put_label(p, skip)
}

add16 :: proc(p: ^Program, v: Var16, n: u16) { // v += n; clobbers A
	ld16(p, .LDA, v, false); emit_impl(p, .CLC); emit_imm(p, .ADC, u8(n));      ld16(p, .STA, v, false)
	ld16(p, .LDA, v, true);                       emit_imm(p, .ADC, u8(n >> 8)); ld16(p, .STA, v, true)
}

// Turn an open if-block into if/else. Emit after the "then" body, passing the id
// the if_* returned; emit the "else" body next, then close with put_label(p, end):
//
//   skip := gt.if_zero(p, lives)
//   ... then (game over) ...
//   end := gt.otherwise(p, skip)
//   ... else (keep playing) ...
//   gt.put_label(p, end)
otherwise :: proc(p: ^Program, then_skip: u32) -> u32 {
	end := anon_fwd(p)
	emit_jump_id(p, end)    // after the then-body, skip over the else-body
	put_label(p, then_skip) // the else-body starts here
	return end
}
