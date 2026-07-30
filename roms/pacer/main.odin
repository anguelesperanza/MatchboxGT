package main

import gt "../../rexcode-testing/gametank"


/*
	This is a fun little test to try out the text stuff
	of MatchboxGT

	
	Things to add:
	1. Automatic word wrapping
	2. Reading in text files that create the correct blob automatically

	Things to Note
	1. Text gets cut off around 7 lines --> this is due to overscan cutoff at approx y = ~100
*/


FONT_GY :: cast(u8)0

section:gt.Var // Used to count what set of lines to display
pressed:gt.Var
held:gt.Var

setup :: proc(p: ^gt.Program) {

	// Load/decompress assets FIRST: inflate_asset uses ALL of zero page as
	// scratch, so anything you set() before it gets wiped. Initialize game
	// variables (section/pressed/held) only after this.
	gt.blob_file(p, "font", "./font.gtg.deflate" )
	gt.inflate_asset(p, "font")
	gt.string_blob(p, "line1", "The FitnessGram")
	gt.string_blob(p, "line2", "Pacer Test is a")
	gt.string_blob(p, "line3", "multistage")
	gt.string_blob(p, "line4", "aerobic")
	gt.string_blob(p, "line5", "capacity test")
	gt.string_blob(p, "line6", "that")
	gt.string_blob(p, "line7", "progressively")
	gt.string_blob(p, "line8", "gets more")
	gt.string_blob(p, "line9", "difficult as it")
	gt.string_blob(p, "line10", "continues. The")
	gt.string_blob(p, "line11", "20 meter pacer")
	gt.string_blob(p, "line12", "test will begin")
	gt.string_blob(p, "line13", "in 30 seconds.")
	gt.string_blob(p, "line14", "Line up at the")
	gt.string_blob(p, "line15", "start. The")
	gt.string_blob(p, "line16", "running speed")
	gt.string_blob(p, "line17", "starts slowly")
	gt.string_blob(p, "line18", "but gets faster")
	gt.string_blob(p, "line19", "each minute")
	gt.string_blob(p, "line20", "after you hear")
	gt.string_blob(p, "line21", "this signal")
	gt.string_blob(p, "line22", "bodeboop. A")
	gt.string_blob(p, "line23", "sing lap should")
	gt.string_blob(p, "line24", "be completed")
	gt.string_blob(p, "line25", "every time you")
	gt.string_blob(p, "line26", "hear this")
	gt.string_blob(p, "line27", "sound. ding")
	gt.string_blob(p, "line28", "Remember to run")
	gt.string_blob(p, "line29", "in a straight")
	gt.string_blob(p, "line30", "line and run as")
	gt.string_blob(p, "line31", "long as")
	gt.string_blob(p, "line32", "possible. The")
	gt.string_blob(p, "line33", "second time you")
	gt.string_blob(p, "line34", "fail to")
	gt.string_blob(p, "line35", "complete a lap")
	gt.string_blob(p, "line36", "before the")
	gt.string_blob(p, "line37", "sound, your")
	gt.string_blob(p, "line38", "test is over.")
	gt.string_blob(p, "line39", "The test will")
	gt.string_blob(p, "line40", "begin on the")
	gt.string_blob(p, "line41", "word start. On")
	gt.string_blob(p, "line42", "your mark. Get")
	gt.string_blob(p, "line43", "ready!… Start.")
	gt.string_blob(p, "line44", "ding")

	// Game state — set up AFTER the asset decompression above.
	section = gt.alloc_var(p)
	pressed = gt.alloc_var(p)
	held    = gt.alloc_var(p)
	gt.set(p, section, 0)
}

frame :: proc(p: ^gt.Program) {
	gt.poll_gamepad1(p, held, pressed)

	// Increment the section counter by 1
	tap := gt.if_just_pressed(p, pressed, gt.PAD_A)
	gt.inc(p, section)
	gt.put_label(p, tap)

	// If the section counter is 8 (7 sections to display the text)
	// set to 0 to start over
	start := gt.if_eq(p, section, 8)
	gt.set(p, section, 0)
	gt.put_label(p, start)

	section_0 := gt.if_eq(p, section, 0)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line1"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line2"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line3"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line4"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line5"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line6"), FONT_GY)
	gt.put_label(p, section_0)

	section_1 := gt.if_eq(p, section, 1)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line7"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line8"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line9"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line10"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line11"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line12"), FONT_GY)
	gt.put_label(p, section_1)
	
	section_2 := gt.if_eq(p, section, 2)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line13"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line14"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line15"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line16"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line17"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line18"), FONT_GY)
	gt.put_label(p, section_2)

	section_3 := gt.if_eq(p, section, 3)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line19"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line20"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line21"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line22"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line23"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line24"), FONT_GY)
	gt.put_label(p, section_3)

	section_4 := gt.if_eq(p, section, 4)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line25"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line26"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line27"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line28"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line29"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line30"), FONT_GY)
	gt.put_label(p, section_4)
	
	section_5 := gt.if_eq(p, section, 5)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line31"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line32"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line33"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line34"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line35"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line36"), FONT_GY)
	gt.put_label(p, section_5)
	
	section_6 := gt.if_eq(p, section, 6)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line37"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line38"), FONT_GY)
	gt.draw_string(p, 2, 32, gt.blob_addr(p, "line39"), FONT_GY)
	gt.draw_string(p, 2, 46, gt.blob_addr(p, "line40"), FONT_GY)
	gt.draw_string(p, 2, 60, gt.blob_addr(p, "line41"), FONT_GY)
	gt.draw_string(p, 2, 74, gt.blob_addr(p, "line42"), FONT_GY)
	gt.put_label(p, section_6)
	
	section_7 := gt.if_eq(p, section, 7)
	gt.draw_string(p, 2, 4,  gt.blob_addr(p, "line43"), FONT_GY)
	gt.draw_string(p, 2, 18, gt.blob_addr(p, "line44"), FONT_GY)
	gt.put_label(p, section_7)
	
}

main :: proc() {
	gt.build_game(
		gt.Config{size = .K8, out = "pacer.gtr", inflate = true},
		gt.Game{
			bg    = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1),
			setup = setup,
			frame = frame,
		},
	)
}

