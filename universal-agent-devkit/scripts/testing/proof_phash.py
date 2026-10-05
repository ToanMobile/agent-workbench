#!/usr/bin/env python3
"""64-bit difference hash for proof screenshots.

Similarity is 1 - hamming/64. Two images are the same screen when similarity
>= 0.98 (at most one bit differs). PNG is decoded with zlib. JPEG needs Pillow;
without it the caller keeps the SHA-256 check only.

Speed (DevKit speed 0a): the PNG scanlines are un-filtered by Pillow when it is installed (15 ms instead of
0.7 s per screenshot); the pure-Python decoder below stays the reference and the fallback, and the answer is
the same bit for bit. HashCache remembers the hash of an image by the sha256 of its bytes.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import struct
import tempfile
import zlib

SIMILAR = 0.98
# Bump when a hash changes meaning (sample points, luma formula, bit order): every cached value is then ignored.
ALGO_VERSION = 1
CACHE_MAX = 5000                  # entries kept; the oldest go first
_CACHE_MAX_BYTES = 8 * 1024 * 1024  # a bigger file is not ours: treated as corrupt
_PNG_SIG = b"\x89PNG\r\n\x1a\n"
_BPP = {0: 1, 2: 3, 6: 4}
_MODE = {0: "L", 2: "RGB", 6: "RGBA"}
_HEX = frozenset("0123456789abcdef")


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw: bytes, height: int, stride: int, bpp: int) -> bytes | None:
    rows = []
    i = 0
    prev = bytearray(stride)
    for _ in range(height):
        if i >= len(raw):
            return None
        f = raw[i]
        i += 1
        row = bytearray(raw[i:i + stride])
        i += stride
        if len(row) < stride:
            return None
        if f == 1:
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 255
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif f == 4:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up_left = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + _paeth(left, prev[x], up_left)) & 255
        elif f != 0:
            return None
        rows.append(row)
        prev = row
    return b"".join(rows)


def _png_header(data: bytes):
    """(width, height, color, [IDAT chunks]) of an 8-bit, non-interlaced gray/RGB/RGBA PNG; None for anything else."""
    if len(data) < 8 or data[:8] != _PNG_SIG:
        return None
    pos = 8
    width = height = None
    bit = color = interlace = None
    idat = []
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        pos += 8
        chunk = data[pos:pos + length]
        pos += length + 4
        if kind == b"IHDR" and len(chunk) >= 13:
            width, height, bit, color, _comp, _filt, interlace = struct.unpack(">IIBBBBB", chunk[:13])
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
    if not width or not height or bit != 8 or interlace != 0 or color not in (0, 2, 6):
        return None
    return width, height, color, idat


def _png_luma_pillow(width: int, height: int, color: int, idat: list):
    """The same (width, height, luma) as the pure path, with Pillow un-filtering the scanlines in C.
    None means "use the pure path": Pillow is missing or raises, or the stream is one the pure path may reject.
    Pillow never decides accept or reject: the pure path's own conditions are tested here first (zlib stream
    intact, enough rows, every filter byte 0-4); Pillow only supplies the pixel values of a stream that passed."""
    try:
        from PIL import Image
    except ImportError:
        return None
    stride = width * _BPP[color]
    joined = b"".join(idat)
    try:
        raw = zlib.decompress(joined)
    except zlib.error:
        return None
    if len(raw) < height * (stride + 1) or max(raw[::stride + 1][:height]) > 4:
        return None
    del raw
    mode = _MODE[color]
    try:
        im = Image.frombytes(mode, (width, height), joined, "zip", mode)
        if im.mode != mode or im.size != (width, height):
            return None
        im.getpixel((0, 0))
    except Exception:  # noqa: BLE001 - any Pillow failure hands the image to the pure path, which decides
        return None
    if color == 0:
        def luma(x: int, y: int) -> int:
            return im.getpixel((x, y))
    else:
        def luma(x: int, y: int) -> int:
            p = im.getpixel((x, y))
            return (p[0] * 3 + p[1] * 6 + p[2]) // 10   # the kit formula, alpha ignored: NOT Pillow's convert("L")
    return width, height, luma


def _png_luma(data: bytes, fast: bool = True):
    head = _png_header(data)
    if head is None:
        return None
    width, height, color, idat = head
    if fast:
        parsed = _png_luma_pillow(width, height, color, idat)
        if parsed is not None:
            return parsed
    bpp = _BPP[color]
    try:
        raw = zlib.decompress(b"".join(idat))
    except zlib.error:
        return None
    pixels = _unfilter(raw, height, width * bpp, bpp)
    if pixels is None:
        return None

    def luma(x: int, y: int) -> int:
        o = (y * width + x) * bpp
        if color == 0:
            return pixels[o]
        r, g, b = pixels[o], pixels[o + 1], pixels[o + 2]
        return (r * 3 + g * 6 + b) // 10

    return width, height, luma


def _jpeg_luma(data: bytes):
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        im = Image.open(__import__("io").BytesIO(data)).convert("L")
    except Exception:
        return None
    w, h = im.size
    px = im.load()
    return w, h, lambda x, y: px[x, y]


def dhash(data: bytes, fast: bool = True) -> int | None:
    """fast=False forces the pure-Python PNG decoder (the reference); JPEG is unaffected."""
    parsed = _png_luma(data, fast)
    if parsed is None and data[:2] == b"\xff\xd8":
        parsed = _jpeg_luma(data)
    if parsed is None:
        return None
    w, h, luma = parsed
    bits = 0
    for y in range(8):
        sy = min(h - 1, int((y + 0.5) * h / 8))
        row = [luma(min(w - 1, int((x + 0.5) * w / 9)), sy) for x in range(9)]
        for x in range(8):
            bits = (bits << 1) | (1 if row[x] > row[x + 1] else 0)
    return bits


def similarity(a: int, b: int) -> float:
    return 1.0 - (bin(a ^ b).count("1") / 64.0)   # not int.bit_count(): the kit supports Python 3.9; a ^ b >= 0 (hashes are 0..2**64-1)


def too_similar(a: int, b: int) -> bool:
    return similarity(a, b) >= SIMILAR


def read_cache(path: str) -> dict:
    """{sha256: dhash} from the cache file. A file that is absent, unreadable, too big, not JSON or not a dict
    gives {}; an entry that is not [ALGO_VERSION, 0 <= int < 2**64] under a 64-hex key is dropped (a miss).
    Nothing here may change a result: the worst a bad cache can do is make the run cold.
    Opened O_NONBLOCK and only a regular file is read: a FIFO at the path would otherwise block the gate for ever."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:   # absent or unreadable: a cold start; the next save() writes the file
        return {}
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return {}
        with os.fdopen(fd, "rb", closefd=False) as f:
            blob = f.read(_CACHE_MAX_BYTES + 1)
    except OSError:
        return {}
    finally:
        os.close(fd)
    if len(blob) > _CACHE_MAX_BYTES:
        return {}
    try:
        raw = json.loads(blob.decode("utf-8"))
    except (ValueError, RecursionError):   # corrupt: a cold start; the next save() rewrites the file
        return {}
    if not isinstance(raw, dict):
        return {}
    out = {}
    for key, val in raw.items():
        if (isinstance(key, str) and len(key) == 64 and _HEX.issuperset(key) and isinstance(val, list) and len(val) == 2
                and type(val[0]) is int and val[0] == ALGO_VERSION and type(val[1]) is int and 0 <= val[1] < 1 << 64):
            out[key] = val[1]
    return out


class HashCache:
    """dhash memoised by the sha256 of the image BYTES (never the path or mtime) in `path`, normally
    <git-common-dir>/postfix-gate/proof-hash-cache.json; path=None caches nothing.
    Only a PNG hash is stored: it is the same on every machine (the pure and the Pillow decoder agree), while a JPEG
    hash depends on the local Pillow/libjpeg build, and "no hash" is cheap to recompute.
    ponytail: a value an agent writes into this file (INSTINCT-027) can make the >=98%-same-screen warning vanish; it is only
    a warning, no exit code or block reads the cache. Upgrade when that warning becomes a block: do not cache fresh images."""

    def __init__(self, path: str | None = None):
        self.path = path
        self.entries = read_cache(path) if path else {}
        self.added = {}

    def get(self, data: bytes, digest: str | None = None) -> int | None:
        if not self.path or data[:8] != _PNG_SIG:
            return dhash(data)
        if digest is None:
            digest = hashlib.sha256(data).hexdigest()
        bits = self.entries.get(digest)
        if bits is None:
            bits = dhash(data)
            if bits is not None:
                self.entries[digest] = self.added[digest] = bits
        return bits

    def save(self) -> None:
        """Write what this run computed on top of the file as it is now (read-merge-write, NO lock: two gates saving at
        once can overwrite each other's new entries; the cost is a later cache miss, never a wrong value). The write is
        atomic (temp file in the same directory + os.replace), so a reader sees the old file or the new one, never half.
        Raises OSError when the directory is not writable: the caller decides how to report it."""
        if not self.path or not self.added:
            return
        merged = read_cache(self.path)
        merged.update(self.added)
        if len(merged) > CACHE_MAX:
            merged = dict(list(merged.items())[-CACHE_MAX:])
        folder = os.path.dirname(self.path)
        os.makedirs(folder, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_proof_hash.", dir=folder)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump({k: [ALGO_VERSION, v] for k, v in merged.items()}, f)
            os.replace(tmp, self.path)
        except OSError:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
        self.added = {}
