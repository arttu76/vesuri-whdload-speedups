# Internals

Addresses are absolute chip addresses, as the slave's patches name them. The game's code is
not in a hunk file: the boot code loads it from raw disk tracks to fixed addresses.

## How it loads

The slave is a direct slave for two RawDIC disk images (`ws_Flags` NoError and EmulTrap, no
Kickstart), with a v17 header for `ws_config` (ButtonWait). `ws_BaseMemSize` is `$80000` and
there is no ExpMem.

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
5. `PatchMenu` fixes an access fault (`$23834`) and adds the quit key to the keyboard
   handler (`$3d7c`).

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
