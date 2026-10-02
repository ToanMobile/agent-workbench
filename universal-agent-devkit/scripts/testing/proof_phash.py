#!/usr/bin/env python3
"""64-bit difference hash for proof screenshots.

Similarity is 1 - hamming/64. Two images are the same screen when similarity
>= 0.98 (at most one bit differs). PNG is decoded with zlib. JPEG needs Pillow;
without it the caller keeps the SHA-256 check only.
"""

from __future__ import annotations

import struct
import zlib

SIMILAR = 0.98


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


def _png_luma(data: bytes):
    if len(data) < 8 or data[:8] != b"\x89PNG\r\n\x1a\n":
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
    bpp = {0: 1, 2: 3, 6: 4}[color]
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


def dhash(data: bytes) -> int | None:
    parsed = _png_luma(data)
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
    return 1.0 - ((a ^ b).bit_count() / 64.0)


def too_similar(a: int, b: int) -> bool:
    return similarity(a, b) >= SIMILAR
