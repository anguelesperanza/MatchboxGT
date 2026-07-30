package gametank

// =============================================================================
// GameTank hardware map
// =============================================================================
//
// Sources: the official wiki (hardware:memorymap, hardware:blitter) and the
// asm tutorial. Addresses are from the main 65C02's point of view.

// --- Memory-mapped I/O -------------------------------------------------------

ACP_RESET  :: u16(0x2000) // write: reset the audio coprocessor
ACP_NMI    :: u16(0x2001) // write: raise NMI on the audio coprocessor
BANK_FLAGS :: u16(0x2005) // RAM/sprite bank + blit clip control
AUDIO_RATE :: u16(0x2006) // bit7 = enable ACP; bits0-6 = IRQ frequency
DMA_FLAGS  :: u16(0x2007) // blitter/video control (see DMA_* bits below)
GAMEPAD1   :: u16(0x2008) // read: port 1 buttons (consecutive reads toggle select)
GAMEPAD2   :: u16(0x2009) // read: port 2 buttons
VIA_BASE   :: u16(0x2800) // 6522-style Versatile Interface Adapter ($2800-$280F)
VIA_ORA    :: u16(0x2801) // Output Register A (drives the flash bank shift register)
VIA_DDRA   :: u16(0x2803) // Data Direction Register A

// Flash-cart bank shift register, on VIA port A low 3 bits. Send the 7-bit bank
// number MSB-first: set DATA, pulse CLK (0->1) per bit, then pulse CS to latch.
BANK_CLK  :: u8(0x01)
BANK_DATA :: u8(0x02)
BANK_CS   :: u8(0x04)

AUDIO_RAM  :: u16(0x3000) // $3000-$3FFF audio RAM (from the main CPU's side)

// --- $2007 DMA / video flag bits ---------------------------------------------

DMA_ENABLE      :: u8(0x01) // enable the blitter
DMA_PAGE_OUT    :: u8(0x02) // which framebuffer page is shown on the TV
DMA_NMI         :: u8(0x04) // raise NMI at vblank
DMA_COLORFILL   :: u8(0x08) // draw solid color instead of copying sprite pixels
DMA_GCARRY      :: u8(0x10) // 0 = repeat 16x16 tiles, 1 = single tile
DMA_CPU_TO_VRAM :: u8(0x20) // 0 = CPU sees sprite RAM, 1 = CPU sees framebuffer
DMA_IRQ         :: u8(0x40) // raise IRQ when a blit finishes
DMA_OPAQUE      :: u8(0x80) // 1 = disable transparency (copy zero pixels too)

// --- $2005 bank flag fields --------------------------------------------------

BANK_SPRITE_PAGE :: u8(0x07) // sprite RAM page selection (mask)
BANK_FB_PAGE     :: u8(0x08) // framebuffer page the CPU accesses
BANK_CLIP_X      :: u8(0x10) // clip blits at the left/right edges
BANK_CLIP_Y      :: u8(0x20) // clip blits at the top/bottom edges
BANK_GPRAM       :: u8(0xC0) // general-purpose RAM bank selection (mask)

// --- Video RAM window + framebuffer geometry ---------------------------------
//
// The window at $4000-$7FFF maps to the framebuffer, sprite RAM, or the blitter
// registers depending on DMA_FLAGS/BANK_FLAGS. As a framebuffer it is 128x128,
// one byte per pixel, so pixel (x, y) lives at VRAM + y*FB_STRIDE + x.

VRAM         :: u16(0x4000)
VRAM_END     :: u16(0x7FFF)
FB_WIDTH     :: 128
FB_HEIGHT    :: 128
FB_STRIDE    :: 128
FB_VISIBLE_H :: 100 // a TV crops the top/bottom; ~100 rows are reliably visible

// --- Blitter registers (visible in the window in blitter-register mode) -------

BLIT_VX     :: u16(0x4000) // destination X in the framebuffer
BLIT_VY     :: u16(0x4001) // destination Y in the framebuffer
BLIT_GX     :: u16(0x4002) // source X in sprite RAM
BLIT_GY     :: u16(0x4003) // source Y in sprite RAM
BLIT_WIDTH  :: u16(0x4004) // width  (bit7 = horizontal flip)
BLIT_HEIGHT :: u16(0x4005) // height (bit7 = vertical flip)
BLIT_START  :: u16(0x4006) // write to trigger the copy
BLIT_COLOR  :: u16(0x4007) // color value for colorfill mode

// --- Cartridge / reset --------------------------------------------------------

VECTORS :: u16(0xFFFA) // NMI ($FFFA), RESET ($FFFC), IRQ ($FFFE)

// --- Asset decompression (INFLATE / zlib6502) ---------------------------------
//
// The bundled INFLATE routine is position-locked at $E000. Config.inflate places
// it there and starts your code just after it. Call it via inflate_asset.
// It reads a source pointer at $F0/$F1 and a destination pointer at $F2/$F3, and
// uses $F0-$FF as scratch — run it before you set up anything in low zero page.

INFLATE_ENTRY :: u16(0xE000) // JSR here to decompress
INFLATE_ZP    :: u8(0xF0)    // $F0/$F1 = src ptr, $F2/$F3 = dst ptr (but INFLATE
                             // uses ALL of zero page as scratch — see inflate_raw)

// --- Zero-page conventions used by this framework -----------------------------
//
// The emitted helpers reserve $00-$0F. Keep your own zero-page variables at $10
// and up. The layout mirrors the tutorials so the double-buffering machinery
// works: the two video registers are write-only, so we keep RAM mirrors of them.

GT_VSYNC :: u8(0x00) // frame flag: the vsync NMI handler increments this
GT_BANK  :: u8(0x01) // RAM mirror of Bank_Flags ($2005, write-only)
GT_DMA   :: u8(0x02) // RAM mirror of DMA_Flags  ($2007, write-only)
GT_PTR   :: u8(0x03) // $03/$04: 16-bit scratch pointer (clear_framebuffer, uploads)
GT_BLIT  :: u8(0x05) // blit-done flag, set by the blit-completion IRQ handler
GT_TMP   :: u8(0x06) // scratch (bank_switch)
GT_NUM_VAL :: u8(0x07) // number routines: working value ($07 lo, $08 hi for 16-bit)
GT_NUM_TMP :: u8(0x09) // draw_number16: tentative 16-bit subtraction low byte
GT_NUM_DIG :: u8(0x0A) // number routines: the current decimal digit (fed to draw_glyph)
GT_RNG     :: u8(0x0B) // random.odin: the global RNG state (an 8-bit LFSR)
GT_FRAME   :: u8(0x0C) // timer.odin: free-running frame counter (build_game bumps it)
GT_TEXT_PTR :: u8(0x0D) // draw_string: $0D/$0E = pointer to the current string
GT_TEXT_X   :: u8(0x0F) // draw_string: the running cursor X
