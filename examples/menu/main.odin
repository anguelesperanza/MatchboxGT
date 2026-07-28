package main

// Menu: a four-option list you move through with the D-pad; the ">" cursor marks
// the selection, and pressing A confirms an option. The confirmed index shows at
// the bottom. This is the RPG command-menu / card-selection pattern.
//
//   odin run examples/menu       # from the repo root; writes menu.gtr
//
// Uses the full-charset font (examples/text/font.gtg.deflate, from make_font.ps1).

import gt "../../gametank"

FONT_GY :: u8(0)
COUNT   :: u8(4)
TOP     :: u8(16) // y of the first option
STEP    :: u8(16) // rows are this far apart

held, pressed, cursor, chosen: gt.Var

setup :: proc(p: ^gt.Program) {
	gt.blob_file(p, "font", "examples/text/font.gtg.deflate")
	gt.inflate_asset(p, "font")
	gt.string_blob(p, "o0", "Fight")
	gt.string_blob(p, "o1", "Magic")
	gt.string_blob(p, "o2", "Item")
	gt.string_blob(p, "o3", "Run")
	gt.string_blob(p, "lbl", "Chosen:")
	held    = gt.alloc_var(p)
	pressed = gt.alloc_var(p)
	cursor  = gt.alloc_var(p)
	chosen  = gt.alloc_var(p)
	gt.set(p, held, 0)     // clean first frame for edge detection
	gt.set(p, cursor, 0)
	gt.set(p, chosen, 0)
}

frame :: proc(p: ^gt.Program) {
	gt.poll_gamepad1(p, held, pressed)
	gt.menu_navigate(p, cursor, COUNT, pressed) // D-pad up/down moves the cursor

	// confirm: each option records its index (a real menu would branch to its action)
	for i in u8(0) ..< COUNT {
		sel := gt.if_chosen(p, cursor, i, pressed, gt.PAD_A)
		gt.set(p, chosen, i)
		gt.put_label(p, sel)
	}

	// draw the option rows, the cursor, and the confirmed-index readout
	gt.draw_string(p, 24, TOP + 0 * STEP, gt.blob_addr(p, "o0"), FONT_GY)
	gt.draw_string(p, 24, TOP + 1 * STEP, gt.blob_addr(p, "o1"), FONT_GY)
	gt.draw_string(p, 24, TOP + 2 * STEP, gt.blob_addr(p, "o2"), FONT_GY)
	gt.draw_string(p, 24, TOP + 3 * STEP, gt.blob_addr(p, "o3"), FONT_GY)
	gt.menu_cursor(p, 12, TOP, cursor, STEP, FONT_GY)
	gt.draw_string(p, 8, 88, gt.blob_addr(p, "lbl"), FONT_GY)
	gt.draw_number(p, 72, 88, chosen, FONT_GY, digits = 1)
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "menu.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}
