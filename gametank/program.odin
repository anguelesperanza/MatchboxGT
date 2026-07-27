package gametank

import "core:fmt"
import "core:os"
import m "core:rexcode/isa/mos6502"

// =============================================================================
// Program builder
// =============================================================================
//
// A Program accumulates the 65C02 instruction stream, named/anonymous labels
// (over rexcode's label + relocation system), and data blobs that get appended
// after the code. build_rom (rom.odin) turns a Program into a .gtr image.
//
// You rarely touch a Program's fields directly — use the emit_* helpers and the
// label / blob procedures below.

// Re-export so callers can name the mnemonic type if they build instructions
// by hand; day to day the emit_* helpers infer it from `.LDA`-style selectors.
Mnemonic :: m.Mnemonic

Blob :: struct {
	name: string,
	data: []u8,
	bank: int, // -1 = fixed region (after code); >=0 = flash bank (mapped at $8000)
}

Program :: struct {
	base:       u16,                      // ROM origin (for address math)
	insts:      [dynamic]m.Instruction,
	labels:     [dynamic]m.Label_Definition,
	names:      map[string]u32,           // label name -> label id
	blobs:      [dynamic]Blob,
	blob_names: map[string]int,           // blob name -> index in `blobs`
	resolved:   map[string]u16,           // blob name -> absolute address (pass 2)
	zp_next:    u8,                       // next free zero-page var address (state.odin)
	ram_next:   u16,                      // next free general-RAM address (state.odin)
}

program_init :: proc(p: ^Program, base: u16) {
	p.base       = base
	p.insts      = make([dynamic]m.Instruction)
	p.labels     = make([dynamic]m.Label_Definition)
	p.names      = make(map[string]u32)
	p.blobs      = make([dynamic]Blob)
	p.blob_names = make(map[string]int)
	p.resolved   = make(map[string]u16)
	p.zp_next    = VAR_ZP_BASE   // $10 (below it is framework-reserved)
	p.ram_next   = VAR_RAM_BASE  // $0200 (page between the stack and object table)
}

program_destroy :: proc(p: ^Program) {
	delete(p.insts)
	delete(p.labels)
	delete(p.names)
	delete(p.blobs)
	delete(p.blob_names)
	delete(p.resolved)
}

// -----------------------------------------------------------------------------
// Labels
// -----------------------------------------------------------------------------

// Define a named label at the current position (call it where the label sits).
mark :: proc(p: ^Program, name: string) {
	if id, ok := p.names[name]; ok {
		p.labels[id] = m.Label_Definition(len(p.insts))
	} else {
		id := u32(len(p.labels))
		append(&p.labels, m.Label_Definition(len(p.insts)))
		p.names[name] = id
	}
}

// Get (reserving if needed) the label id for a name. Forward references are fine
// — the label just has to be mark()'d somewhere before build_rom finishes.
label_id :: proc(p: ^Program, name: string) -> u32 {
	if id, ok := p.names[name]; ok {
		return id
	}
	id := u32(len(p.labels))
	append(&p.labels, m.LABEL_UNDEFINED)
	p.names[name] = id
	return id
}

// Define an anonymous label at the current position (handy for tight loops in
// library code where a name would just be noise). Returns its id for the
// emit_*_id helpers.
anon :: proc(p: ^Program) -> u32 {
	id := u32(len(p.labels))
	append(&p.labels, m.Label_Definition(len(p.insts)))
	return id
}

// Reserve an anonymous label for a forward reference; define its position later
// with put_label. Used for "skip this block" branches.
anon_fwd :: proc(p: ^Program) -> u32 {
	id := u32(len(p.labels))
	append(&p.labels, m.LABEL_UNDEFINED)
	return id
}

// Define a previously reserved (anon_fwd) label at the current position.
put_label :: proc(p: ^Program, id: u32) {
	p.labels[id] = m.Label_Definition(len(p.insts))
}

// -----------------------------------------------------------------------------
// Data blobs (appended to the ROM after the code)
// -----------------------------------------------------------------------------

// Declare a named data blob in the fixed region (placed after the code). Safe to
// call every build pass (idempotent by name).
blob :: proc(p: ^Program, name: string, data: []u8) {
	blob_in(p, name, data, -1)
}

// Declare a data blob in a flash bank (0..126). It is mapped at $8000 when that
// bank is selected (set_bank). Requires a .Flash2M ROM. Idempotent by name.
bank_blob :: proc(p: ^Program, name: string, bank: int, data: []u8) {
	blob_in(p, name, data, bank)
}

@(private)
blob_in :: proc(p: ^Program, name: string, data: []u8, bank: int) {
	if idx, ok := p.blob_names[name]; ok {
		p.blobs[idx].data = data
		p.blobs[idx].bank = bank
		return
	}
	idx := len(p.blobs)
	append(&p.blobs, Blob{name = name, data = data, bank = bank})
	p.blob_names[name] = idx
}

// Declare a data blob whose bytes are read from a file at build time. Handy for
// embedding an asset your standalone tools produced (e.g. a .gtg.deflate sprite).
blob_file :: proc(p: ^Program, name: string, path: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("gametank: cannot read asset %q: %v", path, err)
		return
	}
	blob(p, name, data)
}

// Absolute address of a blob. Returns a placeholder during the measuring pass
// and the real address during the final pass — so emitting
// `emit_abs_x(p, .LDA, blob_addr(p, "table"))` just works.
blob_addr :: proc(p: ^Program, name: string) -> u16 {
	if a, ok := p.resolved[name]; ok {
		return a
	}
	return p.base
}

// -----------------------------------------------------------------------------
// Emit helpers — one per operand shape, mirroring rexcode's inst_* builders.
// The addressing mode is intrinsic to which helper you call.
// -----------------------------------------------------------------------------

emit :: proc(p: ^Program, inst: m.Instruction) { append(&p.insts, inst) }

// Set a zero-page byte to a constant: LDA #val / STA <addr>. Clobbers A.
set_zp :: proc(p: ^Program, addr: u8, val: u8) {
	emit_imm(p, .LDA, val)
	emit_zp(p, .STA, addr)
}

emit_impl :: proc(p: ^Program, mn: m.Mnemonic)          { append(&p.insts, m.inst_none(mn)) }     // INX, CLC, RTS, ...
emit_acc  :: proc(p: ^Program, mn: m.Mnemonic)          { append(&p.insts, m.inst_a(mn)) }        // ROL A
emit_imm  :: proc(p: ^Program, mn: m.Mnemonic, v: u8)   { append(&p.insts, m.inst_i(mn, i64(v))) } // LDA #v

emit_abs   :: proc(p: ^Program, mn: m.Mnemonic, addr: u16) { append(&p.insts, m.inst_m(mn, m.mem_abs(addr))) }
emit_abs_x :: proc(p: ^Program, mn: m.Mnemonic, addr: u16) { append(&p.insts, m.inst_m(mn, m.mem_abs_x(addr))) }
emit_abs_y :: proc(p: ^Program, mn: m.Mnemonic, addr: u16) { append(&p.insts, m.inst_m(mn, m.mem_abs_y(addr))) }
emit_zp    :: proc(p: ^Program, mn: m.Mnemonic, a: u8)     { append(&p.insts, m.inst_m(mn, m.mem_zp(a))) }
emit_zp_x  :: proc(p: ^Program, mn: m.Mnemonic, a: u8)     { append(&p.insts, m.inst_m(mn, m.mem_zp_x(a))) }
emit_ind_y :: proc(p: ^Program, mn: m.Mnemonic, a: u8)     { append(&p.insts, m.inst_m(mn, m.mem_ind_y(a))) }  // (zp),Y
emit_ind_zp:: proc(p: ^Program, mn: m.Mnemonic, a: u8)     { append(&p.insts, m.inst_m(mn, m.mem_ind_zp(a))) } // (zp) [65C02]

// Branch / jump to a named label.
emit_branch :: proc(p: ^Program, mn: m.Mnemonic, target: string) {
	append(&p.insts, m.inst_rel(mn, label_id(p, target)))
}
emit_jump :: proc(p: ^Program, target: string) {
	append(&p.insts, m.Instruction{
		mnemonic = .JMP, operand_count = 1, length = 0,
		ops = {m.op_label(label_id(p, target), 2), {}, {}},
	})
}
emit_jsr :: proc(p: ^Program, target: string) {
	append(&p.insts, m.Instruction{
		mnemonic = .JSR, operand_count = 1, length = 0,
		ops = {m.op_label(label_id(p, target), 2), {}, {}},
	})
}

// Branch / jump to an anonymous label id (from anon()).
emit_branch_id :: proc(p: ^Program, mn: m.Mnemonic, target: u32) {
	append(&p.insts, m.inst_rel(mn, target))
}
emit_jump_id :: proc(p: ^Program, target: u32) {
	append(&p.insts, m.Instruction{
		mnemonic = .JMP, operand_count = 1, length = 0,
		ops = {m.op_label(target, 2), {}, {}},
	})
}
