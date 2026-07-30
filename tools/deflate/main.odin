// deflate — turn a raw sprite-RAM image into a .gtg.deflate the ROM can load.
//
//   odin run tools/deflate -- <input.bin> [output.gtg.deflate]
//
// Native replacement for deflate.ps1. Input is the raw bytes of a sprite-RAM image
// (128 bytes per row, one byte per pixel, each a GameTank HHHSSBBB color; 0 =
// transparent). A full sheet is 128 rows = 16384 bytes, but any length works —
// inflate_asset writes exactly as many bytes as the stream decodes to, from $4000.
// Output is raw DEFLATE (no zlib header), which the on-cart INFLATE routine decodes.
// If no output path is given, it writes <input>.gtg.deflate next to the input.
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import gt "../gtimg"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: deflate <input.bin> [output.gtg.deflate]")
		os.exit(1)
	}
	input := os.args[1]

	data, rerr := os.read_entire_file(input, context.allocator)
	if rerr != nil {
		fmt.eprintfln("deflate: cannot read %s: %v", input, rerr)
		os.exit(1)
	}
	defer delete(data)

	out: string
	if len(os.args) > 2 {
		out = os.args[2]
	} else {
		ext := filepath.ext(input) // ".bin" (or "" if none)
		out = fmt.tprintf("%s.gtg.deflate", input[:len(input) - len(ext)])
	}

	if !gt.write_gtg(out, data) {
		os.exit(1)
	}
}
