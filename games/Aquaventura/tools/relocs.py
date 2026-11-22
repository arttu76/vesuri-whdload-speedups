#!/usr/bin/env python3
"""Build src/relocs.i: how the Enhanced slave makes its copy of the game's code.

    python3 tools/relocs.py            write src/relocs.i and print the summary
    python3 tools/relocs.py --check    only check that src/relocs.i is up to date

The slave fills the ExpMem's copy area (chip COPY_LO-COPY_HI, at a constant offset) with
TRAP #15 and copies only the instructions tools/codemap.py reaches, and the read-only tables
they index PC-relative. The game's data stays in chip memory: there is one copy of every
variable. The copy's code is changed where it would otherwise read the copy's stale data or
leave the copy. Only addresses go into the file, no game bytes:

- _rel_ranges: the ranges that are copied (reached instructions and TABLES).
- _rel_code: 32-bit fields that get the copy's offset: the operand of every jsr/jmp abs.l to
  copied code, and the entries of PTR_TABLES that point to copied code.
- _rel_absw: d16(pc) data operands with a target below COPY_LO become abs.w, in place.
- _rel_stub: d16(pc) data operands with a target inside COPY_LO-COPY_HI. The instruction
  becomes `bra.w stub`; the stub (in an island: copy bytes that hold data in chip) does the
  instruction with the abs.l chip address and jumps back.
- _rel_out: bsr.w, bra.w, jsr d16(pc) and jmp d16(pc) to code below COPY_LO become
  jsr/jmp abs.w.
- _rel_chip: entries of CHIPONLY routines get `jmp chip`.

Code the map does not reach is not in the copy: a jump to it (a PC-indexed jump table, a
branch into a CHIPONLY routine) hits TRAP #15, whose handler continues at the same
instruction in chip memory. The script stops on what it cannot place.
"""
import os
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import codemap as C  # noqa: E402

COPY = (0x8000, 0x23000)
OUT = ROOT / 'src/relocs.i'
# Read-only tables that copied code reads with d8(pc,xn): address -> bytes. No dump of a
# running game differs from the loaded image in them (docs/development.md).
TABLES = {0xECE0: 76, 0x12F44: 128, 0x13468: 8, 0x13574: 8, 0x13994: 12, 0x1D2B0: 112,
          0x1EB52: 32, 0x1EB78: 24, 0x1F2A6: 24, 0x20924: 36, 0x20AFE: 128}
# Tables of code addresses among them: entries that point to copied code are relocated.
PTR_TABLES = {0x13994: 3, 0x1EB78: 6}
# Routines that run from chip memory only: (start, end, entries).
# $c4c8: reads the colour table $c4da with d8(pc,xn), and the game writes that table.
# $12e7c: the span fill, which writes its own instructions ($12f14-$12f36) per colour.
# $ec6c, $f4b8: the text plotters, which write their own instructions per colour ($ed40,
# $f4fa, $f512, through lea d16(pc)).
# $fa8e: the sprite draw, which writes the displacements of its own instructions
# ($fd86-$fdb6) before its loop.
CHIPONLY = [(0xC4C8, 0xC4DA, [0xC4C8]),
            (0xEC6C, 0xEDB0, [0xEC6C]), (0xF4B8, 0xF5DA, [0xF4B8, 0xF4E2, 0xF534]),
            (0xFA8E, 0xFDD2, [0xFA8E])]
# The span fill $12e7c writes its own instructions ($12f14-$12f36) per colour, through
# lea $12f14(pc),a2 at $12ec0. The slave replaces that part of the copy ($12ea0-$12ed7) with
# a jump to one of 32 prepared loops, one per colour (src/enhance.s _fillinit), so the lea
# is left alone, and the chip entry jumps to the copy (FORCE_TRAMP): only the copy's fill
# ever runs.
PCREL_KEEP = {0x12EC0}
FORCE_TRAMP = [0x12E7C]
SMC_SELF = []
# Slave patches applied to chip before the copy (jsr slave): copied as patched, not relocated.
PATCHED = [(0x84A6, 0x84AC), (0x84B4, 0x84BA), (0x1EA16, 0x1EA1C)]
# Islands for the stubs: copy bytes whose chip bytes are data that only absolute addresses
# reach: the unused end of the object table, the sort tree, the vertex buffer, two zeroed
# data areas and shape data.
ISLANDS = [(0x8000, 0x8370), (0x9B86, 0xA446), (0xA50A, 0xB9CA), (0x14000, 0x15000),
           (0x2007C, 0x207AC)]
REACH = 0x7F00
SAVESIZE = 0x3800                   # the saved state (src/state.i STATESIZE fits)
STACKSIZE = 0xF00
FILLLOOP = 0x12FC4 - 0x12ED8        # one span fill loop with its mask table


def incopy(a):
    return COPY[0] <= a < COPY[1]


def crc16(data):
    """resload_CRC16 (CRC-16/ARC: polynomial $8005 reflected, initial 0)."""
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build():
    code = C.explore()
    mem = code.mem
    # RELOCS_EXCL=lo-hi,lo-hi (hex): ranges left out of the copy, to bisect a fault
    excl = [tuple(int(x, 16) for x in p.split('-')) for p in os.environ.get('RELOCS_EXCL', '').split(',') if p]
    chiponly = lambda a: any(s <= a < e for s, e, _ in CHIPONLY) or any(s <= a < e for s, e in excl)
    patched = lambda a: any(s <= a < e for s, e in PATCHED)
    copied = {a for a in code.insn if incopy(a) and not chiponly(a)}
    # Instructions that hold a variable: an absolute or PC-relative data operand of reached
    # code points into them (the game writes $e7ec, the operand of movea.l #imm,a0 at $e7ea).
    # They are not copied, so they run from chip memory (TRAP #15, or jmp chip if 6 bytes fit).
    owner = {}
    for a in copied:
        for k in range(code.insn[a][0]):
            owner[a + k] = a
    holders, leas, rel_smc = set(), [], []
    for r in code.refs:
        if r.kind in ('abs', 'absw', 'pcrel', 'imm') and r.target in owner:
            if r.addr in PCREL_KEEP:
                continue
            if r.kind == 'imm' or r.mnem.split('.')[0] in ('lea', 'pea'):
                leas.append(r)
            elif r.addr in SMC_SELF:
                assert r.kind == 'abs' and r.addr in copied
                rel_smc.append(r.addr + r.off)
            else:
                holders.add(owner[r.target])
    assert len(rel_smc) == len(SMC_SELF)
    copied -= holders
    keep = bytearray(len(mem))
    for a in copied:
        keep[a:a + code.insn[a][0]] = b'\1' * code.insn[a][0]
    for t, n in TABLES.items():
        assert not any(keep[t:t + n]), f'table {t:x} overlaps code'
        keep[t:t + n] = b'\1' * n
    for s, e in ISLANDS:
        assert not any(keep[s:e]), f'island {s:x} holds code or a table'
    rel_code, rel_absw, rel_stub, rel_out, problems = list(rel_smc), [], [], [], []
    for r in code.refs:
        if r.addr not in copied:
            continue
        if patched(r.addr):
            continue
        t = r.target
        if r.kind == 'call':
            if t in copied:
                rel_code.append(r.addr + r.off)
        elif r.kind == 'branch':
            if incopy(t):
                continue            # stays in the copy (or hits TRAP in a CHIPONLY routine)
            op = struct.unpack_from('>H', mem, r.addr)[0]
            if op in (0x6100, 0x6000) and t < 0x8000:
                rel_out.append(r.addr)
            else:
                problems.append(f'branch out of the copy: {r}')
        elif r.kind == 'pccall':
            if not incopy(t):
                if t < 0x8000 and r.size == 4:
                    rel_out.append(r.addr)
                else:
                    problems.append(f'call out of the copy: {r}')
        elif r.kind == 'pcrel':
            op = struct.unpack_from('>H', mem, r.addr)[0]
            if op & 0x3F != 0x3A:
                problems.append(f'd16(pc) not in the source field: {r}')
            elif t < 0x8000:
                rel_absw.append((r.addr, r.off))
            elif r.addr in PCREL_KEEP:
                pass
            elif incopy(t):
                rel_stub.append((r.addr, r.size, r.off))
            else:
                problems.append(f'd16(pc) above the copy: {r}')
        elif r.kind == 'pcidx':
            if not any(tt <= t < tt + n for tt, n in TABLES.items()):
                problems.append(f'd8(pc,xn) read outside TABLES: {r}')
        elif r.kind == 'jtab':
            pass                    # targets not in the copy hit TRAP
    for t, n in PTR_TABLES.items():
        for k in range(n):
            v = struct.unpack_from('>I', mem, t + 4 * k)[0]
            if v in copied:
                rel_code.append(t + 4 * k)
    # the stubs' places: the nearest island with room
    free = [list(i) for i in ISLANDS]
    stubs = []
    for site, size, off in sorted(rel_stub):
        need = size + 2 + 6
        best = None
        for isl in free:
            if isl[1] - isl[0] < need:
                continue
            d = abs(isl[0] - (site + 2))
            if d < REACH and (best is None or d < best[0]):
                best = (d, isl)
        if best is None:
            problems.append(f'no island within reach of {site:x}')
            continue
        stubs.append((site, size, off, best[1][0]))
        best[1][0] += need
    # Trampolines: chip entries that are reached through pointers (tools/seeds.txt: handler
    # tables, jump tables) get `jmp copy`, where the first 6 bytes are whole copied
    # instructions that nothing else enters or reads.
    targets = {r.target for r in code.refs if r.kind in ('branch', 'call', 'pccall', 'callw')}
    targets |= set(C.seeds(mem))
    refd = {r.target + k for r in code.refs if r.kind in ('abs', 'absw', 'pcrel', 'pcidx') for k in range(4)}
    tramps = []
    for e in sorted(set(C.seeds(mem))):
        if e not in copied or patched(e):
            continue
        a, ok = e, True
        while a < e + 6:
            if a not in copied or (a != e and a in targets) or patched(a):
                ok = False
                break
            a += code.insn[a][0]
        if ok and not any(x in refd for x in range(e, e + 6)):
            tramps.append(e)
    tramps = sorted(set(tramps) | set(FORCE_TRAMP))
    rel_chip = [e for _, _, es in CHIPONLY for e in es]
    rel_chip += sorted(a for a in holders if code.insn[a][0] >= 6)
    # The slave's own areas go into copy bytes that hold nothing (the ExpMem is the copy's
    # size: a larger optional ExpMem stops WHDLoad on a 1 MB A500): the saved state, the
    # stack, and the span fill's 32 loops.
    used = bytearray(keep)
    for s, e in ISLANDS:
        top = max([st + sz + 8 for _, sz, _, st in stubs if s <= st < e] + [s])
        used[s:top] = b'\1' * (top - s)
    gaps, s = [], None
    for a in range(COPY[0], COPY[1] + 1):
        if a < COPY[1] and not used[a]:
            if s is None:
                s = a
        elif s is not None:
            lo, hi = (s + 3) & ~3, a & ~3
            if hi - lo >= 256:
                gaps.append([lo, hi])
            s = None

    def take(n):
        for g in sorted(gaps, key=lambda g: g[1] - g[0]):
            if g[1] - g[0] >= n:
                g[0] += n
                return g[0] - n
        raise SystemExit(f'no gap of {n} bytes in the copy')
    save = take(SAVESIZE)
    stack = take(STACKSIZE)
    fill, left = [], 32
    for g in sorted(gaps, key=lambda g: g[0] - g[1]):
        n = min(left, (g[1] - g[0]) // FILLLOOP)
        if n:
            fill.append((g[0], n))
            g[0] += n * FILLLOOP
            left -= n
    assert not left, 'no room for the span fill loops'
    ranges, s = [], None
    for a in range(COPY[0], COPY[1] + 1):
        if a < COPY[1] and keep[a]:
            if s is None:
                s = a
        elif s is not None:
            ranges.append((s, a - s))
            s = None
    assert all(not (st & 1) and not (n & 1) for st, n in ranges), 'odd range'
    return dict(code=code, ranges=ranges, rel_code=sorted(rel_code), rel_absw=sorted(rel_absw),
                stubs=stubs, rel_out=sorted(rel_out), rel_chip=rel_chip, problems=problems,
                holders=sorted(holders), leas=leas, tramps=tramps, save=save, stack=stack, fill=fill,
                crc=crc16(mem[COPY[0]:COPY[1]]))


def longs(vals, per=8):
    return ['\tdc.l\t' + ','.join(f'${v:x}' for v in vals[i:i + per]) for i in range(0, len(vals), per)]


def render(r):
    L = ['; Generated by tools/relocs.py from the loaded game (tmp/start.bin): chip addresses for',
         '; the code copy (src/enhance.s _mkcopy), no game bytes. Do not edit.',
         f'COPY_LO\t\t= ${COPY[0]:x}', f'COPY_HI\t\t= ${COPY[1]:x}',
         f'COPY_CRC\t= ${r["crc"]:04x}\t;resload_CRC16 of chip COPY_LO-COPY_HI at the game\'s entry',
         '; the slave\'s areas in unused parts of the copy, as chip addresses',
         f'COPY_SAVE\t= ${r["save"]:x}\t;the saved state', f'SAVESIZE\t= ${SAVESIZE:x}',
         f'COPY_STACK\t= ${r["stack"]:x}\t;the stack', f'STACKSIZE\t= ${STACKSIZE:x}',
         '', f'; {len(r["ranges"])} copied ranges ({sum(n for _, n in r["ranges"])} bytes): start, length',
         '_rel_ranges']
    for s, n in r['ranges']:
        L.append(f'\tdc.l\t${s:x}\n\tdc.w\t${n:x}')
    L += ['\tdc.l\t0', '', f'; {len(r["rel_code"])} code addresses (jsr/jmp abs.l, pointer tables)', '_rel_code']
    L += longs(r['rel_code']) + ['\tdc.l\t0', '', f'; {len(r["rel_absw"])} d16(pc) operands below the copy: instruction, offset of the displacement', '_rel_absw']
    for a, off in r['rel_absw']:
        L.append(f'\tdc.l\t${a:x}\n\tdc.w\t{off}')
    L += ['\tdc.l\t0', '', f'; {len(r["stubs"])} d16(pc) operands inside the copy: instruction, its length, offset of the', '; displacement, the stub', '_rel_stub']
    for site, size, off, stub in r['stubs']:
        L.append(f'\tdc.l\t${site:x}\n\tdc.w\t{size},{off}\n\tdc.l\t${stub:x}')
    L += ['\tdc.l\t0', '', f'; {len(r["rel_out"])} relative calls and jumps to code below the copy', '_rel_out']
    L += longs(r['rel_out']) + ['\tdc.l\t0', '', f'; {len(r["rel_chip"])} entries of routines that run from chip only', '_rel_chip']
    L += longs(r['rel_chip']) + ['\tdc.l\t0', '', f'; {len(r["tramps"])} chip entries reached through pointers: jmp copy', '_rel_tramp']
    L += longs(r['tramps']) + ['\tdc.l\t0', '', '; room for the span fill\'s 32 loops: address, loops', '_rel_fill']
    for a, n in r['fill']:
        L.append(f'\tdc.l\t${a:x}\n\tdc.w\t{n}')
    L += ['\tdc.l\t0', '']
    return '\n'.join(L)


def main(argv):
    r = build()
    for p in r['problems']:
        print('PROBLEM', p)
    text = render(r)
    if '--check' in argv:
        ok = OUT.exists() and OUT.read_text() == text
        print('src/relocs.i is up to date' if ok else 'src/relocs.i differs: run tools/relocs.py')
        return 0 if ok and not r['problems'] else 1
    if r['problems']:
        return 1
    print('instructions that hold a variable:', ' '.join(f'{a:x}' for a in r['holders']))
    print('lea/pea/immediate of copied code (a code pointer, or a write into code):',
          ' '.join(f'{x.addr:x}->{x.target:x}' for x in r['leas']))
    OUT.write_text(text)
    print(f'{len(r["ranges"])} ranges, {sum(n for _, n in r["ranges"])} bytes copied; '
          f'{len(r["rel_code"])} code, {len(r["rel_absw"])} abs.w, {len(r["stubs"])} stubs, '
          f'{len(r["rel_out"])} out, {len(r["rel_chip"])} chip-only, {len(r["tramps"])} trampolines; '
          f'CRC ${r["crc"]:04x}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
