// png_to_sheet — convert an image into a GameTank sprite sheet (.gtg.deflate).
//
//   # exact: you supply an RGB -> GameTank-byte palette (recommended for real art)
//   odin run tools/png_to_sheet -- art.png sheet.gtg.deflate --palette pal.txt
//
//   # approximate: auto-map each pixel to the nearest GameTank color (prototyping)
//   odin run tools/png_to_sheet -- art.png sheet.gtg.deflate --quantize
//
// Native replacement for png_to_sheet.ps1. The image is copied pixel-for-pixel to
// the top-left of a 128x128 sprite-RAM sheet (rest transparent), so lay sprites/
// tiles/glyphs at the grid positions your code reads. Fully transparent pixels
// (alpha < 128) become GameTank color 0. Colors are GameTank HHHSSBBB bytes.
//
// Palette file (exact mode): one "RRGGBB HH" per line (hex RGB, hex byte); blank
// lines and # comments ignored. Map your transparent/background color to 00.
//
// Any format core:image can decode works (PNG, BMP, TGA, ...); this imports the
// PNG and BMP loaders. Add another core:image/<fmt> import to accept more.
package main

import "core:fmt"
import "core:image"
import "core:image/bmp"
import "core:image/png"
import "core:os"
import "core:strconv"
import "core:strings"
import gt "../gtimg"

_ :: bmp // ensure the BMP loader is linked (registers itself)
_ :: png

// --quantize maps each pixel to the nearest GameTank color using `dac_rgb` (the
// real DAC palette in dac_palette.odin), so the result matches on-screen colors.

main :: proc() {
	// --- parse args: <input> [output] (--quantize | --palette <file>) ---
	input, output, palette: string
	quantize := false
	positionals := 0
	i := 1
	for i < len(os.args) {
		a := os.args[i]
		switch {
		case a == "--quantize" || a == "-Quantize":
			quantize = true
		case a == "--palette" || a == "-Palette":
			i += 1
			if i < len(os.args) { palette = os.args[i] }
		case:
			switch positionals {
			case 0: input = a
			case 1: output = a
			}
			positionals += 1
		}
		i += 1
	}

	if input == "" {
		fmt.eprintln("usage: png_to_sheet <input.png> [output.gtg.deflate] (--palette <file> | --quantize)")
		os.exit(1)
	}
	if palette == "" && !quantize {
		fmt.eprintln("png_to_sheet: pick a mode: --palette <file> or --quantize")
		os.exit(1)
	}
	if output == "" {
		output = strings.concatenate({strip_ext(input), ".gtg.deflate"})
	}

	// --- load the image as RGBA8 ---
	data, rerr := os.read_entire_file(input, context.allocator)
	if rerr != nil {
		fmt.eprintfln("png_to_sheet: cannot read %s: %v", input, rerr)
		os.exit(1)
	}
	defer delete(data)

	img, ierr := image.load_from_bytes(data, image.Options{.alpha_add_if_missing})
	if ierr != nil {
		fmt.eprintfln("png_to_sheet: cannot decode %s: %v", input, ierr)
		os.exit(1)
	}
	defer image.destroy(img)
	if img.channels != 4 || img.depth != 8 {
		fmt.eprintfln("png_to_sheet: expected 8-bit RGBA after decode (got %d channels, %d-bit)", img.channels, img.depth)
		os.exit(1)
	}
	pix := img.pixels.buf[:]

	// --- build lookups ---
	pal_map: map[u32]u8 // exact mode: RGB -> byte
	defer delete(pal_map)
	if palette != "" {
		ptext, perr := os.read_entire_file(palette, context.allocator)
		if perr != nil {
			fmt.eprintfln("png_to_sheet: palette not found: %s", palette)
			os.exit(1)
		}
		defer delete(ptext)
		ptext_s := string(ptext)
		for line in strings.split_lines_iterator(&ptext_s) {
			t := strings.trim_space(line)
			if t == "" || strings.has_prefix(t, "#") { continue }
			fields := strings.fields(t)
			defer delete(fields)
			if len(fields) < 2 { continue }
			rgb, ok1 := strconv.parse_u64_of_base(fields[0], 16)
			b, ok2 := strconv.parse_u64_of_base(fields[1], 16)
			if ok1 && ok2 {
				pal_map[u32(rgb)] = u8(b)
			}
		}
	}

	// --- map pixels into the sheet ---
	out := gt.new_sheet()
	defer delete(out)
	sw := min(img.width, gt.W)
	sh := min(img.height, gt.H)
	unmatched := 0
	for y in 0 ..< sh {
		for x in 0 ..< sw {
			base := (y * img.width + x) * 4
			r := int(pix[base]); g := int(pix[base + 1]); bl := int(pix[base + 2]); a := int(pix[base + 3])
			if a < 128 { continue } // transparent -> byte 0
			if palette != "" {
				key := u32(r << 16 | g << 8 | bl)
				if v, found := pal_map[key]; found {
					gt.px(out, x, y, v)
				} else {
					unmatched += 1
				}
			} else {
				best := 0
				bd := max(int)
				for k in 1 ..< 256 {
					dr := r - int(dac_rgb[k][0]); dg := g - int(dac_rgb[k][1]); db := bl - int(dac_rgb[k][2])
					d := dr * dr + dg * dg + db * db
					if d < bd { bd = d; best = k }
				}
				gt.px(out, x, y, u8(best))
			}
		}
	}
	if unmatched > 0 {
		fmt.eprintfln("png_to_sheet: warning — %d pixel(s) had no palette entry (left transparent)", unmatched)
	}

	if !gt.write_gtg(output, out) {
		os.exit(1)
	}
	fmt.printfln("  (from %dx%d image)", sw, sh)
}

strip_ext :: proc(path: string) -> string {
	dot := strings.last_index(path, ".")
	slash := max(strings.last_index(path, "/"), strings.last_index(path, "\\"))
	if dot > slash {
		return path[:dot]
	}
	return path
}
