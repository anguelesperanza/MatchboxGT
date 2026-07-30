// Package gtimg — shared helpers for the native (Odin) asset generators that
// replace the old PowerShell make_*.ps1 / deflate / png_to_sheet scripts.
//
// A GameTank sprite sheet is a 128x128, 1-byte-per-pixel image (each byte a
// GameTank HHHSSBBB color; 0 = transparent). inflate_asset decompresses a raw
// DEFLATE stream of that image straight into sprite RAM at $4000. These helpers
// build the pixel buffer and emit the .gtg.deflate the ROM loads.
//
// Cross-platform: compression uses vendor:zlib (system libz on Linux, the bundled
// libz.lib on Windows) with raw DEFLATE (windowBits = -15) — the same stream the
// on-cart INFLATE routine decodes. No PowerShell / .NET dependency.
package gtimg

import "core:fmt"
import "core:os"
import zlib "vendor:zlib"

W    :: 128        // sheet width  (sprite-RAM page is 128x128)
H    :: 128        // sheet height
SIZE :: W * H      // 16384 bytes

// Allocate a fresh 128x128 sheet, all pixels transparent (0). Free with delete().
new_sheet :: proc() -> []u8 {
	return make([]u8, SIZE)
}

// Set one pixel (bounds-checked; out-of-range writes are ignored so drawing code
// can spill past an edge without crashing).
px :: proc(img: []u8, x, y: int, c: u8) {
	if x >= 0 && x < W && y >= 0 && y < H {
		img[y * W + x] = c
	}
}

// Fill a rectangle [x, x+w) x [y, y+h) with color c (bounds-checked).
rect :: proc(img: []u8, x, y, w, h: int, c: u8) {
	for yy in y ..< y + h {
		for xx in x ..< x + w {
			px(img, xx, yy, c)
		}
	}
}

// Compress `src` to a raw DEFLATE stream (no zlib header/trailer), the format the
// on-cart INFLATE routine expects. Returns freshly-allocated bytes; free with
// delete(). ok=false on a zlib error.
deflate_raw :: proc(src: []u8) -> (out: []u8, ok: bool) {
	stream := zlib.z_stream{}
	// windowBits = -15 -> raw DEFLATE; level 9 = best; memLevel 8, default strategy.
	if zlib.deflateInit2(&stream, zlib.BEST_COMPRESSION, zlib.DEFLATED, -15, 8, zlib.DEFAULT_STRATEGY) != zlib.OK {
		fmt.eprintln("gtimg: deflateInit2 failed")
		return nil, false
	}
	max_out := zlib.deflateBound(&stream, zlib.uLong(len(src)))
	buf := make([]u8, max_out)
	stream.next_in   = raw_data(src)
	stream.avail_in  = u32(len(src))
	stream.next_out  = raw_data(buf)
	stream.avail_out = u32(max_out)
	if zlib.deflate(&stream, zlib.FINISH) != zlib.STREAM_END {
		fmt.eprintln("gtimg: deflate did not finish")
		zlib.deflateEnd(&stream)
		delete(buf)
		return nil, false
	}
	n := int(stream.total_out)
	zlib.deflateEnd(&stream)
	return buf[:n], true
}

// Deflate `img` and write it to `path` as a .gtg.deflate. Prints a one-line
// summary. Returns false (and leaves no file) on any error.
write_gtg :: proc(path: string, img: []u8) -> bool {
	if len(img) > SIZE {
		fmt.eprintfln("gtimg: warning — image is %d bytes; a sprite-RAM page is %d (128x128). Extra bytes spill past the VRAM window.", len(img), SIZE)
	}
	comp, ok := deflate_raw(img)
	if !ok {
		return false
	}
	defer delete(comp)
	if err := os.write_entire_file(path, comp); err != nil {
		fmt.eprintfln("gtimg: cannot write %q: %v", path, err)
		return false
	}
	fmt.printfln("wrote %s (%d bytes, from %d)", path, len(comp), len(img))
	return true
}
