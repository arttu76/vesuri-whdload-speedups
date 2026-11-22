#!/usr/bin/env bash
# Game pace and frame rate of the test build in the game's first level.
#   rate.sh SETUP "WHD_ARGS" [EXTRA_ARGS] [SECONDS]
# Boots BUILD=auto (fire pressed by itself, the game's cheat on), waits for the state $60 and
# prints, for two spans of SECONDS (default 5, emulator time in warp): game steps, frames
# between, fields, fields per step and frames per second. The test builds keep the counters
# at $c0 (steps), $c4 (frames between) and $c8 (fields); without Enhanced framerate they stay 0.
set -uo pipefail
cd "$(dirname "$0")/.."
setup="$1" args="$2" extra="${3:-}" secs="${4:-5}"
srv() { python3 ../../common/tools/game_server.py "$@" 2>/dev/null; }
word() { srv gdb "$1" | tail -1 | awk '{print $2}'; }
make -s build BUILD=auto 2>&1 | grep -v 'amiga env' | grep -i -B3 error && exit 1
srv quit >/dev/null 2>&1
(make serve BUILD=auto NOBUILD=1 SETUP="$setup" WARP=1 WINDOW=none WB=0 WHD_ARGS="$args" \
  ${extra:+EXTRA_ARGS="$extra"} > tmp/serve.log 2>&1 &)
for _ in $(seq 1 60); do srv wait 1 >/dev/null && break; sleep 1; done
for _ in $(seq 1 40); do
  srv wait 5 >/dev/null || { echo "the emulator stopped"; exit 1; }
  [ "$(word 'x/1xh 0x1090')" = 0x0060 ] && break
done
srv wait 5 >/dev/null
for _ in 1 2; do
  a=($(srv gdb 'x/3dw 0xc0' | tail -1 | cut -f2-)); srv wait "$secs" >/dev/null
  b=($(srv gdb 'x/3dw 0xc0' | tail -1 | cut -f2-))
  python3 -c "
s, f, t = ${b[0]}-${a[0]}, ${b[1]}-${a[1]}, ${b[2]}-${a[2]}
print(f'steps {s} between {f} fields {t}: {t/max(s,1):.2f} fields/step, {(s+f)*50/max(t,1):.1f} frames/s')"
done
