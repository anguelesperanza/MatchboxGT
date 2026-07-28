package main

// Runtime text: render strings from memory with draw_string. Unlike draw_text
// (which bakes a constant string into code at build time), draw_string reads a
// string from an address at run time — so the content can be data-driven or chosen
// while the game runs. Here two lines sit in a little dialogue box, the pattern
// RPGs / point-and-click adventures use.
//
//   odin run examples/text       # from the repo root; writes text.gtr
//
// The font comes from the shared sheet (examples/game), which has a 0-9 / A-Z grid
// at row 16; string_blob encodes strings against that same charset.

import gt "../../gametank"

FONT_GY :: u8(16)

setup :: proc(p: ^gt.Program) {
	gt.blob_file(p, "sprites", "examples/game/sprites.gtg.deflate")
	gt.inflate_asset(p, "sprites")
	gt.string_blob(p, "line1", "A SLIME BLOCKS")
	gt.string_blob(p, "line2", "THE PATH AHEAD")
}

frame :: proc(p: ^gt.Program) {
	// a dialogue box, then the two lines of runtime text on top of it
	gt.fill_rect(p, 2, 44, 124, 40, gt.color(gt.HUE_BLUE, gt.SAT_FULL, 2))
	gt.draw_string(p, 8, 54, gt.blob_addr(p, "line1"), FONT_GY)
	gt.draw_string(p, 8, 68, gt.blob_addr(p, "line2"), FONT_GY)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "text.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}
