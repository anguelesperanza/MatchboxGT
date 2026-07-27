package gametank

import "core:fmt"
import m "core:rexcode/isa/mos6502"

// =============================================================================
// Audio: a 4-voice square-wave mixer on the ACP
// =============================================================================
//
// The ACP is a second 6502 with its own DAC and 4 KiB of RAM shared with the
// main CPU (main sees it at $3000-$3FFF; the ACP sees it at $0000-$0FFF, and the
// DAC at $8000+). Instead of bundling a precompiled program, we ASSEMBLE our own
// mixer with rexcode and copy it into the ACP.
//
// Each of 4 voices has a 16-bit rate and an 8-bit volume in shared RAM. Every
// sample the ACP does, per voice: phase += rate; if the phase's top bit is set,
// add the voice's volume to the mix. The mix byte is written to the DAC. So each
// voice is a square wave; volume 0 = off. Keep the sum <= 255 (4 * 60 default).
//
// Shared-RAM layout (main CPU addresses):
//   $3001/$3002 voice0 rate,  $3003 voice0 vol
//   $3004/$3005 voice1 rate,  $3006 voice1 vol
//   $3007/$3008 voice2 rate,  $3009 voice2 vol
//   $300A/$300B voice3 rate,  $300C voice3 vol
//
// Requires no INFLATE (the mixer is copied raw). Pitch comes from the bundled
// MIDI->rate table. Call audio_init once, then voice_note / voice_off.

@(private) PITCHES := #load("assets/pitches.dat") // 2 bytes per MIDI note

VOICES        :: 4
DEFAULT_VOL   :: u8(60) // per-voice volume for the audio_note shortcut
@(private) AUDIO_STOP_BYTE :: u8(0x7F)
@(private) AUDIO_RUN_BYTE  :: u8(0xFF)

// ACP-side zero-page layout (the ACP sees shared RAM at $0000; skip $00 — the
// hardware clobbers it on DAC writes).
@(private) ACP_R0  :: u8(0x01) // voice rates (lo, hi at +1); voices are 3 apart
@(private) ACP_V0  :: u8(0x03) // voice volumes
@(private) ACP_PH0 :: u8(0x10) // phase accumulators (2 bytes each)
@(private) ACP_MIX :: u8(0x18) // per-sample mix accumulator
@(private) ACP_DAC :: u16(0x8000)
@(private) ACP_ORG :: u16(0x0200) // ACP code origin (matches square.asm)
@(private) ACP_LOAD :: u16(0x3200) // where the main CPU writes it: $3000 + $0200

// The assembled mixer (built once, lazily) and its ACP-space handler addresses.
@(private) acp_code:  []u8
@(private) acp_reset: u16
@(private) acp_irq:   u16
@(private) acp_nmi:   u16
@(private) acp_ready: bool

// One voice of the mixer IRQ: phase += rate; if phase's top bit is set, add the
// voice's volume to the running mix.
@(private)
acp_voice :: proc(p: ^Program, ph, rate, vol: u8) {
	emit_impl(p, .CLC)
	emit_zp(p, .LDA, ph);     emit_zp(p, .ADC, rate);     emit_zp(p, .STA, ph)
	emit_zp(p, .LDA, ph + 1); emit_zp(p, .ADC, rate + 1); emit_zp(p, .STA, ph + 1)
	skip := anon_fwd(p)
	emit_branch_id(p, .BPL, skip) // top bit clear -> this voice is low -> skip
	emit_impl(p, .CLC)
	emit_zp(p, .LDA, ACP_MIX); emit_zp(p, .ADC, vol); emit_zp(p, .STA, ACP_MIX)
	put_label(p, skip)
}

// Assemble the mixer program at the ACP origin. Returns its bytes plus the
// ACP-space addresses of its RESET/IRQ/NMI handlers.
@(private)
build_acp :: proc() -> (code: []u8, reset, irq, nmi: u16, ok: bool) {
	p: Program
	program_init(&p, ACP_ORG)
	defer program_destroy(&p)

	mark(&p, "acp_reset")
	emit_impl(&p, .CLI)
	mark(&p, "acp_fore")
	emit_jump(&p, "acp_fore") // idle; all the work happens in the sample IRQ

	mark(&p, "acp_irq")
	emit_imm(&p, .LDA, 0x00); emit_zp(&p, .STA, ACP_MIX)
	acp_voice(&p, ACP_PH0 + 0, ACP_R0 + 0, ACP_V0 + 0)
	acp_voice(&p, ACP_PH0 + 2, ACP_R0 + 3, ACP_V0 + 3)
	acp_voice(&p, ACP_PH0 + 4, ACP_R0 + 6, ACP_V0 + 6)
	acp_voice(&p, ACP_PH0 + 6, ACP_R0 + 9, ACP_V0 + 9)
	emit_zp(&p, .LDA, ACP_MIX); emit_abs(&p, .STA, ACP_DAC)
	emit_impl(&p, .RTI)

	mark(&p, "acp_nmi")
	emit_impl(&p, .RTI)

	relocs: [dynamic]m.Relocation
	errors: [dynamic]m.Error
	defer delete(relocs)
	defer delete(errors)
	buf := make([]u8, m.encode_max_code_size(p.insts[:]))
	n, enc_ok := m.encode(p.insts[:], p.labels[:], buf, &relocs, &errors, resolve = true, base_address = u64(ACP_ORG))
	if !enc_ok || len(relocs) > 0 {
		delete(buf)
		return nil, 0, 0, 0, false
	}
	out := make([]u8, n)
	copy(out, buf[:n])
	delete(buf)
	r, _ := label_addr(&p, "acp_reset")
	i, _ := label_addr(&p, "acp_irq")
	nm, _ := label_addr(&p, "acp_nmi")
	return out, r, i, nm, true
}

// Assemble the mixer (once), then emit code that loads it into the ACP and starts
// it: pause the ACP, zero its voice state, copy the program in, write its
// vectors, pulse reset, enable. Call once at startup after the stack is set up.
audio_init :: proc(p: ^Program) {
	if !acp_ready {
		code, rst, ir, nm, ok := build_acp()
		if !ok {
			fmt.eprintln("gametank: failed to assemble the ACP mixer")
			return
		}
		acp_code = code; acp_reset = rst; acp_irq = ir; acp_nmi = nm; acp_ready = true
	}
	blob(p, "__gt_acp", acp_code)
	blob(p, "__gt_pitches", PITCHES)

	emit_imm(p, .LDA, AUDIO_STOP_BYTE); emit_abs(p, .STA, AUDIO_RATE) // pause ACP

	// zero voice state ($3000-$301F): rates, volumes, phases all start at 0
	emit_imm(p, .LDX, 0x1F)
	emit_imm(p, .LDA, 0x00)
	zloop := anon(p)
	emit_abs_x(p, .STA, 0x3000)
	emit_impl(p, .DEX)
	emit_branch_id(p, .BPL, zloop)

	// copy the mixer program into ACP RAM at $3200 (= ACP $0200)
	src := blob_addr(p, "__gt_acp")
	emit_imm(p, .LDX, u8(len(acp_code) - 1))
	cloop := anon(p)
	emit_abs_x(p, .LDA, src)
	emit_abs_x(p, .STA, ACP_LOAD)
	emit_impl(p, .DEX)
	emit_branch_id(p, .BPL, cloop)

	// write the ACP interrupt vectors at $3FFA (= ACP $0FFA)
	emit_imm(p, .LDA, u8(acp_nmi));         emit_abs(p, .STA, 0x3FFA)
	emit_imm(p, .LDA, u8(acp_nmi >> 8));    emit_abs(p, .STA, 0x3FFB)
	emit_imm(p, .LDA, u8(acp_reset));       emit_abs(p, .STA, 0x3FFC)
	emit_imm(p, .LDA, u8(acp_reset >> 8));  emit_abs(p, .STA, 0x3FFD)
	emit_imm(p, .LDA, u8(acp_irq));         emit_abs(p, .STA, 0x3FFE)
	emit_imm(p, .LDA, u8(acp_irq >> 8));    emit_abs(p, .STA, 0x3FFF)

	emit_abs(p, .STZ, ACP_RESET)                                     // start it
	emit_imm(p, .LDA, AUDIO_RUN_BYTE); emit_abs(p, .STA, AUDIO_RATE) // enable
}

// A holds a MIDI note; write its rate + volume to `voice` (0..3).
@(private)
emit_voice :: proc(p: ^Program, voice, vol: u8) {
	pa := blob_addr(p, "__gt_pitches")
	base := u16(0x3001) + u16(voice) * 3
	emit_acc(p, .ASL)
	emit_impl(p, .TAX)
	emit_abs_x(p, .LDA, pa + 1); emit_abs(p, .STA, base)     // rate lo
	emit_abs_x(p, .LDA, pa);     emit_abs(p, .STA, base + 1) // rate hi
	emit_imm(p, .LDA, vol);      emit_abs(p, .STA, base + 2) // volume
}

// Play a constant MIDI note on a voice (0..3) at a given volume.
voice_note :: proc(p: ^Program, voice, note, vol: u8) {
	emit_imm(p, .LDA, note)
	emit_voice(p, voice, vol)
}

// Play a MIDI note (from a zero-page var) on a voice.
voice_note_var :: proc(p: ^Program, voice, note_zp, vol: u8) {
	emit_zp(p, .LDA, note_zp)
	emit_voice(p, voice, vol)
}

// Silence a single voice.
voice_off :: proc(p: ^Program, voice: u8) {
	emit_imm(p, .LDA, 0x00)
	emit_abs(p, .STA, u16(0x3003) + u16(voice) * 3)
}

// Convenience/back-compat: a single note on voice 0 at the default volume.
audio_note :: proc(p: ^Program, note: u8) { voice_note(p, 0, note, DEFAULT_VOL) }
audio_note_var :: proc(p: ^Program, note_zp: u8) { voice_note_var(p, 0, note_zp, DEFAULT_VOL) }

// Silence all voices.
audio_silence :: proc(p: ^Program) {
	for v in 0 ..< u8(VOICES) { voice_off(p, v) }
}

// Pause the whole ACP.
audio_stop :: proc(p: ^Program) {
	emit_imm(p, .LDA, AUDIO_STOP_BYTE)
	emit_abs(p, .STA, AUDIO_RATE)
}
