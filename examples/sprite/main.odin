package main

// Sprite asset demo: decompress a 128x128 image into sprite RAM with the bundled
// INFLATE routine, then blit it to the screen (double-buffered).
//
// The asset (gametank.gtg.deflate) was produced by the standalone deflate tool
// from gametank.bmp. Build from the repo root (or `odin run .` from this folder):
//
//   odin run examples/sprite       # writes sprite.gtr

import gt "../../gametank"

assemble :: proc(p: ^gt.Program) {
	bg := gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1)

	// Embed the compressed sprite (relative to the repo root at build time).
	gt.blob(p, "logo", #load("gametank.gtg.deflate"))

	// --- basic CPU init, then decompress the sprite into sprite RAM ----------
	gt.emit_impl(p, .SEI)
	gt.emit_impl(p, .CLD)
	gt.emit_imm(p, .LDX, 0xFF)
	gt.emit_impl(p, .TXS)
	gt.inflate_asset(p, "logo")          // -> sprite RAM page 0 at (0,0)

	// --- now bring up double-buffered video ---------------------------------
	gt.boot_double_buffered(p)
	gt.clear_screen(p, bg); gt.flip(p)
	gt.clear_screen(p, bg); gt.flip(p)

	// --- draw the sprite each frame -----------------------------------------
	gt.mark(p, "loop")
	gt.clear_screen(p, bg)
	gt.draw_sprite(p, 0, 0, 0, 0, 127, 127) // dst (0,0), src (0,0), 127x127
	gt.await_vsync(p)
	gt.flip(p)
	gt.emit_jump(p, "loop")

	gt.vsync_nmi(p, "nmi")
}

main :: proc() {
	gt.build_rom(gt.Config{size = .K8, out = "sprite.gtr", nmi = "nmi", inflate = true}, assemble)
}
