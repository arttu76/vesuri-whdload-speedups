"""Decode an Aquaventura IPF into the disk image that Bored Seal's RawDIC imager makes.

python3 -I ipf2disk.py CAPSIMG.so 1|2 IN.ipf OUT

The layout follows the imager (Aquaventura.islave). Tracks are numbered cylinder*2+head.
Disk 1: track 0 is AmigaDOS ($1600 bytes), track 1 is empty ($1A00 bytes), tracks 2-$8E and
$90-$9E are Psygnosis tracks (sync $4429, $1800 bytes), track $8F is empty ($1800 bytes).
Disk 2: tracks 0-1 are empty, tracks 2-$9E hold six 1024-byte sectors after sync $4489 and
the long $552AAAAA. A track that fails its checksum is zero-filled and reported.
"""
import ctypes as C
import sys

import numpy as np

lib = C.CDLL(sys.argv[1])
disk, src, out = int(sys.argv[2]), sys.argv[3].encode(), sys.argv[4]


class TrackT1(C.Structure):
    _pack_ = 1
    _fields_ = [("type", C.c_uint32), ("cylinder", C.c_uint32), ("head", C.c_uint32),
                ("sectorcnt", C.c_uint32), ("sectorsize", C.c_uint32),
                ("trackbuf", C.POINTER(C.c_ubyte)), ("tracklen", C.c_uint32),
                ("timelen", C.c_uint32), ("timebuf", C.POINTER(C.c_uint32)),
                ("overlap", C.c_int32)]


DI_LOCK_INDEX, DI_LOCK_DENVAR, DI_LOCK_UPDATEFD, DI_LOCK_TYPE = 1, 4, 1 << 8, 1 << 9
assert lib.CAPSInit() == 0
img = lib.CAPSAddImage()
assert img >= 0
assert lib.CAPSLockImage(img, C.c_char_p(src)) == 0, "CAPSLockImage failed"
lib.CAPSLoadImage(img, DI_LOCK_DENVAR)

M = 0x55555555


def track_bits(track):
    """The track's bits, twice over (a block may wrap), or None."""
    t = TrackT1(type=1)
    r = lib.CAPSLockTrack(C.byref(t), img, track // 2, track % 2,
                          DI_LOCK_INDEX | DI_LOCK_DENVAR | DI_LOCK_UPDATEFD | DI_LOCK_TYPE)
    if r != 0 or not t.tracklen:
        return None
    raw = np.ctypeslib.as_array(t.trackbuf, (t.tracklen,)).copy()
    lib.CAPSUnlockTrack(img, track // 2, track % 2)
    return np.unpackbits(np.concatenate([raw, raw]))


def syncs(bits, word, room):
    """Bit positions just after each occurrence of the 16-bit sync word."""
    pat = np.unpackbits(np.frombuffer(word.to_bytes(2, "big"), np.uint8))
    win = np.lib.stride_tricks.sliding_window_view(bits[:len(bits) - room], 16)
    return [int(p) + 16 for p in np.nonzero((win == pat).all(axis=1))[0]]


def words(bits, pos, n, kind):
    return np.frombuffer(np.packbits(bits[pos:pos + n * int(kind[2]) * 8]).tobytes(), kind)


def amigados(bits, track):
    """The 11 AmigaDOS sectors of a track, or None."""
    found = {}
    for p in syncs(bits, 0x4489, 9000):
        hdr = words(bits, p, 2, ">u4").astype(np.uint64)
        info = int(((hdr[0] & M) << 1) | (hdr[1] & M))
        if info >> 24 != 0xFF or (info >> 16) & 255 != track or (info >> 8) & 255 > 10:
            continue
        d = words(bits, p + 448, 256, ">u4").astype(np.uint64)
        s = words(bits, p + 384, 2, ">u4").astype(np.uint64)
        if int(np.bitwise_xor.reduce(d)) & M != int(((s[0] & M) << 1) | (s[1] & M)):
            continue
        found[(info >> 8) & 255] = (((d[:128] & M) << 1) | (d[128:] & M)).astype(">u4").tobytes()
    if len(found) != 11:
        return None
    return b"".join(found[s] for s in range(11))


def psygnosis(bits):
    """Disk 1: sync $4429 (once or twice), a long, the checksum, $1800 odd and $1800 even bytes."""
    for p in syncs(bits, 0x4429, 0x3020 * 8):
        v = words(bits, p, 4 + 0xC00, ">u4").astype(np.uint64)
        want = int(((v[2] & M) << 1) | (v[3] & M))
        d = v[4:]
        if int(np.bitwise_xor.reduce(d)) & M != want:
            continue
        return (((d[:0x600] & M) << 1) | (d[0x600:] & M)).astype(">u4").tobytes()
    return None


def sectors(bits):
    """Disk 2: sync $4489, $552AAAAA, then six sectors of a checksum word and 512 words."""
    for p in syncs(bits, 0x4489, (4 + 6 * 2052) * 8):
        if int(words(bits, p, 1, ">u4")[0]) != 0x552AAAAA:
            continue
        v = words(bits, p + 32, 6 * 1026, ">u2").astype(np.uint32)
        w = (((v[0::2] << 1) & 0xAAAA) | (v[1::2] & 0x5555)).reshape(6, 513)
        if all(int(r[1:].sum()) & 0xFFFF == int(r[0]) for r in w):
            return w[:, 1:].astype(">u2").tobytes()
    return None


image = bytearray()
bad = []
for track in range(0x9F):
    size = 0x1800
    data = None
    empty = track == 0x8F if disk == 1 else track < 2
    if disk == 1 and track == 0:
        size = 0x1600
    if disk == 1 and track == 1:
        size, empty = 0x1A00, True
    if not empty:
        bits = track_bits(track)
        if bits is not None:
            if disk == 2:
                data = sectors(bits)
            elif track == 0:
                data = amigados(bits, track)
            else:
                data = psygnosis(bits)
        if data is None:
            bad.append(track)
    image += data if data else bytes(size)

open(out, "wb").write(image)
print(f"disk {disk}: {len(image)} bytes; tracks that failed: {bad}")
