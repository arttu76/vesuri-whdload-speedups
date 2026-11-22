# Internals

Addresses are absolute chip addresses, as the slave's patches name them. The game's code is
not in a hunk file: the boot code loads it from raw disk tracks to fixed addresses.

## How it loads

The slave is a direct slave for two RawDIC disk images (`ws_Flags` NoError and EmulTrap, no
Kickstart), with a v17 header for `ws_config` (ButtonWait, CUSTOM1, CUSTOM2). `ws_BaseMemSize`
is `$80000`. `ws_ExpMem` asks for an optional `$1B000` (108 KB), which only Enhanced
framerate uses.

1. `Patch` loads `$1600` bytes from the start of disk 1 to `$5000`, redirects the boot
   code's track loader (`$5214`) to `Disk1_Loader`, and jumps to `$5026`. The loader's
   offsets and lengths are in tracks of `$1800` bytes.
2. The boot code calls `PatchPicture` (title picture at `$1000`: wait for a button with
   ButtonWait) and `PatchIntro` (intro at `$4000`), through the vectors that the slave puts
   at `$100` and `$106`.
3. `PatchIntro` removes the intro's disk access, sends its two track readers to
   `Intro_Loader` and its file loader to `Disk2_Loader`, adds the quit key, and makes the
   intro run `BootGame` when it ends.
4. `BootGame` patches the game loader at `$1000` (file loader, CACR access, protection) and
   hooks its decruncher exit (`DecrPatch`). When the decrunched program is the game
   (`$11be` holds `$207805c0`), `PatchGame` removes the protection check (`$260a0`) and the
   code checksums (`$1ed1e`, `$1ef68`, `$2079c`) and runs `PatchMenu` before `$3b58`.
5. `PatchMenu` fixes an access fault (`$23834`), adds the quit key to the keyboard
   handler (`$3d7c`), and calls `_enhance` (`src/enhance.s`) before the game's entry `$3b58`.
   The game starts again from the loader after a game over, so all of this runs again.

`Disk2_Loader` reads disk 2 by file name. Function 5 loads the directory (`$1000` bytes at
offset `$3000`): 16-byte entries with the name and, at offset 12, the length, then at
`$c00` a block map. A file starts at the first block (`$400` bytes) whose map byte is the
file's index.

## Slave patches

| Address | Patch | Why |
|---|---|---|
| `$5214` | `jmp Disk1_Loader` | boot loader reads from the disk image |
| `$50d4`, `$50b0` | call `$100`, `$106` | hooks for the intro and the title picture |
| `$ad02`, `$ad58`, `$ad28` | skip disk access, `jsr PicWait` | title picture |
| `$59bc`-`$5a5c`, `$5ac6`, `$5afe` | skip drive access | intro |
| `$5338`, `$534e` | `jmp Intro_Loader` | intro track reads |
| `$40f4`, `$42e8` | no disk swap wait, `jmp Disk2_Loader` | intro |
| `$5bd2` | `jsr` quit key check | intro keyboard |
| `$11de`, `$1de2`, `$1114`, `$1df6` | file loader, no CACR access, decruncher hook, protection | game loader |
| `$102c`, `$10aa` | skip disk access, run `PatchGame` | game loader |
| `$260a0`, `$1ed1e`, `$1ef68`, `$2079c` | protection check and code checksums off | game |
| `$4014`, `$4088` | skip disk access, run `PatchMenu` | game |
| `$23834` | `move.w 2(a6),(a5)+`-form snoop fix | game |
| `$4ef0`, `$3d7c` | quit key in the level 2 handler | game |
| `$3c14`, `$3c4a`, `$3ef0`, `$3edc`, `$5056`, `$84a6`, `$84b4`, `$1ea16`, `$3bba`, `$22672`, vector `$bc` | Enhanced framerate (below), only with the option on | game |

## The program

The loader decrunches the game to fixed addresses. `$1000`-`$23FFF` holds the code with its
variables and tables between the routines, and the rest of the 512 KB holds graphics, the two
screens and the disk buffers.

| Address | What |
|---|---|
| `$1090` | the state: `$60` is the 3D game, `$b0` the tunnel, `$70` and `$c0` sequences between them, `$e0` the options, `$20` the high scores. A negative value asks for a change |
| `$3c70` | the state table: four routines per state (A, B, exit, init) |
| `$1154`, `$1158` | the back and the front screen (40000 bytes each: 200 rows of 5 interleaved planes) |
| `$115e`, `$115c` | the fill colour, and the colour the span fill was last set for |
| `$1149`-`$114d` | joystick flags, written by the level 3 handler (`$3fc4`); `$114d` is the fire latch |
| `$39fc` | the key table, two bytes per key |
| `$3f04`-`$3f0a` | a 50-field counter, the frames of this second (`$3f06`) and of the last (`$3f08`) |
| `$5eb0` | 96 objects of 98 bytes: active (0), type (2), handler (4), lifetime (6), speed (8), position (32), four turn rates (48), a 3x3 matrix (56) |
| `$109c`, `$10a4` | the player's object and the camera's object |
| `$9b86` | the depth sort tree, made again in every pass |
| `$1368` → `$a50a` | the vertex buffer |
| `$22fe0` | the cheat (CTRL, F10 and fire at the options): infinite energy, L next level, T tunnel |
| `$23c5c`-`$23c93` | four sound effect requests, taken by the level 3 handler (`$239ea`) |

## Frames and time

The main loop is `$3c1a`-`$3c60`. One pass does this:

1. Leaves for another state if `$1090` is negative, and handles the pause key.
2. `$3e96`: the key table's per-pass step.
3. The state's routine A (`jsr` at `$3c50`). In the game (`$1db38`) it starts the blitter
   clear of the back screen (`$4c1c`) and does the cheat keys and the spawning.
4. The state's routine B (`jsr` at `$3c56`). In the game (`$1dc62`) it calls 23 routines that
   move the objects (`$8412`: handler, turn by the rates, move by the speed, collisions),
   transform and sort them, draw them (`$a4ba`), draw the horizon, the stars and the panel,
   and swap the screens (`$5056`).

The game has no clock: one pass is one step of the world and one frame. `$5056` waits for the
copper's interrupt request (set below the view) before it swaps, so a pass takes a whole
number of fields. Measured on the a500 setup with the level-skip test build, the game draws
7 to 10 frames a second in the 3D game (8.2 on average over the 8 levels) and 10 in the
tunnel and in the states `$70` and `$c0`.

The game runs from chip memory only, and the CPU does the 3D work and the polygon fills.
v1.3 draws 8 to 9 frames a second on a Furia-like setup (a500-020 at 37.5 MHz) and 13 to
17 on the a3000-50, because chip memory is no faster there. The game then also runs that
much faster than on an A500.

## Enhanced framerate (CUSTOM1)

`_enhance` turns the option on only when CUSTOM1 is set, the ExpMem was allocated, the CPU
is a 68020 or better, the CRC-16 of chip `$8000`-`$22FFF` at `PatchMenu` is the one
`src/relocs.i` was made for, and the instructions that the patches replace are the expected
ones. Otherwise the slave does nothing more than v1.3.

### The code copy

`_mkcopy` fills the ExpMem with `TRAP #15` and copies the code that `tools/codemap.py`
reaches from chip `$8000`-`$22FFF` to the same offsets (34 KB of code in 134 ranges). All
data stays in chip memory, so every variable exists once. `src/relocs.i`
(`tools/relocs.py`) lists what `_mkcopy` changes in the copy:

- `_rel_code`: `jsr`/`jmp abs.l` to copied code, and the entries of two pointer tables
  (`$13994`, `$1eb78`), get the copy's offset.
- `_rel_absw`: a `d16(pc)` data operand with a target below `$8000` becomes `abs.w`.
- `_rel_stub`: a `d16(pc)` data operand with a target inside `$8000`-`$22FFF` would read the
  copy's stale bytes. The instruction becomes `bra.w stub`. The stub does the instruction
  with the `abs.l` chip address and jumps back. The stubs are in islands: copy bytes whose
  chip bytes are data.
- `_rel_chip`: routines that must run from chip memory get `jmp chip` at their entries in
  the copy: the colour routine `$c4c8` (it reads the table `$c4da` with `d8(pc,xn)`, and the
  game writes that table), the text plotters `$ec6c` and `$f4b8` and the sprite draw `$fa8e`
  (they write their own instructions), and the instructions that hold a variable (`$e7ea`,
  whose operand `$e7ec` the game writes, and the three that the game's own checks read).
- `_rel_tramp`: 89 chip entries that the game reaches through pointers (the state table,
  handler tables) get `jmp copy`.
- Read-only tables that copied code reads with `d8(pc,xn)` are copied (`TABLES` in
  `tools/relocs.py`).

Code that is not in the copy is `TRAP #15` there. `_trapchip` (vector `$bc`) continues at the
same instruction in chip memory, so a jump that the code map does not know runs the
original code. The chip program stays complete apart from the trampolines.

The span fill (`$12e7c`) writes five instructions into its loop when the colour changes.
WHDLoad caches the ExpMem on a CPU with an MMU, where such a write needs a cache flush.
`_fillinit` (after `$5216` made the instruction table `$38bc`) makes 32 copies of the loop
`$12ed8`-`$12fc3`, one per colour, and the copy's `$12ea0` becomes a jump to the colour's
loop. The chip entry `$12e7c` jumps to the copy, so only that fill runs.

The stack is in the ExpMem: `PatchMenu` sets it, and the operand of the game's own
`lea $80000,sp` (`$22670`) is changed. The saved state, the stack and the 32 loops are in
parts of the copy that hold no code (`COPY_SAVE`, `COPY_STACK`, `_rel_fill`), so the ExpMem
is 108 KB. With 136 KB WHDLoad no longer started on the a500 setup (1 MB).

### Steps and frames between

`$3c4a` (`jsr $3e96`) jumps to `_frame`, which runs the pass itself. In the state `$60`:

- A step is the game's own pass (`$3e96`, A, B). `_swap` holds its swap until PERIOD
  fields after the last step's swap (6 by default, CUSTOM2). A step that is late is shown
  when it is done, and the next one counts from there: the game slows as v1.3 does on a
  slow machine.
- A frame between runs when it and the step after it still fit: the fields since the last
  step, plus the fields the last frame between took, plus the fields the last step took,
  are at most PERIOD. `_frame` saves the state (`src/state.i`, 12.9 KB) after the step,
  runs A and B with `_mode` = k, the fields from the last step to this frame's swap, and
  restores the state. The pass is the game's own, so everything is drawn. The turn rates
  (`$84a6`: `jsr $d1d6`), the speed (`$84b4`: `jsr $d4ea`) and the horizon's scroll
  (`$1ea16`) are scaled by k/PERIOD, so the objects, the camera and the horizon are where
  the step will have them after that part of its time. The step itself runs from the saved
  state: the game's logic never sees a frame between.
- `_swap` (`$5056`) does the swap's wait for the copper request itself and counts the
  fields per pass there, at the same beam position every time.

While a frame between runs:

- The keyboard interrupt is off (INTENA PORTS), because the key table is restored.
- The level 3 handler's sound effect call (`$3edc`) works on the requests of the last step:
  `_vblsnd` swaps `$23c5c`-`$23c93` with their saved copy around `$239ea`.
- The fire latch `$114d` is set back to its value before the frame, or cleared if the
  button was up at any field (`_vbl`), and `$3ff0` computes `$114c` again.

The states `$70`, `$b0` and `$c0` run the game's pass with its swap 5 fields after the last
one, the A500's rate there. Other states run as they come.

### Measurements

Emulator, `tools/rate.sh SETUP "CUSTOM1=1"`, the first level, hands off:

| Setup | v1.3 | 2.0b, Enhanced framerate |
|---|---|---|
| a500 (68000, 1 MB) | 7-10 frames/s | the same (the option stays off) |
| a500-020 at 37.5 MHz (Furia-like) | 8-9 frames/s, game too fast | 16.7 frames/s, 6.0 fields a step |
| a1200-030 | not measured | 25.0 frames/s, 6.0 fields a step |
| a3000-50 | 13-17 frames/s, game too fast | 25.0 frames/s, 6.0 fields a step |
| a1200-060 | not measured | 49 frames/s, 6.0 fields a step |

A pass takes a whole number of fields, so the rates are 50/3, 50/2 and 50. On the
Furia-like setup a pass is 2.3 fields of work: 1.5 in the copy, 0.4 in chip code, 0.2 in
the save and restore, 0.2 in interrupts. On the a1200-060 the camera moved 40 units in each
of 6 frames of a 240-unit step.

`tools/verify.sh` (9 minutes, levels 1 to 7, 1687 steps and 838 frames between) logs no
address that a frame between leaves changed, other than the test build's own key.

### Limitations

- Movement that a routine does by itself, not through the object loop's turn and move,
  is not scaled: it shows the next step's position in every frame between.
- The game takes random numbers from the beam position (`$5134`), so a frame between can
  decide differently from the step (an enemy shot that the step does not fire shows for
  one frame).
- Model data that the game animates is in the saved state only where the test runs saw it
  written. An animated part outside it would move once per frame.
- The text plotters, the sprite draw and the sound driver run from chip memory.
- The tunnel and the other states have no frames between.
