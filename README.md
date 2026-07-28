# MatchboxGT — build GameTank ROMs in Odin

A build-time framework for making [GameTank](https://gametank.zone) console ROMs in
Odin, backed by `core:rexcode/isa/mos6502`. You write an Odin program that
*constructs* a ROM: it runs on your PC at build time, emits 65C02 machine code
(via rexcode) plus data, lays everything into a raw `.gtr` image, and writes it
to disk. **Your game logic is the emitted 6502 — Odin is the assembler host, not
the runtime.**

```
your main.odin  ──(odin run)──▶  emits 65C02 + data  ──▶  game.gtr  ──▶  emulator / flash cart
```

---

## Prerequisites

- **Odin** with the `rexcode` package available under its `core` collection.
  This repo was built against `odin version dev-2026-07`.
- The `core` collection must resolve to your Odin `core/` directory (rexcode
  lives at `core/rexcode/`). If Odin already ships `core` pointing there, you
  need no extra flags — otherwise pass
  `-collection:core=/path/to/Odin/core`.
- A GameTank emulator (or real hardware + flash cart) to load the `.gtr`.

Verify your toolchain:

```bash
odin version
```

---

## Quick start

Every program is an Odin `package main` that imports the framework and calls a
`build_*` driver from `main()`. Run it from the **repo root** so relative asset
paths and the output filename resolve correctly.

```bash
odin run examples/hello      # writes hello.gtr in the repo root
```

Then load the resulting `.gtr` in your emulator.

### The minimal ROM

```odin
package main

import gt "../../gametank"

main :: proc() {
    gt.build_rom(gt.Config{size = .K8, out = "game.gtr"}, assemble)
}

assemble :: proc(p: ^gt.Program) {
    gt.set_dma(p, gt.DMA_CPU_TO_VRAM)     // let the CPU write the framebuffer
    gt.clear_framebuffer(p, gt.BLACK)
    // ... emit your program ...
    gt.mark(p, "loop")
    gt.emit_jump(p, "loop")               // spin forever
}
```

`build_rom` drives everything: it runs `assemble` to build a `Program`, resolves
label and data-blob addresses (a hidden **two-pass** so tables placed after the
code get correct absolute addresses), fills the RESET/NMI/IRQ vectors, and
writes the raw image. On success it prints a build summary (code size, data
blobs and their addresses, and the vector table).

> **Note:** because of the two-pass layout, `assemble` must be **deterministic** —
> it is called twice and must emit the same instructions both times. This is the
> normal case for a code generator; just don't make emission depend on
> wall-clock time, RNG, etc.

---

## Two ways to author

### 1. Manual — `build_rom(cfg, assemble)`

You emit the whole program yourself: boot, main loop, handlers. Best when you
want full control (see `examples/hello`, `examples/bounce`, `examples/audio`,
`examples/banking`). A typical double-buffered game loop:

```odin
assemble :: proc(p: ^gt.Program) {
    gt.boot_double_buffered(p)              // blitter + vblank NMI + page-flip invariant
    gt.clear_screen(p, gt.BLACK); gt.flip(p)
    gt.clear_screen(p, gt.BLACK); gt.flip(p)

    gt.mark(p, "loop")
    gt.clear_screen(p, gt.BLACK)
    // ... update + draw ...
    gt.await_vsync(p)
    gt.flip(p)
    gt.emit_jump(p, "loop")

    gt.vsync_nmi(p, "nmi")                  // NMI handler, out of the main path
}

main :: proc() {
    gt.build_rom(gt.Config{size = .K8, out = "game.gtr", nmi = "nmi"}, assemble)
}
```

### 2. Scaffolded — `build_game(cfg, Game{...})`

The **runtime scaffold** writes all that boilerplate for you. You supply just a
`setup` proc (run once, before video comes up — load assets, init state) and a
`frame` proc (run every frame; the screen arrives already cleared to `bg`). The
scaffold does the reset, the two-buffer clear, the vblank-paced flip loop, and
the NMI. See `examples/runtime`.

```odin
package main
import gt "../../gametank"

setup :: proc(p: ^gt.Program) {
    gt.blob_file(p, "sprites", "examples/game/sprites.gtg.deflate")
    gt.inflate_asset(p, "sprites")
    gt.set_object(p, 0, 56, 56, 0, 0)       // player at (56,56), sprite (0,0)
}

frame :: proc(p: ^gt.Program) {
    gt.read_gamepad1(p, 0x10)
    gt.move_dec(p, 0x10, gt.PAD_LEFT,  gt.OBJ_X + 0, 0)
    gt.move_inc(p, 0x10, gt.PAD_RIGHT, gt.OBJ_X + 0, 112)
    gt.draw_objects(p, 1)
}

main :: proc() {
    gt.build_game(
        gt.Config{size = .K8, out = "runtime.gtr", inflate = true},
        gt.Game{bg = gt.color(gt.HUE_INDIGO, gt.SAT_MORE, 1), setup = setup, frame = frame},
    )
}
```

---

## `Config` reference

```odin
Config :: struct {
    size:    Rom_Size, // .K8 ($E000-$FFFF), .K32 ($8000-$FFFF), .Flash2M (2 MiB banked)
    out:     string,   // output path, e.g. "game.gtr"
    reset:   string,   // RESET vector label; "" = start of emitted code
    nmi:     string,   // NMI vector label;   "" = a default RTI handler
    irq:     string,   // IRQ vector label;   "" = the blit-completion handler (keep this default)
    inflate: bool,     // bundle the INFLATE decompressor at $E000 (needed for compressed assets)
    quiet:   bool,     // suppress the build summary
}
```

- **`.K8`** → 8 KiB image mapped to `$E000-$FFFF`. The common size; the only one
  that supports `inflate` (the decompressor is position-locked at `$E000`).
- **`.K32`** → 32 KiB mapped to `$8000-$FFFF`.
- **`.Flash2M`** → 2 MiB banked cart: code lives in the fixed region
  `$C000-$FFFF`; big data goes in banks 0–126 (mapped at `$8000` via `set_bank`).
- Leaving `irq` unset installs the **blit-completion handler**, which `blit_go`
  relies on. Only override `irq` if you re-implement that yourself.

---

## API reference

All procs take the builder `p: ^gt.Program` and *emit* 6502 — they do not run
anything. Constants are plain Odin constants used at build time.

### Program builder — `program.odin`
| Proc | Emits / does |
|---|---|
| `mark(p, name)` | define a named label here |
| `emit_jump(p, target)` / `emit_jsr(p, target)` | `JMP` / `JSR` to a named label |
| `emit_branch(p, mn, target)` | conditional branch (`.BEQ`, `.BNE`, …) to a named label |
| `anon(p) -> id` / `anon_fwd(p) -> id` / `put_label(p, id)` | anonymous labels for tight loops / forward "skip" branches |
| `emit_branch_id`, `emit_jump_id` | branch/jump to an anonymous label id |
| `emit_impl / emit_acc / emit_imm` | implied (`INX`), accumulator (`ROL A`), immediate (`LDA #v`) |
| `emit_abs / emit_abs_x / emit_abs_y` | absolute + indexed |
| `emit_zp / emit_zp_x / emit_ind_y / emit_ind_zp` | zero-page, `(zp),Y`, `(zp)` [65C02] |
| `set_zp(p, addr, val)` | `LDA #val / STA addr` (clobbers A) |
| `blob(p, name, data)` / `blob_file(p, name, path)` | attach a data blob (bytes / from a build-time file) |
| `bank_blob(p, name, bank, data)` | data blob in a flash bank (`.Flash2M`) |
| `blob_addr(p, name) -> u16` | absolute address of a blob (works across both passes) |

### Display & frame pacing — `display.odin`
`boot_double_buffered(p, extra_dma=0)`, `boot(p, dma, bank)`, `set_dma(p, flags)`,
`set_bank_flags(p, flags)`, `vsync_nmi(p, name)`, `await_vsync(p)`, `flip(p)`.

### Blitter — `blitter.odin`
`clear_screen(p, color)`, `fill_rect(p, x,y,w,h, color)`,
`draw_sprite(p, vx,vy, gx,gy, w,h)`, and the low-level
`blit_begin`/`blit_go`/`blit_end`/`blit_reset_counters` (use these when the
coordinates live in RAM). Max blit size is 127×127.

### Direct framebuffer — `video.odin`
`clear_framebuffer(p, color)` — CPU-written fill; simplest, slowest. Needs
`DMA_CPU_TO_VRAM`. For anything that moves, use the blitter.

### Input — `input.odin`
Buttons: `PAD_RIGHT, PAD_LEFT, PAD_DOWN, PAD_UP, PAD_B, PAD_C, PAD_A, PAD_START`.

- **Held (level):** `read_gamepad1(p, dest_zp)` / `read_gamepad2` fill a zero-page
  byte with `PAD_*` flags (`1 = down`). `if_pressed(p, state_zp, mask) -> skip_id`
  opens a guarded block, closed with `put_label`.
- **Held + edges:** `poll_gamepad1(p, held, pressed)` (Vars) reads the pad into
  `held` and also fills `pressed` with only the buttons that went down *this
  frame*. Then `if_held(p, held, mask)` for held buttons and `if_just_pressed(p,
  pressed, mask)` for taps (fires once per press) — both close with `put_label`.
  Init `held` to `0` in setup; pass the same two Vars every frame.

### Color — `color.odin`
Pixels are one byte `HHHSSBBB`. `color(hue, sat, bright)`, `gray(level)`,
`BLACK`, `WHITE`. Hues `HUE_GREEN/YELLOW/ORANGE/RED/MAGENTA/INDIGO/BLUE/CYAN`;
saturation `SAT_NONE/SOME/MORE/FULL`; brightness 0–7. **Hue names are rough** —
the emulator's DAC doesn't render them all as named; verify a swatch before
committing.

### Font, text & numbers — `font.odin`
`draw_text(p, x,y, text, font_gy)` emits one glyph blit per character of a
**build-time** string (`0-9`, `A-Z`; other chars leave a gap). For **runtime /
data-driven** text (dialogue tables, item names, messages chosen while the game
runs), `string_blob(p, name, text)` encodes a string into ROM and `draw_string(p,
x,y, addr, font_gy)` renders it from an address at run time (a real loop, so length
and content can vary) — point it at `blob_addr(p, name)` or any RAM you fill in the
same encoding. The charset is `0-9`, `A-Z`, `a-z`, and common punctuation — but a
sheet only renders the glyphs it actually contains: the original game sheet has
`0-9 / A-Z` at row 16, while `examples/text/font.gtg.deflate` (built by
`make_font.ps1`) is a full-charset sheet at row 0. `draw_number`/`draw_glyph` work
with either, since digits stay at indices 0–9. `draw_number(p, x,y, v,
font_gy, digits=3)` displays the decimal value of a **`Var`** (converted to digits
at runtime): use `digits = 1` for a 0–9 counter, `3` for a 0–255 value.
`draw_number16(p, x,y, v16, font_gy, digits=5)` does the same for a **`Var16`**
(0–65535), for real scores. `draw_glyph(p, x,y, value_zp,
strip_gx, strip_gy)` is the single-digit primitive. All read digit glyphs from the
font grid (row 0 = `'0'..'9'` at `font_gy`), which must be in sprite RAM.

### Assets / compression — `asset.odin`
`inflate_asset(p, name, dest=VRAM)` decompresses a `.gtg.deflate` blob into
sprite RAM; `inflate_raw(p, name, dest)` targets plain RAM (e.g. audio RAM).
Requires `Config.inflate = true`. Run **before** setting up double-buffering —
INFLATE owns the graphics bus. Workflow: produce a `.gtg.deflate` → `blob_file` it
→ build with `inflate = true` → `inflate_asset` it, then draw. The `.gtg.deflate`
format is a **raw DEFLATE** stream of a 128×128, 1-byte-per-pixel sprite-RAM image
(each byte a `HHHSSBBB` color; `0` = transparent). Any standard deflate encoder
works — `examples/anim/make_coin.ps1` generates one with .NET's `DeflateStream`.

### Banking — `bank.odin` (`.Flash2M` only)
`set_bank(p, page)` / `set_bank_var(p, page_zp)` select the 16 KiB bank (0–126)
mapped at `$8000`. Code always stays in the fixed region; only data is banked.

### Audio — `audio.odin` (4-voice square mixer on the ACP)
`audio_init(p)` once at startup (assembles a mixer with rexcode and copies it
into the audio coprocessor). Then per voice 0–3: `voice_note(p, voice, note, vol)`,
`voice_note_var`, `voice_off(p, voice)`. Shortcuts for voice 0: `audio_note(p, note)`,
`audio_note_var`. `audio_silence(p)` mutes all; `audio_stop(p)` pauses the ACP.
Notes are MIDI numbers (bundled MIDI→rate table); keep the volume sum ≤ 255.

### Runtime scaffold — `runtime.odin`
- `build_game(cfg, Game{bg, audio, setup, frame})` — the double-buffered game loop
  + NMI. Set `audio = true` to start the ACP mixer at boot (calls `audio_init`),
  so `setup`/`frame` can use the audio API directly.
- `move_dec` / `move_inc(p, input_zp, mask, addr, min/max)` — clamped movement of
  a RAM byte while a button is held.
- `sound_while(p, input_zp, mask, voice, note, vol)` — play `note` on `voice`
  while any bit of `mask` is held, silence it otherwise (a one-call movement/
  footstep tone). Requires `Game.audio = true`.
- **Object table:** up to 256 sprites in parallel RAM arrays
  (`OBJ_X/OBJ_Y/OBJ_GX/OBJ_GY` at `$0300–$06FF`, `OBJ_VX/OBJ_VY` at `$0700/$0800`).
  `set_object(p, i, x,y, gx,gy)` sets one; `draw_objects(p, count)` blits every
  visible one; `hide_object(p, i)` parks it off-screen (`Y >= OBJ_HIDDEN`), which
  also excludes it from movement and collision. Each object is a 16×16 sprite.
- **Collision:** `if_overlap(p, a, b, size=16) -> id` opens an "if objects `a` and
  `b` overlap" block (AABB on their boxes); emit the response, then close with
  `put_label(p, id)` — same idiom as `if_pressed`. Both indices are constants.
- **Animation:** `animate_object(p, i, timer, base_gx, frames, period)` cycles an
  object's source cell through a horizontal strip of 16px frames (from `base_gx`),
  one frame every `period` game-frames — arm the counter Var with `timer_set` in
  setup. `next_frame(p, i, base_gx, frames)` is the un-timed primitive (gate it
  with your own `every_n_frames`, e.g. to animate several objects off one timer).
- **Velocity:** `set_velocity(p, i, vx, vy)` sets a signed (`i8`) per-object
  velocity; `move_objects(p, count, max)` advances objects 0..count-1 by their
  velocity each frame and bounces them off the `[0, max]` walls (velocity negates
  in place at a wall). RAM isn't zeroed at power-on, so set every active object's
  velocity — `0` for stationary ones like a D-pad-driven player — before the first
  `move_objects`.

### Game state & control flow — `state.odin`
This is the layer that lets you write game *logic* without hand-writing 6502.

- **Variables:** `alloc_var(p) -> Var` hands you one byte of RAM (no more picking
  `$10`, `$11`… yourself — zero page first, then general RAM). `alloc_bytes(p, n)`
  reserves a raw block for arrays. Allocate in `setup`, keep the `Var` in an Odin
  variable. RAM isn't power-on-zeroed, so `set` a var before reading it.
- **Arithmetic** (all but `inc`/`dec` clobber A): `set(p, v, n)`, `copy_var(p, dst,
  src)`, `inc`/`dec(p, v)`, `add`/`sub(p, v, n)`, `add_var`/`sub_var(p, v, other)`.
- **16-bit** (0–65535, for scores past 255): `alloc_var16(p) -> Var16`, then
  `set16(p, v, n)`, `inc16(p, v)`, `add16(p, v, n)`. Display with `draw_number16`.
- **Conditionals** — same `put_label` idiom as `if_pressed`: `if_eq`/`if_ne`/`if_lt`/
  `if_ge(p, v, n)`, `if_zero`/`if_nonzero(p, v)`, each returns a skip id:

  ```odin
  skip := gt.if_ge(p, score, 100)
  gt.set(p, lives, ... )          // runs only when score >= 100
  gt.put_label(p, skip)
  ```

  `otherwise(p, skip) -> end` turns any of these into if/else (emit the else-body,
  then `put_label(p, end)`).
- Interop: a `Var`'s raw address is `v.addr`; for older helpers that take a bare
  zero-page byte (e.g. `read_gamepad1`), pass `u8(v.addr)`.
- Because you author in Odin, an ordinary build-time `for`/`if` still unrolls at
  zero runtime cost — reach for these helpers only when the *game* must branch on a
  value that isn't known until it runs.

### Menus — `menu.odin`
A menu is a `cursor` Var (the selected row) plus rows you draw yourself.
`menu_navigate(p, cursor, count, pressed)` moves it up/down with the D-pad (one
step per press, clamped) — feed it a `poll_gamepad` edge Var. `menu_cursor(p, x, y,
cursor, spacing, font_gy)` draws a ">" marker beside the selected row (same `y`/
`spacing` you laid the rows out with). `if_chosen(p, cursor, index, pressed, button)
-> id` opens a block that runs when the player confirms that option (close with
`put_label`) — one per option, the RPG command-menu / card-selection pattern. See
`examples/menu`.

### Tilemaps — `tilemap.odin`
`draw_tilemap(p, addr, cols, rows, x, y, tile_gy)` renders a `cols`×`rows` grid of
16×16 tiles from a byte map at `addr` (row-major tile indices — a ROM `blob` for a
fixed level, or `alloc_bytes` RAM you edit at run time). Tiles come from an 8-wide
tileset in sprite RAM at row `tile_gy` (tile *N* at `((N&7)*16, tile_gy+(N>>3)*16)`,
up to 64 types). It redraws the whole grid, so call it each frame after the clear;
a single screen is a few dozen blits. Limits: `cols*rows ≤ 256`, `x + cols*16 ≤
255` (a 128px screen holds 8 columns). See `examples/tilemap`.

For **scrolling**, `draw_tilemap_view(p, addr, map_cols, view_cols, view_rows,
cam_x, cam_y, x, y, tile_gy)` shows a `view_cols`×`view_rows` window onto a bigger
`map_cols`-wide map, with the tile at map cell `(cam_x, cam_y)` in the top-left.
`cam_x`/`cam_y` are **Vars in tile units** — this is tile-aligned scrolling (the
view moves a whole tile per step, ideal for grid games). Clamp them to
`[0, map_cols-view_cols]` / `[0, map_rows-view_rows]` yourself (e.g. `move_dec`/
`move_inc` gated with `every_n_frames`). See `examples/scroll`.

### Timing — `timer.odin`
`build_game` bumps a free-running frame counter each frame. `frame_var()` returns
it as a Var (test with `if_*`, or blink via `if_held(p, frame_var(), 0x10)`).
`tick(p, t)` is a **saturating** countdown (decrements a Var but stops at 0, unlike
`dec`) — the building block for cooldowns and one-shot timers; gate on it with
`if_zero`/`if_nonzero`. `every_n_frames(p, t, n) -> skip` runs a guarded block once
every `n` frames (init the counter Var `t` with `timer_set(p, t, n)` in setup).

### Random — `random.odin`
A single global generator (an 8-bit LFSR). `random_seed(p, nonzero)` once in setup,
then `random(p)` (new byte in A — call once per frame too, to keep it churning),
`random_var(p, dst)` (store to a Var), or `random_into(p, addr, mask)` (masked byte
straight to a RAM address — e.g. `random_into(p, OBJ_X + i, 0x70)` for a random
16px-aligned position).

---

## Memory & zero-page conventions

The framework reserves **zero-page `$00–$0F`** for its own machinery (vsync flag,
register mirrors, scratch pointer, blit-done flag) and `$F0–$FF` as INFLATE
scratch. The easiest way to stay clear of all this is to **let `alloc_var` hand
out addresses** rather than picking them by hand — it draws from `$10–$EF` (zero
page) then `$0200–$02FF` (general RAM). Bank_Flags (`$2005`) and DMA_Flags
(`$2007`) are write-only, so the framework keeps RAM mirrors and updates both
together — always go through `set_dma` / `set_bank_flags` / `flip` rather than
writing the registers directly. See `gametank/registers.odin` for the full map.

RAM map at a glance: `$00–$0F` framework, `$10–$EF` `alloc_var` zero-page pool,
`$0100–$01FF` stack, `$0200–$02FF` `alloc_bytes` / general RAM, `$0300–$08FF`
object table (X/Y/GX/GY/VX/VY), `$F0–$FF` INFLATE scratch. If you hand-pick
addresses, avoid the `alloc_*` pools so they don't collide.

---

## Making sprite sheets (`.gtg.deflate`)

Compressed sprites are **raw DEFLATE** streams of a raw sprite-RAM image: **128
bytes per row, one byte per pixel**, each byte a GameTank `HHHSSBBB` color (see
[Color](#color--colorodin)); **`0` is transparent** (the blitter skips it). A full
sheet is 128 rows = **16384 bytes**; the on-cart INFLATE routine decodes it into
sprite RAM at `$4000`. Sprites, glyphs, and animation frames are just 8×8 or 16×16
cells within that image (frame *N* of a 16px strip sits at sheet X = `N*16`).

**Two steps: build the raw bytes, then deflate them.**

1. **Author the image as raw color bytes.** Produce the 16384-byte array however
   suits you — draw shapes in code, or map an indexed image's palette to GameTank
   color bytes. Worked example: [`examples/anim/make_coin.ps1`](examples/anim/make_coin.ps1)
   draws a 4-frame spinning coin (ellipses in gold `0x3C`) and writes the asset.
2. **Deflate to `.gtg.deflate`.** Any standard DEFLATE encoder works — the format
   is plain RFC 1951 with no zlib header. The repo ships a helper:

   ```bash
   pwsh tools/deflate.ps1 my_sheet.bin examples/mygame/sheet.gtg.deflate
   ```

   (or inline in PowerShell: `System.IO.Compression.DeflateStream` at
   `CompressionLevel.Optimal` over your byte array.)

**Use it in a ROM:** `blob_file(p, "sheet", "path/sheet.gtg.deflate")` →
`inflate_asset(p, "sheet")` in `setup` (needs `Config.inflate = true`, and it must
run before double-buffering) → then draw with `draw_sprite` / the object table /
`draw_number` / `draw_string`. Colors are the emulator's DAC palette (approximate —
verify a swatch), and any deflate encoder's output is decoded on-cart, so **test a
new sheet in the emulator** once.

---

## Examples

Run each from the repo root with `odin run examples/<name>`; each writes a
`.gtr` of the same name.

| Example | Shows |
|---|---|
| `hello`   | direct-framebuffer text; the minimal boot |
| `bounce`  | double-buffered blitter animation + vsync loop |
| `move`    | gamepad-driven movement |
| `sprite`  | compressed sprite: `blob_file` + `inflate_asset` + `draw_sprite` |
| `game`    | a full little game on the runtime API — D-pad player, a coin you collect, a random respawn, a score (`draw_number`), and a jingle — in ~100 lines |
| `audio`   | the 4-voice ACP mixer (`audio_init` + `voice_note`) |
| `banking` | a `.Flash2M` banked cart with `set_bank` |
| `runtime` | the `build_game` scaffold: input movement, per-object velocity + wall bounce, collision pickups, a game-loop sound, and a state var driving a win condition |
| `anim`    | sprite animation — a 4-frame spinning coin on a timer (`animate_object`); sheet generated by `make_coin.ps1` |
| `text`    | runtime text — a dialogue box drawn from ROM with `draw_string`, using a full upper/lowercase + punctuation font (`make_font.ps1`) |
| `tilemap` | a walled room drawn from a byte map with `draw_tilemap`, plus a hero you walk around inside it (`make_tiles.ps1`) |
| `menu`    | a four-option menu with a ">" cursor, D-pad navigation, and A to confirm (`menu_navigate`/`menu_cursor`/`if_chosen`) |
| `scroll`  | a scrolling tilemap — an 8×6 window you scroll over a larger 12×10 map with the D-pad (`draw_tilemap_view`) |

---

## Package layout

```
gametank/
  registers.odin  hardware addresses, flag bits, framebuffer geometry, ZP map
  color.odin      HHHSSBBB color packing + named colors
  program.odin    the Program builder: labels, data blobs, emit_* helpers
  display.odin    boot, register mirrors, vsync, double-buffered page flipping
  bank.odin       flash-cart banking (set_bank; .Flash2M ROMs)
  blitter.odin    colorfill + sprite blits, clear_screen, counter reset
  input.odin      Genesis-pad reading + PAD_* masks + if_pressed
  font.odin       draw_glyph / draw_text from a glyph grid
  asset.odin      inflate_asset / inflate_raw (decompress blobs)
  audio.odin      4-voice square mixer (self-assembled ACP program)
  video.odin      direct-CPU framebuffer helpers (clear_framebuffer)
  runtime.odin    build_game scaffold, clamped movement, object table
  rom.odin        Config + build_rom + .gtr layout/output (+ INFLATE bundling)
  assets/         bundled INFLATE routine, ACP program, pitch table
examples/         one runnable package per feature (see table above)
```

`gametank/doc.odin` carries the same overview as an in-source package doc
comment.
