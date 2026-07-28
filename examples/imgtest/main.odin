package main

// Loads a sprite converted from a PNG by tools/png_to_sheet.ps1 and draws it —
// end-to-end proof that "draw art -> convert -> load" works.
//
//   pwsh tools/png_to_sheet.ps1 examples/imgtest/hero.png examples/imgtest/hero.gtg.deflate -Palette examples/imgtest/pal.txt
//   odin run examples/imgtest

import gt "../../gametank"

setup :: proc(p: ^gt.Program) {
	gt.blob_file(p, "hero", "examples/imgtest/hero.gtg.deflate")
	gt.inflate_asset(p, "hero")
	gt.set_object(p, 0, 56, 56, 0, 0) // the converted sprite sits at sheet (0,0)
}

frame :: proc(p: ^gt.Program) {
	gt.draw_objects(p, 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "imgtest.gtr", inflate = true},
		gt.Game{bg = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1), setup = setup, frame = frame},
	)
}
