package gametank

import "core:fmt"
import "core:os"
import m "core:rexcode/isa/mos6502"

// =============================================================================
// ROM configuration + build driver
// =============================================================================

// Supported raw ROM images. An N-byte image is mapped to the top of the 64 KiB
// space so the CPU vectors land at $FFFA. (Banked/2 MB carts are a later hook.)
Rom_Size :: enum u8 {
	K8,      // 8 KiB  -> $E000-$FFFF   (verified against the tutorial)
	K32,     // 32 KiB -> $8000-$FFFF   (fills the whole cartridge window)
	Flash2M, // 2 MiB banked: code fixed at $C000-$FFFF, data in banks 0-126 ($8000)
}

Config :: struct {
	size:    Rom_Size, // image size / mapping
	out:     string,   // output path (e.g. "game.gtr")
	reset:   string,   // RESET vector label; "" = start of emitted code
	nmi:     string,   // NMI vector label;   "" = a default RTI handler
	irq:     string,   // IRQ vector label;   "" = a default RTI handler
	inflate: bool,     // bundle the INFLATE routine at $E000 (for compressed assets)
	quiet:   bool,     // suppress the build summary
}

@(private) DEFAULT_NMI :: "__gt_nmi"
@(private) DEFAULT_IRQ :: "__gt_irq"

// The INFLATE (zlib6502) decompressor, assembled to run at $E000. When
// Config.inflate is set it is placed at the ROM base and code starts after it.
@(private) INFLATE_RESERVED :: 512   // reserve $E000-$E1FF for the routine
@(private) INFLATE_BLOB := #load("assets/inflate_e000_0200.obx")

@(private)
rom_capacity :: proc(s: Rom_Size) -> int {
	switch s {
	case .K8:      return 8192
	case .K32:     return 32768
	case .Flash2M: return 2097152
	}
	return 8192
}

@(private)
rom_origin :: proc(s: Rom_Size) -> u16 {
	switch s {
	case .K8:      return 0xE000
	case .K32:     return 0x8000
	case .Flash2M: return 0xC000 // fixed region; banked layout handled separately
	}
	return 0xE000
}

// Build a ROM image by running `gen` to populate a Program, then laying out
// code + data + vectors and writing the raw .gtr. Returns false (after printing
// a diagnostic) on any error.
//
// `gen` is invoked twice — once to measure the code, once with real data
// addresses — so it must be deterministic (the usual case for a code generator).
build_rom :: proc(cfg: Config, gen: proc(p: ^Program)) -> bool {
	if cfg.size == .Flash2M {
		return build_flash2m(cfg, gen)
	}
	base     := rom_origin(cfg.size)
	capacity := rom_capacity(cfg.size)

	// The INFLATE routine is locked to $E000, so compressed-asset ROMs must be
	// 8 KiB (base $E000) with code starting just after the routine.
	prologue := 0
	if cfg.inflate {
		if cfg.size != .K8 {
			fmt.eprintfln("gametank: Config.inflate requires size = .K8 (INFLATE is locked to $E000)")
			return false
		}
		prologue = INFLATE_RESERVED
	}
	code_base := base + u16(prologue)

	// ---- pass 1: measure the code, discover blob sizes ----------------------
	p1: Program
	program_init(&p1, code_base)
	defer program_destroy(&p1)
	gen(&p1)
	finalize_handlers(&p1, cfg)
	code1, ok1 := assemble(&p1, code_base)
	if !ok1 {
		return false
	}
	code_len := len(code1)
	delete(code1)

	// ---- assign blob addresses immediately after the code -------------------
	resolved := make(map[string]u16)
	defer delete(resolved)
	off := code_len
	for b in p1.blobs {
		resolved[b.name] = code_base + u16(off)
		off += len(b.data)
	}
	data_len := off - code_len

	if prologue + code_len + data_len > capacity - 6 {
		fmt.eprintfln("gametank: ROM overflow — prologue %d + code %d + data %d > %d usable bytes",
			prologue, code_len, data_len, capacity - 6)
		return false
	}

	// ---- pass 2: assemble for real ------------------------------------------
	p2: Program
	program_init(&p2, code_base)
	defer program_destroy(&p2)
	for name, addr in resolved {
		p2.resolved[name] = addr
	}
	gen(&p2)
	finalize_handlers(&p2, cfg)
	code, ok2 := assemble(&p2, code_base)
	if !ok2 {
		return false
	}
	defer delete(code)
	if len(code) != code_len {
		fmt.eprintfln("gametank: internal error — code length changed between passes (%d -> %d)",
			code_len, len(code))
		return false
	}

	// ---- compose the image --------------------------------------------------
	img := make([]u8, capacity)
	defer delete(img)
	if cfg.inflate {
		copy(img[:], INFLATE_BLOB)   // $E000: the decompressor
	}
	copy(img[prologue:], code)
	o := prologue + code_len
	for b in p2.blobs {
		copy(img[o:], b.data)
		o += len(b.data)
	}

	// ---- vectors ($FFFA/$FFFC/$FFFE = last 6 bytes) -------------------------
	nmi_name := DEFAULT_NMI; if cfg.nmi != "" { nmi_name = cfg.nmi }
	irq_name := DEFAULT_IRQ; if cfg.irq != "" { irq_name = cfg.irq }

	reset_addr := code_base
	ok_r := true
	if cfg.reset != "" {
		reset_addr, ok_r = label_addr(&p2, cfg.reset)
	}
	nmi_addr, ok_n := label_addr(&p2, nmi_name)
	irq_addr, ok_i := label_addr(&p2, irq_name)
	if !ok_r || !ok_n || !ok_i {
		fmt.eprintfln("gametank: could not resolve a vector label (reset=%q nmi=%q irq=%q)",
			cfg.reset, nmi_name, irq_name)
		return false
	}

	v := capacity - 6
	img[v+0] = u8(nmi_addr);   img[v+1] = u8(nmi_addr   >> 8)
	img[v+2] = u8(reset_addr); img[v+3] = u8(reset_addr >> 8)
	img[v+4] = u8(irq_addr);   img[v+5] = u8(irq_addr   >> 8)

	// ---- write --------------------------------------------------------------
	if werr := os.write_entire_file(cfg.out, img); werr != nil {
		fmt.eprintfln("gametank: failed to write %s: %v", cfg.out, werr)
		return false
	}

	if !cfg.quiet {
		fmt.printfln("wrote %s", cfg.out)
		fmt.printfln("  ROM     : %d bytes, mapped $%04X-$FFFF", capacity, base)
		if cfg.inflate {
			fmt.printfln("  inflate : %d bytes @ $%04X (code starts $%04X)", len(INFLATE_BLOB), base, code_base)
		}
		fmt.printfln("  code    : %d bytes", code_len)
		fmt.printfln("  data    : %d bytes in %d blob(s)", data_len, len(p2.blobs))
		for b in p2.blobs {
			fmt.printfln("    %-14s %5d bytes @ $%04X", b.name, len(b.data), resolved[b.name])
		}
		fmt.printfln("  vectors : RESET=$%04X  NMI=$%04X  IRQ=$%04X", reset_addr, nmi_addr, irq_addr)
	}
	return true
}

// Build a 2 MiB banked flash ROM. All code lives in the fixed region
// ($C000-$FFFF = the last 16 KiB); fixed-region data follows the code; banked
// blobs go in banks 0-126 (mapped at $8000 when selected via set_bank).
@(private)
build_flash2m :: proc(cfg: Config, gen: proc(p: ^Program)) -> bool {
	CAP       :: 2097152
	FIXED_ORG :: u16(0xC000)  // fixed region CPU address
	FIXED_OFF :: 0x1FC000     // fixed region file offset (bank 127)
	FIXED_LEN :: 0x4000       // 16 KiB
	VEC_OFF   :: FIXED_OFF + 0x3FFA
	INFLATE_AT :: 0x2000      // INFLATE lives at $E000 = $C000 + $2000

	// ---- pass 1: measure the fixed-region code ------------------------------
	p1: Program
	program_init(&p1, FIXED_ORG)
	defer program_destroy(&p1)
	gen(&p1)
	finalize_handlers(&p1, cfg)
	emit_bank_switch(&p1, BANK_SWITCH_NAME)
	code1, ok1 := assemble(&p1, FIXED_ORG)
	if !ok1 { return false }
	code_len := len(code1)
	delete(code1)

	if cfg.inflate && code_len > INFLATE_AT {
		fmt.eprintfln("gametank: fixed-region code (%d) overruns INFLATE at $E000", code_len)
		return false
	}

	// ---- assign blob addresses ---------------------------------------------
	// fixed blobs after the code (or after INFLATE if compressed assets are used)
	resolved := make(map[string]u16)
	defer delete(resolved)
	bank_used := make(map[int]int) // bank -> bytes used
	defer delete(bank_used)
	fixed_off := code_len
	if cfg.inflate { fixed_off = INFLATE_AT + INFLATE_RESERVED }
	for b in p1.blobs {
		if b.bank < 0 {
			resolved[b.name] = FIXED_ORG + u16(fixed_off)
			fixed_off += len(b.data)
		} else {
			if b.bank > 126 {
				fmt.eprintfln("gametank: bank %d out of range (0-126)", b.bank)
				return false
			}
			o := bank_used[b.bank]
			resolved[b.name] = 0x8000 + u16(o)
			bank_used[b.bank] = o + len(b.data)
		}
	}
	if fixed_off > 0x3FFA {
		fmt.eprintfln("gametank: fixed region overflow (%d > 16 KiB usable)", fixed_off)
		return false
	}
	for bank, sz in bank_used {
		if sz > FIXED_LEN {
			fmt.eprintfln("gametank: bank %d overflow (%d > 16 KiB)", bank, sz)
			return false
		}
	}

	// ---- pass 2: assemble for real -----------------------------------------
	p2: Program
	program_init(&p2, FIXED_ORG)
	defer program_destroy(&p2)
	for name, addr in resolved { p2.resolved[name] = addr }
	gen(&p2)
	finalize_handlers(&p2, cfg)
	emit_bank_switch(&p2, BANK_SWITCH_NAME)
	code, ok2 := assemble(&p2, FIXED_ORG)
	if !ok2 { return false }
	defer delete(code)
	if len(code) != code_len {
		fmt.eprintfln("gametank: internal error — code length changed between passes")
		return false
	}

	// ---- compose the 2 MiB image -------------------------------------------
	img := make([]u8, CAP)
	defer delete(img)
	copy(img[FIXED_OFF:], code)
	if cfg.inflate { copy(img[FIXED_OFF + INFLATE_AT:], INFLATE_BLOB) }
	for b in p2.blobs {
		if b.bank < 0 {
			copy(img[FIXED_OFF + int(resolved[b.name] - FIXED_ORG):], b.data)
		} else {
			copy(img[b.bank * FIXED_LEN + int(resolved[b.name] - 0x8000):], b.data)
		}
	}

	// ---- vectors ------------------------------------------------------------
	nmi_name := DEFAULT_NMI; if cfg.nmi != "" { nmi_name = cfg.nmi }
	irq_name := DEFAULT_IRQ; if cfg.irq != "" { irq_name = cfg.irq }
	reset_addr := FIXED_ORG
	ok_r := true
	if cfg.reset != "" { reset_addr, ok_r = label_addr(&p2, cfg.reset) }
	nmi_addr, ok_n := label_addr(&p2, nmi_name)
	irq_addr, ok_i := label_addr(&p2, irq_name)
	if !ok_r || !ok_n || !ok_i {
		fmt.eprintfln("gametank: could not resolve a vector label")
		return false
	}
	img[VEC_OFF+0] = u8(nmi_addr);   img[VEC_OFF+1] = u8(nmi_addr   >> 8)
	img[VEC_OFF+2] = u8(reset_addr); img[VEC_OFF+3] = u8(reset_addr >> 8)
	img[VEC_OFF+4] = u8(irq_addr);   img[VEC_OFF+5] = u8(irq_addr   >> 8)

	if werr := os.write_entire_file(cfg.out, img[:]); werr != nil {
		fmt.eprintfln("gametank: failed to write %s: %v", cfg.out, werr)
		return false
	}
	if !cfg.quiet {
		fmt.printfln("wrote %s", cfg.out)
		fmt.printfln("  ROM     : 2 MiB flash (fixed code $C000-$FFFF, data banks 0-126)")
		fmt.printfln("  code    : %d bytes (fixed region)", code_len)
		for b in p2.blobs {
			if b.bank < 0 {
				fmt.printfln("    %-12s %5d bytes @ $%04X (fixed)", b.name, len(b.data), resolved[b.name])
			} else {
				fmt.printfln("    %-12s %5d bytes @ $%04X (bank %d)", b.name, len(b.data), resolved[b.name], b.bank)
			}
		}
		fmt.printfln("  vectors : RESET=$%04X  NMI=$%04X  IRQ=$%04X", reset_addr, nmi_addr, irq_addr)
	}
	return true
}

// Install default interrupt handlers for any vector the config leaves unset.
// NMI defaults to a bare RTI; IRQ defaults to the blit-completion handler (so
// blit_go's wait works even when the program never sets its own IRQ handler).
@(private)
finalize_handlers :: proc(p: ^Program, cfg: Config) {
	if cfg.nmi == "" {
		mark(p, DEFAULT_NMI)
		emit_impl(p, .RTI)
	}
	if cfg.irq == "" {
		emit_blit_isr(p, DEFAULT_IRQ)
	}
}

// Absolute address of a (post-encode) label, or (0, false) if missing/undefined.
@(private)
label_addr :: proc(p: ^Program, name: string) -> (u16, bool) {
	id, ok := p.names[name]
	if !ok {
		return 0, false
	}
	d := p.labels[id]
	if d == m.LABEL_UNDEFINED {
		return 0, false
	}
	return p.base + u16(d), true
}

// Encode a Program to machine code at `base`. After this, p.labels hold byte
// offsets (rexcode rewrites them in place). Returns freshly-allocated bytes.
@(private)
assemble :: proc(p: ^Program, base: u16) -> ([]u8, bool) {
	relocs: [dynamic]m.Relocation
	errors: [dynamic]m.Error
	defer delete(relocs)
	defer delete(errors)

	buf := make([]u8, m.encode_max_code_size(p.insts[:]))
	n, enc_ok := m.encode(p.insts[:], p.labels[:], buf, &relocs, &errors,
		resolve = true, base_address = u64(base))
	if !enc_ok {
		for e in errors {
			fmt.eprintfln("gametank: encode error at instruction %d: %v", e.inst_idx, e.code)
		}
		delete(buf)
		return nil, false
	}
	if len(relocs) > 0 {
		fmt.eprintfln("gametank: %d unresolved label reference(s) — a branch/jump target was never mark()'d",
			len(relocs))
		delete(buf)
		return nil, false
	}
	out := make([]u8, n)
	copy(out, buf[:n])
	delete(buf)
	return out, true
}
