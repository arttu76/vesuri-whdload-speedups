# Development

Only what differs from the repository's `docs/running.md` and `docs/building.md`: the inputs
and how they are installed, game-specific tools, captures and traps.

## Inputs

`inputs.sha256` pins three files in `tmp/archives/`:

- `Aquaventura.lha`: the whdload.de install package v1.3, with the slave, its source and the
  RawDIC imager.
- `Aquaventura_Disk1.ipf` and `Aquaventura_Disk2.ipf`: images of the two original disks.

The slave reads the two files that the package's RawDIC imager makes, `disk.1` and `disk.2`.
`make unpack` runs `game_unpack` in `game.sh`. It builds `tmp/game/Aquaventura` from the
install package and decodes the IPFs with `tools/ipf2disk.py`, which follows the imager
(`Aquaventura.islave`). Tracks are numbered cylinder*2+head:

| Disk | Tracks | Format | Bytes per track |
|---|---|---|---|
| 1 | 0 | AmigaDOS | `$1600` |
| 1 | 1 | not read, zero-filled | `$1A00` |
| 1 | 2-`$8E`, `$90`-`$9E` | sync `$4429`, a long, a checksum long, `$1800` odd then `$1800` even bytes | `$1800` |
| 1 | `$8F` | not read, zero-filled | `$1800` |
| 2 | 0-1 | not read, zero-filled | `$1800` |
| 2 | 2-`$9E` | sync `$4489`, `$552AAAAA`, six sectors of a checksum word and 512 words | `$1800` |

Each image is 976896 bytes, and a track starts at track*`$1800`. All tracks decode with valid
checksums.

The tool uses the SPS capsimg library at `$AMIGA_SHARE/capsimg/capsimg.so` (set `CAPSIMG` to
use another one). AmigaXDev's setup does not install capsimg. Build it from FrodeSolheim's
`capsimg` repository (`./bootstrap`, `./configure` in `CAPSImg/`, `make`) and copy
`capsimg.so` to `$AMIGA_SHARE/capsimg/`. Its structures are packed (`#pragma pack(1)`), which
the tool follows.

## Running

`WB=0` boots without the Workbench 2.04 floppy, for a setup without `$WORKBENCH_ADF`. The
game does not need it.

## Build

The build without CUSTOM1 behaves as the shipped v1.3 slave. Two instructions are encoded
differently from the shipped binary: StingRay's assembler encoded the two `cmp.w #n,d1` in
`Disk2_Loader` as `CMP` (`$b27c`), and vasm encodes them as `CMPI` (`$0c41`). The two forms
do the same.

| `BUILD` | Defines | For |
|---|---|---|
| `release` | none | the slave that ships |
| `auto` | `AUTOFIRE` | scripted runs: the fire button pressed for 8 fields in every 128, the game's cheat on (infinite energy), counters at `$c0` |
| `skip` | `AUTOFIRE SKIPKEYS` | the same, and the key L (next level) or T (tunnel) every 2048 fields, also without CUSTOM1 |
| `verify` | `AUTOFIRE SKIPKEYS VERIFY` | the same, and the check of every frame between (`tools/verify.sh`). Its ExpMem is 640 KB. CUSTOM2 from 4 up is the step's length in fields |

The test builds' counters (longs): `$c0` steps, `$c4` frames between, `$c8` fields, `$cc`
VERIFY's logged addresses, `$d0` the ExpMem, `$d4` traps from the copy to chip code, `$d8`
the last trap's address, `$dc` the copy's offset; words: `$e0` states seen (bit =
state/16), `$e4` the pass that was swapped in (0 a step, k a frame between).

## Tools

- `tools/startdump.sh`: writes `tmp/start.bin`, chip memory at the game's entry `$3b58`
  with the release slave and no option. `tools/codemap.py` and `tools/relocs.py` read it.
- `tools/codemap.py`: the reached code (`summary`, `dis LO HI`). `seeds FILE...` adds
  entries that only pointers reach to `tools/seeds.txt`, from traced PCs (hex words in text
  files).
- `tools/relocs.py`: writes `src/relocs.i`. `--check` only compares.
  `RELOCS_EXCL=lo-hi,lo-hi` leaves ranges out of the copy, to find a routine that fails in
  the copy by bisection: the range whose exclusion repairs the picture holds it.
- `tools/rate.sh SETUP "WHD_ARGS" [EXTRA_ARGS]`: fields per step and frames per second.
- `tools/verify.sh [MINUTES] [SETUP]`: the check of the frames between.
- `tools/ipf2disk.py`: the IPF decoder for `make unpack`.
- A Furia-like machine: `SETUP=a500-020 EXTRA_ARGS=--uae_cpu_frequency=37500000`. Its fast
  memory is no faster than chip memory, so a real Furia is probably faster.

## The saved state

`src/state.i` lists what `_save` and `_restore` copy around a frame between. It is kept by
hand. To change it:

1. Run `tools/verify.sh`. It prints the addresses that a frame between left changed.
2. Decide what each one is. Game state goes into `src/state.i` (even start and length).
   Display data that must follow the frame shown (copper lists, sprites, screen pointers)
   and scratch that every pass makes again go into `_vexcl` in `src/enhance.s`, with the
   reason.
3. Run it again until it prints no address. `$3a24` is the test build's own T key.

The table started from two sources: every address that reached code names absolutely and
that is not an instruction, and every byte that differed between memory dumps made before
and after 150 passes of the main loop (`$3c4a` to `$3c5c`).

## The code copy

After a change that moves or adds a slave patch in chip `$8000`-`$22FFF`, add its bytes to
`PATCHED` in `tools/relocs.py` and run the tool. The copy is made after the patches, and the
tool must not relocate them.

Code that changes or reads its own instructions is the trap. A routine that does must run
from chip memory only (`CHIPONLY`) or from the copy only (`FORCE_TRAMP`), never from both,
because the two would share one variable that says what the code was last changed to. The
tool finds instructions whose operand reached code names (it reports them as "instructions
that hold a variable" and leaves them in chip memory), and it lists `lea`, `pea` and
immediates that point at copied code: read each of those, it is a code pointer or a write
into code. A write through a register that the tool does not list shows as a wrong
picture; find it with `RELOCS_EXCL`.

## Traps

- `make server CMD='...'` passes the command through the shell, so a gdb expression with
  parentheses fails. The tools call `common/tools/game_server.py` directly.
- The gdb stub ignores memory writes. Change the game through a test build.
- The game starts again from the loader after a game over, so `PatchMenu` and `_enhance`
  run more than once in a long run.
- `ws_ExpMem` must be whole 4 KB pages ("Slave is illegal"). An optional ExpMem of 136 KB
  stopped WHDLoad on the a500 setup ("not enough memory" on loading its overlay); 108 KB
  and 124 KB start.
- The profile of a 68030 setup records no instructions. Profile on a 68020 setup.
- FS-UAE watchpoints with a condition are too slow to reach a later level.
- A `Config=` tooltype in the game's icon replaces the slave's `ws_config`. An icon with
  `Config=BW` shows only ButtonWait in the splash window, whatever the slave declares.
  WHDLoad adds such a tooltype itself when a slave without `ws_config` reads ButtonWait.
  The emulator boots here pass the options on the command line and never read an icon.
