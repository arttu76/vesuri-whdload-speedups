#!/usr/bin/env bash
# Check that a frame between two game steps leaves the game's memory as it was.
#   verify.sh [MINUTES] [SETUP]
# Boots BUILD=verify (default 9 minutes of wall time in warp, on the a3000-50) with
# CUSTOM2=20: a step every 20 fields, so every step has frames between. The build presses
# fire, turns the game's cheat on and presses L (next level) or T (tunnel) every 2048 fields.
# After every frame between it compares chip memory $1000-$7ffff with a copy made before the
# frame and logs each address that differs, except the screens, the stack, what the
# interrupts own and the draw's scratch (src/enhance.s _vexcl). Prints the state, the level,
# the states seen (bit = state/16), the counters and the logged addresses as ranges: add
# game state among them to src/state.i. $3a24 is the build's own T key.
set -uo pipefail
cd "$(dirname "$0")/.."
mins="${1:-9}" setup="${2:-a3000-50}"
srv() { python3 ../../common/tools/game_server.py "$@" 2>/dev/null; }
word() { srv gdb "$1" | tail -1 | awk '{print $2}'; }
make -s build BUILD=verify 2>&1 | grep -v 'amiga env' | grep -i -B3 error && exit 1
srv quit >/dev/null 2>&1
(make serve BUILD=verify NOBUILD=1 SETUP="$setup" WARP=1 WINDOW=none WB=0 \
  WHD_ARGS="CUSTOM1=1 CUSTOM2=20" > tmp/serve.log 2>&1 &)
for _ in $(seq 1 60); do srv wait 1 >/dev/null && break; sleep 1; done
for _ in $(seq 1 "$mins"); do srv wait 60 >/dev/null || { echo "the emulator stopped"; exit 1; }; done
echo "state $(word 'x/1xh 0x1090') level $(word 'x/1dh 0x3b40') seen $(word 'x/1xh 0xe0')" \
  "steps, between, fields: $(srv gdb 'x/3dw 0xc0' | tail -1 | cut -f2-)"
n="$(word 'x/1dw 0xcc')"; exp="$(word 'x/1xw 0xd0')"
echo "logged addresses: $n"
if [ "$n" -gt 0 ]; then
  srv gdb "x/${n}xw $exp+0x1b000" | awk '/^0x[0-9a-f]+:/ {for (i = 2; i <= NF; i++) print $i}' | python3 -c "
import sys
a = sorted(int(x, 16) for x in sys.stdin.read().split())
r = []
for x in a:
    if r and x - r[-1][1] <= 8: r[-1][1] = x + 2
    else: r.append([x, x + 2])
print(' '.join('%x-%x' % (s, e) for s, e in r))"
fi
srv quit >/dev/null
make -s stop >/dev/null 2>&1 || true   # the emulator of this game, pid-scoped
