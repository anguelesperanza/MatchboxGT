package gametank

// =============================================================================
// GameTank color
// =============================================================================
//
// A pixel is one byte in the format HHHSSBBB:
//   bits 7-5  Hue        (which color of the rainbow)
//   bits 4-3  Saturation (0 = greyscale, 3 = most vivid)
//   bits 2-0  Brightness (0 = black .. 7 = white; ~4 is the most vibrant, higher
//                         values wash the color out toward white)
//
// IMPORTANT: values written straight into the framebuffer (direct CPU writes,
// clear_framebuffer) are used as-is — $00 is black, $07 is white. But the
// blitter's colorfill register ($4007) expects the *inverted* byte, so the
// fill_rect helper inverts for you. Pass normal color values everywhere.

// Combine a hue, saturation, and brightness into a color byte. `hue` and `sat`
// are the pre-shifted HUE_*/SAT_* constants below; `bright` is 0..7.
color :: #force_inline proc "contextless" (hue, sat, bright: u8) -> u8 {
	return hue | sat | (bright & 0x7)
}

// Greyscale ramp: level 0..7 (0 = black, 7 = white). Saturation is zero.
gray :: #force_inline proc "contextless" (level: u8) -> u8 {
	return level & 0x7
}

BLACK :: u8(0x00)
WHITE :: u8(0x07)

// Hue (bits 7-5). These are the SDK/tutorial's labels — but the emulator's DAC
// palette does NOT render them all as their names suggest (checked against the
// emulator): e.g. $C0 ("HUE_BLUE") shows as cyan, and $E0 ("HUE_CYAN") shows as
// green. Treat the names as rough and verify a color in the emulator before
// committing to it (a swatch of all 8 hues x a few brightnesses is the quick way).
HUE_GREEN   :: u8(0)
HUE_YELLOW  :: u8(32)
HUE_ORANGE  :: u8(64)
HUE_RED     :: u8(96)
HUE_MAGENTA :: u8(128)
HUE_INDIGO  :: u8(160)
HUE_BLUE    :: u8(192)
HUE_CYAN    :: u8(224)

// Saturation (bits 4-3).
SAT_NONE :: u8(0)
SAT_SOME :: u8(8)
SAT_MORE :: u8(16)
SAT_FULL :: u8(24)
