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

The build is 4 bytes different from the shipped slave: StingRay's assembler encoded the two
`cmp.w #n,d1` in `Disk2_Loader` as `CMP` (`$b27c`), and vasm encodes them as `CMPI`
(`$0c41`). The two forms do the same. The only source edit is the commented-out `INCDIR`.
The rebuilt slave boots to the title on the a500 setup, as the shipped slave does.
