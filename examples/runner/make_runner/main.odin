// Regenerate examples/runner/runner.gtg.deflate — a parallax-runner sprite sheet.
//
//   odin run examples/runner/make_runner    # from the repo root
//
// Native replacement for make_runner.ps1. Layout (128x128 sprite RAM):
//   gy 0  : 4 player run frames, 16x16 (X = 0,16,32,48)
//   gy 16 : mountains strip  128x24  (far layer)
//   gy 40 : hills strip      128x24  (mid layer)
//   gy 64 : ground strip     128x24  (near layer)
// The three strips are 128px wide and seamless so they wrap invisibly.
package main

import "core:math"
import "core:os"
import gt "../../../tools/gtimg"

main :: proc() {
	out := "examples/runner/runner.gtg.deflate"
	if len(os.args) > 1 {
		out = os.args[1]
	}

	img := gt.new_sheet()
	defer delete(img)

	BODY  :: u8(0x7C); HEAD :: u8(0x07); LEG :: u8(0x01) // player
	MTN   :: u8(0xC2)                                    // mountains (blue-grey)
	HILL  :: u8(0x13)                                    // hills (green)
	GRASS :: u8(0x1C); DIRT :: u8(0x52); DOT :: u8(0x51) // ground

	// --- player: 4 run frames (legs together / apart) ---
	leg_frames := [4][2]int{{6, 9}, {4, 11}, {6, 9}, {4, 11}}
	for f in 0 ..< 4 {
		ox := f * 16
		for y in 1 ..= 5 {
			for x in 5 ..= 10 {
				dx := f64(x) - 7.5
				dy := f64(y) - 3
				if dx * dx + dy * dy <= 8 {
					gt.px(img, ox + x, y, HEAD)
				}
			}
		}
		for y in 6 ..= 11 {
			for x in 5 ..= 10 {
				gt.px(img, ox + x, y, BODY)
			}
		}
		for y in 7 ..= 9 { // arms
			gt.px(img, ox + 3, y, BODY)
			gt.px(img, ox + 4, y, BODY)
			gt.px(img, ox + 11, y, BODY)
			gt.px(img, ox + 12, y, BODY)
		}
		l := leg_frames[f]
		for y in 12 ..= 15 {
			gt.px(img, ox + l[0], y, LEG)
			gt.px(img, ox + l[0] + 1, y, LEG)
			gt.px(img, ox + l[1], y, LEG)
			gt.px(img, ox + l[1] + 1, y, LEG)
		}
	}

	// --- mountains strip (gy 16, 24 tall): triangular peaks, period 32 ---
	for x in 0 ..< 128 {
		dist := abs((x % 32) - 16) // 0 at peak, 16 at valley
		for y in dist ..< 24 {
			gt.px(img, x, 16 + y, MTN)
		}
	}

	// --- hills strip (gy 40, 24 tall): rounded humps, period 64 ---
	for x in 0 ..< 128 {
		hump := int(math.round(10 * math.sin(math.PI * f64(x % 64) / 64)))
		for y in 14 - hump ..< 24 {
			if y >= 0 {
				gt.px(img, x, 40 + y, HILL)
			}
		}
	}

	// --- ground strip (gy 64, 24 tall): grass top, dirt below, texture dots ---
	for x in 0 ..< 128 {
		for y in 0 ..< 24 {
			c := DIRT
			if y < 4 {
				c = GRASS
			}
			if y >= 6 && (x + y * 3) % 11 == 0 {
				c = DOT
			}
			gt.px(img, x, 64 + y, c)
		}
	}

	if !gt.write_gtg(out, img) {
		os.exit(1)
	}
}
