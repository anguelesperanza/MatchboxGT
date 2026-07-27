package main

// Audio demo: a 3-chord progression (C -> F -> G) played on three voices at once
// — polyphony via the ACP mixer. Three bars show the three voices' pitches.
//
//   odin run examples/audio      # from the repo root; writes audio.gtr
//
// (Turn the emulator's sound on — you should hear three notes together, cycling.)

import gt "../../gametank"

CHORD  :: u8(0x10) // 0..2
FRAMES :: u8(0x11)
NOTE0  :: u8(0x12) // current chord's three notes (for the bars)
NOTE1  :: u8(0x13)
NOTE2  :: u8(0x14)

VOL  :: u8(40) // per-voice (3 * 40 = 120, well under the 255 mix ceiling)
STEP :: u8(48) // frames per chord

// Set the three voices + note vars to a chord (notes are build-time constants).
set_chord :: proc(p: ^gt.Program, n0, n1, n2: u8) {
	gt.set_zp(p, NOTE0, n0); gt.voice_note(p, 0, n0, VOL)
	gt.set_zp(p, NOTE1, n1); gt.voice_note(p, 1, n1, VOL)
	gt.set_zp(p, NOTE2, n2); gt.voice_note(p, 2, n2, VOL)
}

// Emit the "select_chord" subroutine: play the chord matching CHORD, then RTS.
// (Uses JMP for the dispatch because each chord block is bigger than an 8-bit
// branch can reach.)
emit_select_chord :: proc(p: ^gt.Program) {
	gt.mark(p, "select_chord")
	gt.emit_zp(p, .LDA, CHORD)
	n1 := gt.anon_fwd(p); a1 := gt.anon_fwd(p)
	n2 := gt.anon_fwd(p); a2 := gt.anon_fwd(p)
	gt.emit_imm(p, .CMP, 1); gt.emit_branch_id(p, .BNE, n1); gt.emit_jump_id(p, a1)
	gt.put_label(p, n1)
	gt.emit_imm(p, .CMP, 2); gt.emit_branch_id(p, .BNE, n2); gt.emit_jump_id(p, a2)
	gt.put_label(p, n2)
	set_chord(p, 60, 64, 67); gt.emit_impl(p, .RTS) // C major
	gt.put_label(p, a1)
	set_chord(p, 65, 69, 72); gt.emit_impl(p, .RTS) // F major
	gt.put_label(p, a2)
	set_chord(p, 67, 71, 74); gt.emit_impl(p, .RTS) // G major
}

// A colorfill bar at column x, height taken from a zero-page note value.
draw_bar :: proc(p: ^gt.Program, x, height_zp, color: u8) {
	gt.blit_begin(p, gt.DMA_COLORFILL | gt.DMA_OPAQUE)
	gt.emit_imm(p, .LDA, x);  gt.emit_abs(p, .STA, gt.BLIT_VX)
	gt.emit_imm(p, .LDA, 8);  gt.emit_abs(p, .STA, gt.BLIT_VY)
	gt.emit_imm(p, .LDA, 20); gt.emit_abs(p, .STA, gt.BLIT_WIDTH)
	gt.emit_zp(p, .LDA, height_zp); gt.emit_abs(p, .STA, gt.BLIT_HEIGHT)
	gt.emit_imm(p, .LDA, 0xFF - color); gt.emit_abs(p, .STA, gt.BLIT_COLOR)
	gt.blit_go(p)
	gt.blit_end(p)
}

assemble :: proc(p: ^gt.Program) {
	bg := gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1)
	c0 := gt.color(gt.HUE_BLUE, gt.SAT_FULL, 6)   // cyan
	c1 := gt.color(gt.HUE_YELLOW, gt.SAT_FULL, 4) // gold
	c2 := gt.color(gt.HUE_RED, gt.SAT_FULL, 5)    // rose

	gt.emit_impl(p, .SEI)
	gt.emit_impl(p, .CLD)
	gt.emit_imm(p, .LDX, 0xFF)
	gt.emit_impl(p, .TXS)
	gt.audio_init(p)

	gt.boot_double_buffered(p)
	gt.set_zp(p, CHORD, 0)
	gt.set_zp(p, FRAMES, 0)
	gt.clear_screen(p, bg); gt.flip(p)
	gt.clear_screen(p, bg); gt.flip(p)
	gt.emit_jsr(p, "select_chord") // start on C

	gt.mark(p, "loop")
	gt.emit_zp(p, .INC, FRAMES)
	gt.emit_zp(p, .LDA, FRAMES)
	gt.emit_imm(p, .CMP, STEP)
	no_adv := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BNE, no_adv)
	gt.set_zp(p, FRAMES, 0)
	gt.emit_zp(p, .INC, CHORD)
	gt.emit_zp(p, .LDA, CHORD)
	gt.emit_imm(p, .CMP, 3)
	in_rng := gt.anon_fwd(p)
	gt.emit_branch_id(p, .BNE, in_rng)
	gt.set_zp(p, CHORD, 0)
	gt.put_label(p, in_rng)
	gt.emit_jsr(p, "select_chord")
	gt.put_label(p, no_adv)

	gt.clear_screen(p, bg)
	draw_bar(p, 20, NOTE0, c0)
	draw_bar(p, 52, NOTE1, c1)
	draw_bar(p, 84, NOTE2, c2)
	gt.await_vsync(p)
	gt.flip(p)
	gt.emit_jump(p, "loop")

	emit_select_chord(p) // subroutine body (reached only via JSR)
	gt.vsync_nmi(p, "nmi")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "audio.gtr", nmi = "nmi"}, assemble)
}
