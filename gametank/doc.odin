/*
Package gametank — a build-time framework for making GameTank ROMs in Odin,
backed by core:rexcode/isa/mos6502.

Authoring model: you write an Odin program that *constructs* a ROM. It runs on
your PC at build time and emits 65C02 machine code (via rexcode) plus data,
lays everything out into a raw .gtr image, and writes it to disk. Your game
logic is the emitted 6502 — Odin is the assembler host, not the runtime.

Minimal usage:

	import gt "../../gametank"

	main :: proc() {
		gt.build_rom(gt.Config{size = .K8, out = "game.gtr"}, assemble)
	}

	assemble :: proc(p: ^gt.Program) {
		gt.set_video_flags(p, gt.DMA_CPU_TO_VRAM)   // CPU writes framebuffer
		gt.clear_framebuffer(p, gt.BLACK)
		// ... emit your program ...
		gt.mark(p, "loop")
		gt.emit_jump(p, "loop")
	}

build_rom drives everything: it runs `assemble` to build a Program, resolves
label and data-blob addresses (a hidden two-pass so tables placed after the
code get correct absolute addresses), fills the RESET/NMI/IRQ vectors, and
writes the raw image.

File layout of this package:
  - registers.odin  hardware addresses, flag bits, framebuffer geometry, ZP map
  - color.odin      HHHSSBBB color packing + named colors
  - program.odin    the Program builder: labels, data blobs, emit_* helpers
  - display.odin    boot, register mirrors, vsync, double-buffered page flipping
  - bank.odin       flash-cart banking: set_bank (2 MiB carts, .Flash2M ROMs)
  - blitter.odin    colorfill + sprite blits, clear_screen, sprite-RAM counter reset
  - input.odin      Genesis-pad reading + PAD_* masks; if_pressed (held) and
                    poll_gamepad + if_held / if_just_pressed (edge-triggered)
  - font.odin       draw_text (build-time string) + draw_string / string_blob
                    (runtime, data-driven text) + draw_number / draw_number16 +
                    draw_glyph, from an 8x8 glyph grid
  - asset.odin      inflate_asset/inflate_raw: decompress blobs into sprite/RAM
  - audio.odin      4-voice square mixer (self-assembled ACP program): audio_init,
                    voice_note / voice_off / audio_note (voice 0) / audio_silence
  - video.odin      direct-CPU framebuffer helpers (clear_framebuffer)
  - runtime.odin    build_game scaffold (opt-in audio), clamped movement,
                    sound_while, object table (draw_objects), collision
                    (if_overlap), velocity + bounce (move_objects), sprite
                    animation (animate_object / next_frame)
  - state.odin      game-logic layer: RAM-var allocator (alloc_var/alloc_var16),
                    arithmetic (set/inc/add/... + 16-bit set16/inc16/add16), and
                    conditionals (if_eq/if_lt/... + otherwise)
  - random.odin     global LFSR RNG: random_seed / random / random_var / random_into
  - timer.odin      frame counter (frame_var) + countdown tick + every_n_frames
  - rom.odin        Config + build_rom + .gtr layout/output (+ INFLATE bundling)
  - assets/         bundled INFLATE routine + ACP program + pitch table (#loaded)

Compressed sprites: produce a .gtg.deflate with your deflate tool, embed it with
blob_file, build with Config.inflate = true, and inflate_asset it into sprite RAM
before drawing with draw_sprite. See examples/sprite.
*/
package gametank
