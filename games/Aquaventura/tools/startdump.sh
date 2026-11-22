#!/usr/bin/env bash
# Write tmp/start.bin: chip memory as the game's entry $3b58 finds it, with the release
# slave and no option set (the image tools/codemap.py and tools/relocs.py read).
set -uo pipefail
cd "$(dirname "$0")/.."
srv() { python3 ../../common/tools/game_server.py "$@" 2>/dev/null; }
(make serve BUILD=release SETUP=a500 WARP=1 WINDOW=none WB=0 > tmp/serve.log 2>&1 &)
for _ in $(seq 1 60); do srv wait 1 >/dev/null && break; sleep 1; done
srv stop >/dev/null
srv until 0x3b58 >/dev/null
srv gdb dump binary memory "$PWD/tmp/start.bin" 0 0x80000 >/dev/null
srv quit >/dev/null
make -s stop >/dev/null 2>&1 || true   # the emulator of this game, pid-scoped
ls -l tmp/start.bin
