"""Minimal, structurally valid DEX files for tests/verification/test_dexscan.sh.

A real DEX never stores a reference as one smali string `Lcls;->name`: the class descriptor and the member name are two
entries of string_ids, joined only through method_ids / field_ids (class_idx -> type_ids -> string, name_idx -> string).
This builds exactly those tables, so a scanner that only greps for `Lcls;->name` finds nothing here — as on a real APK.

dex(methods=(), fields=(), filler=0, tail=b"") -> bytes
  methods / fields: [(class_descriptor, member_name)]; filler: extra method_ids that all point at La;->m;
  tail: bytes appended after the string data (header file_size counts them, as d8 would).
"""
import struct


def uleb128(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def dex(methods=(), fields=(), filler=0, tail=b""):
    methods = list(methods) + [("La;", "m")] * filler
    classes = sorted({c for c, _ in methods} | {c for c, _ in fields} | ({"I"} if fields else set()))
    strings = sorted(set(classes) | {n for _, n in methods} | {n for _, n in fields})
    sidx = {s: i for i, s in enumerate(strings)}
    tidx = {c: i for i, c in enumerate(classes)}
    off = 0x70
    string_ids_off = off; off += 4 * len(strings)
    type_ids_off = off; off += 4 * len(classes)
    field_ids_off = off; off += 8 * len(fields)
    method_ids_off = off; off += 8 * len(methods)
    data = bytearray()
    string_offs = []
    for s in strings:
        string_offs.append(off + len(data))
        b = s.encode()
        data += uleb128(len(b)) + b + b"\0"
    body = bytearray()
    body += b"".join(struct.pack("<I", o) for o in string_offs)
    body += b"".join(struct.pack("<I", sidx[c]) for c in classes)
    body += b"".join(struct.pack("<HHI", tidx[c], tidx["I"], sidx[n]) for c, n in fields)
    body += b"".join(struct.pack("<HHI", tidx[c], 0, sidx[n]) for c, n in methods)
    h = bytearray(0x70)
    h[0:8] = b"dex\n035\x00"
    struct.pack_into("<II", h, 0x38, len(strings), string_ids_off)
    struct.pack_into("<II", h, 0x40, len(classes), type_ids_off)
    struct.pack_into("<II", h, 0x50, len(fields), field_ids_off if fields else 0)
    struct.pack_into("<II", h, 0x58, len(methods), method_ids_off if methods else 0)
    out = bytes(body) + bytes(data) + bytes(tail)
    struct.pack_into("<I", h, 0x20, 0x70 + len(out))  # file_size
    return bytes(h) + out
