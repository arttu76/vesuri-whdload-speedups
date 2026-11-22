#!/usr/bin/env python3
"""The game's code, found statically: a recursive disassembly of the loaded program.

    python3 tools/codemap.py summary              reached code and what it references
    python3 tools/codemap.py dis LO HI            the reached instructions in [LO, HI)
    python3 tools/codemap.py seeds FILE...        add entries from traced PCs to tools/seeds.txt

The image is chip memory as the game's entry $3b58 finds it (tmp/start.bin, which
tools/startdump.sh writes). explore() follows control flow from the entry, the interrupt
handlers, the state table ($3c70: four routines per state) and tools/seeds.txt through
branches, bsr and jsr/jmp with absolute or PC-relative targets. Jumps through registers and
PC-indexed jump tables end a path: their targets are in tools/seeds.txt, which `seeds` fills
from traces (text files of hex PCs, one per word) with the lowest address of each run of
traced code that the static pass does not reach.

Used by tools/relocs.py, which builds the slave's relocation tables from it.
"""
import struct
import sys
from pathlib import Path

import capstone
from capstone import m68k as M

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / 'tmp/start.bin'
SEEDFILE = ROOT / 'tools/seeds.txt'
LO, HI = 0x1000, 0x24000            # the program: code and its data
ENTRY = 0x3B58
VECTORS = [0x3EB0, 0x3D6A]          # level 3 and level 2 handlers
STATES = (0x3C70, 0x3D60)           # the state table: longs

_md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_BIG_ENDIAN | capstone.CS_MODE_M68K_000)
_md.detail = True
STOP = {'rts', 'rte', 'rtr', 'jmp', 'bra', 'illegal', 'stop'}
SIZES = {'b': 1, 'w': 2, 'l': 4}


class Ref:
    """A reference in an instruction: kind is 'pcrel' (d16(pc) data), 'pcidx' (d8(pc,xn)
    data), 'jtab' (jmp/jsr d8(pc,xn)), 'abs' (absolute long operand), 'absw' (absolute
    short), 'imm' (a long immediate inside the program), 'branch' (relative), 'call' (jsr/jmp
    absolute long), 'callw' (jsr/jmp absolute short), 'pccall' (jsr/jmp d16(pc))."""

    def __init__(self, addr, size, kind, target, off, mnem, ops):
        self.addr, self.size, self.kind, self.target = addr, size, kind, target
        self.off, self.mnem, self.ops = off, mnem, ops

    def __repr__(self):
        return f'{self.addr:x} {self.mnem} {self.ops} [{self.kind} {self.target:x} +{self.off}]'


class Code:
    def __init__(self, mem):
        self.mem = mem
        self.insn = {}              # address -> (size, mnemonic, operands)
        self.refs = []
        self.indirect = []          # jsr/jmp through a register

    def long(self, a):
        return struct.unpack_from('>I', self.mem, a)[0]

    def word(self, a):
        return struct.unpack_from('>H', self.mem, a)[0]

    def bytes_map(self):
        m = bytearray(len(self.mem))
        for a, (s, _, _) in self.insn.items():
            m[a:a + s] = b'\1' * s
        return m

    def explore(self, seeds):
        work = list(seeds)
        while work:
            a = work.pop()
            while LO <= a < HI and not a & 1 and a not in self.insn:
                try:
                    i = next(_md.disasm(bytes(self.mem[a:a + 16]), a, 1))
                except StopIteration:
                    break
                self.insn[a] = (i.size, i.mnemonic, i.op_str)
                m = i.mnemonic.split('.')[0]
                jump = m in ('jmp', 'jsr')
                for o in i.operands:
                    am = o.address_mode
                    if am == M.M68K_AM_BRANCH_DISPLACEMENT:
                        t = (a + 2 + o.br_disp.disp) & 0xFFFFFF
                        self.refs.append(Ref(a, i.size, 'branch', t, 2, i.mnemonic, i.op_str))
                        work.append(t)
                    elif am in (M.M68K_AM_PCI_DISP, M.M68K_AM_PCI_INDEX_8_BIT_DISP):
                        idx = am == M.M68K_AM_PCI_INDEX_8_BIT_DISP
                        off = self._extoff(a, i.size, o.mem.disp, idx)
                        t = a + off + o.mem.disp
                        kind = ('jtab' if idx else 'pccall') if jump else ('pcidx' if idx else 'pcrel')
                        self.refs.append(Ref(a, i.size, kind, t, off, i.mnemonic, i.op_str))
                        if kind == 'pccall':
                            work.append(t)
                    elif am in (M.M68K_AM_ABSOLUTE_DATA_LONG, M.M68K_AM_ABSOLUTE_DATA_SHORT):
                        long = am == M.M68K_AM_ABSOLUTE_DATA_LONG
                        v = o.imm & (0xFFFFFFFF if long else 0xFFFF)
                        off = self._valoff(a, i.size, v, 4 if long else 2)
                        kind = ('call' if long else 'callw') if jump else ('abs' if long else 'absw')
                        self.refs.append(Ref(a, i.size, kind, v, off, i.mnemonic, i.op_str))
                        if jump:
                            work.append(v)
                    elif am == M.M68K_AM_IMMEDIATE and i.size >= 6:
                        v = o.imm & 0xFFFFFFFF
                        if LO <= v < HI:
                            off = self._valoff(a, i.size, v, 4)
                            if off:
                                self.refs.append(Ref(a, i.size, 'imm', v, off, i.mnemonic, i.op_str))
                    elif jump:
                        self.indirect.append((a, i.op_str))
                if m in STOP:
                    break
                a += i.size
        return self

    def _extoff(self, a, size, disp, idx):
        for off in range(2, size, 2):
            w = self.word(a + off)
            d = (w & 0xFF) if idx else w
            if idx and d & 0x80:
                d -= 0x100
            if not idx and d & 0x8000:
                d -= 0x10000
            if d == disp:
                return off
        raise ValueError(f'no extension word at {a:x}')

    def _valoff(self, a, size, v, n):
        for off in range(2, size - n + 2, 2):
            if (self.long(a + off) if n == 4 else self.word(a + off)) == v:
                return off
        return 0


def image():
    return bytearray(open(IMAGE, 'rb').read()) + bytearray(16)


def seeds(mem):
    s = [ENTRY] + VECTORS
    s += [struct.unpack_from('>I', mem, a)[0] for a in range(*STATES, 4)]
    if SEEDFILE.exists():
        s += [int(x, 16) for x in SEEDFILE.read_text().split() if not x.startswith('#')]
    return s


def explore():
    mem = image()
    return Code(mem).explore(seeds(mem))


def add_seeds(files):
    pcs = set()
    for f in files:
        pcs.update(int(x, 16) for x in Path(f).read_text().split())
    pcs = sorted(p for p in pcs if LO <= p < HI)
    old = [x for x in SEEDFILE.read_text().split()] if SEEDFILE.exists() else []
    new = []
    mem = image()
    code = Code(mem).explore(seeds(mem))
    for p in pcs:
        if p not in code.insn:
            new.append(p)
            code.explore([p])
    SEEDFILE.write_text('\n'.join(sorted(set(old) | {f'{p:x}' for p in new}, key=lambda x: int(x, 16))) + '\n')
    print(f'{len(new)} new seeds, {len(old) + len(new)} in {SEEDFILE.name}')


def main(argv):
    if argv[:1] == ['seeds']:
        return add_seeds(argv[1:])
    code = explore()
    if argv[:1] == ['dis']:
        lo, hi = int(argv[1], 16), int(argv[2], 16)
        for a in sorted(code.insn):
            if lo <= a < hi:
                s, m, o = code.insn[a]
                print(f'{a:6x}: {m} {o}')
        return
    kinds = {}
    for r in code.refs:
        kinds[r.kind] = kinds.get(r.kind, 0) + 1
    print(f'{len(code.insn)} instructions, {sum(code.bytes_map())} bytes; references: {kinds}')
    print('jump tables:', ' '.join(f'{r.addr:x}->{r.target:x}' for r in code.refs if r.kind == 'jtab'))
    print('indirect:', ' '.join(f'{a:x}{o}' for a, o in code.indirect))


if __name__ == '__main__':
    main(sys.argv[1:])
