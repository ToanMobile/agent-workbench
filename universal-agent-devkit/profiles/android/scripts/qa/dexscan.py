#!/usr/bin/env python3
"""
dexscan.py — Android DEX & Bytecode Policy Scanner
Scans a compiled .apk / .aab or a classes.dex for references to dangerous APIs, counts the methods of each DEX
(warn at 60,000 while a module still has ONE DEX; one DEX holds at most 65,536) and, with --manifest, lists exported
components that no permission guards (an SDK can export one without the app's code asking for it).

A DEX stores a reference as method_ids / field_ids entries (class -> type_ids -> string, name -> string), never as one
smali string `Lcls;->name`: this scanner resolves those tables. (Before 2026-11-19 it grepped for the smali text, which
no real DEX contains — 0 of 32 DEX of OfficeReader's APK — so it reported "clean" for every app.)

Usage: dexscan.py <apk|aab|dex> [--manifest <merged AndroidManifest.xml>]
  --manifest takes the text manifest the build merged, e.g.
  app/build/intermediates/merged_manifests/release/AndroidManifest.xml (the one inside an APK is binary XML).
  An .aar holds classes.jar (JVM bytecode), not DEX: scan the APK/AAB that includes it.
Exit: 0 clean (warnings may be printed) · 1 dangerous API referenced · 2 usage, missing or unreadable input
"""

import os
import re
import struct
import sys
import zipfile
import zlib
import xml.etree.ElementTree as ET

# (class descriptor, member name, label) — a method or field reference resolved from the DEX tables.
DANGEROUS_REFS = [
    (b"Ljava/lang/reflect/Method;", b"setAccessible", "Bypassing Java Access Control (Reflection setAccessible)"),
    (b"Ljava/lang/reflect/AccessibleObject;", b"setAccessible", "Bypassing Java Access Control (Reflection setAccessible)"),
    (b"Ljava/lang/reflect/Field;", b"setAccessible", "Bypassing Java Access Control (Reflection setAccessible)"),
    (b"Ljava/lang/reflect/Constructor;", b"setAccessible", "Bypassing Java Access Control (Reflection setAccessible)"),
    (b"Landroid/os/Build;", b"SERIAL", "Restricted Hardware Identifier Access (Build.SERIAL)"),
    (b"Landroid/telephony/TelephonyManager;", b"getDeviceId", "Restricted Device ID Access (IMEI / getDeviceId)"),
    (b"Landroid/os/Environment;", b"getExternalStorageDirectory", "Non-scoped legacy storage API (getExternalStorageDirectory)"),
]
# classes.dex, classes2.dex … in an APK; <module>/dex/classes*.dex in an AAB (base and feature modules).
DEX_ENTRY = re.compile(r"^(?:([^/]+)/dex/)?classes\d*\.dex$")
METHOD_WARN = 60000
METHOD_CAP = 65536
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
COMPONENTS = ("activity", "activity-alias", "service", "receiver", "provider")
UNREADABLE = (OSError, zipfile.BadZipFile, zlib.error, RuntimeError, NotImplementedError, EOFError)
USAGE = "Usage: dexscan.py <apk|aab|dex> [--manifest <merged AndroidManifest.xml>]"


class DexError(ValueError):
    """The DEX tables point outside the file."""


def usage(message):
    print(f"✖ {message}\n{USAGE}", file=sys.stderr)
    return 2


def method_count(data):
    """method_ids_size from the DEX header (uint32 LE at 0x58), or None when this is not a DEX."""
    if len(data) < 0x70 or data[:4] != b"dex\n":
        return None
    return struct.unpack_from("<I", data, 0x58)[0]


def _string(data, string_ids_off, idx, count):
    if idx >= count:
        raise DexError("string index out of range")
    (pos,) = struct.unpack_from("<I", data, string_ids_off + 4 * idx)
    shift = 0
    while True:  # uleb128 utf16 length, then MUTF-8 bytes up to NUL
        if pos >= len(data):
            raise DexError("string data out of range")
        b = data[pos]
        pos += 1
        if not b & 0x80:
            break
        shift += 7
        if shift > 28:
            raise DexError("bad uleb128")
    end = data.find(b"\0", pos)
    if end < 0:
        raise DexError("unterminated string")
    return data[pos:end]


def dangerous_refs(data):
    """[(label, 'Lcls;->name')] of dangerous references in one DEX. Raises DexError / struct.error on broken tables.
    Only a DEX holding both pieces of a pair can reference it, so the tables are parsed only then — but every table is
    bounds-checked FIRST: a truncated DEX must never pass as clean through that shortcut."""
    n_str, str_off = struct.unpack_from("<II", data, 0x38)
    n_type, type_off = struct.unpack_from("<II", data, 0x40)
    members = [struct.unpack_from("<II", data, at) for at in (0x50, 0x58)]  # field_ids, method_ids
    for size, off, item in ((n_str, str_off, 4), (n_type, type_off, 4), *((s, o, 8) for s, o in members)):
        if size and off + size * item > len(data):
            raise DexError("table out of range")
    wanted = [(c, n, label) for c, n, label in DANGEROUS_REFS if c in data and n in data]
    if not wanted:
        return []
    pairs = {(c, n): label for c, n, label in wanted}
    found = []
    for size, off in members:  # item: (u16 class_idx, u16 type/proto, u32 name_idx)
        if not size:
            continue
        names = {}
        for i in range(size):
            class_idx, _, name_idx = struct.unpack_from("<HHI", data, off + 8 * i)
            if class_idx >= n_type:
                raise DexError("type index out of range")
            (desc_idx,) = struct.unpack_from("<I", data, type_off + 4 * class_idx)
            key = (desc_idx, name_idx)
            if key in names:
                continue
            ref = (_string(data, str_off, desc_idx, n_str), _string(data, str_off, name_idx, n_str))
            names[key] = ref
            if ref in pairs:
                found.append((pairs[ref], ref[0].decode(errors="replace") + "->" + ref[1].decode(errors="replace")))
    return found


def dex_blobs(target_path):
    """[(name, module, bytes)] of every DEX in the input; raises one of UNREADABLE on unreadable input."""
    if zipfile.is_zipfile(target_path):
        with zipfile.ZipFile(target_path, "r") as z:
            out = []
            for n in z.namelist():
                m = DEX_ENTRY.match(n)
                if m:
                    out.append((n, m.group(1) or "", z.read(n)))
            if not out and "classes.jar" in z.namelist():
                raise ValueError("an .aar holds classes.jar (JVM bytecode), not DEX — scan the APK/AAB that includes it")
            return out
    with open(target_path, "rb") as f:
        return [(os.path.basename(target_path), "", f.read())]


def unguarded_exports(manifest_path):
    """Exported components without a permission. Raises OSError / ET.ParseError on an unreadable manifest."""
    root = ET.parse(manifest_path).getroot()  # expat: no external entities are fetched
    found = []
    for tag in COMPONENTS:
        for node in root.iter(tag):
            if node.get(ANDROID_NS + "exported") != "true":
                continue
            if any(node.get(ANDROID_NS + a) for a in ("permission", "readPermission", "writePermission")):
                continue
            actions = {a.get(ANDROID_NS + "name") for a in node.iter("action")}
            categories = {c.get(ANDROID_NS + "name") for c in node.iter("category")}
            if "android.intent.action.MAIN" in actions and "android.intent.category.LAUNCHER" in categories:
                continue  # the launcher entry is meant to be exported
            if tag == "receiver" and "android.appwidget.action.APPWIDGET_UPDATE" in actions:
                continue  # an app widget must be exported: the launcher sends it APPWIDGET_UPDATE
            found.append((tag, node.get(ANDROID_NS + "name") or "?"))
    return found


def report_counts(counts):
    """counts: [(name, module, n)]. d8 fills every DEX of a multidex module close to the cap on purpose (real run on
    OfficeReader 2026-11-18: 8 of 31), so the 60,000 warning only means something for a module with ONE DEX."""
    modules = {}
    for name, module, n in counts:
        modules.setdefault(module, []).append((name, n))
    for module, items in sorted(modules.items()):
        if len(items) == 1:
            name, n = items[0]
            if n >= METHOD_WARN:
                print(f"⚠️ [{name}] {n} method — sát trần {METHOD_CAP} của một DEX (cảnh báo từ {METHOD_WARN}); thêm code sẽ buộc multidex")
            else:
                print(f"  [{name}] {n} method")
        else:
            where = f"module {module}: " if module else ""
            print(f"  {where}multidex: {len(items)} DEX, tổng {sum(n for _, n in items)} method (DEX gần đầy là bình thường)")


def scan_apk_or_dex(target_path, manifest_path=None):
    print(f"🔍 [DEXSCAN] Đang quét bytecode: {target_path}...")
    if not os.path.isfile(target_path):
        return usage(f"Tệp không tồn tại: {target_path}")
    if manifest_path is not None and not os.path.isfile(manifest_path):
        return usage(f"--manifest không tồn tại: {manifest_path}")
    try:
        blobs = dex_blobs(target_path)
    except (*UNREADABLE, ValueError) as e:
        return usage(f"Không đọc được {target_path}: {e}")
    if not blobs:
        return usage(f"Không có classes*.dex nào trong {target_path} — không có gì để quét")

    findings, counts, unreadable = [], [], []
    for name, module, data in blobs:
        count = method_count(data)
        if count is None:
            print(f"⚠️ [{name}] không đọc được header DEX — chưa đếm method, chưa quét API")
            unreadable.append(f"{name}: không phải header DEX")  # never let a skipped entry read as clean
            continue
        counts.append((name, module, count))
        (declared,) = struct.unpack_from("<I", data, 0x20)  # header file_size: d8 writes the real size
        if declared != len(data):
            # A cut anywhere (string data sits after the id tables) must never pass the "no dangerous strings" shortcut.
            unreadable.append(f"{name}: file_size {declared} ≠ {len(data)} byte (DEX bị cắt hoặc hỏng)")
            continue
        (checksum,) = struct.unpack_from("<I", data, 0x08)  # adler32 of data[12:], written by d8
        if zlib.adler32(data[12:]) != checksum:
            unreadable.append(f"{name}: checksum adler32 sai (DEX hỏng)")
            continue
        try:
            findings += [(name, label, ref) for label, ref in dangerous_refs(data)]
        except (DexError, struct.error) as e:
            unreadable.append(f"{name}: {e}")
    report_counts(counts)

    if manifest_path is None:
        print("ℹ️ manifest: chưa kiểm (truyền --manifest <merged AndroidManifest.xml> để liệt kê component exported)")
    else:
        try:
            exports = unguarded_exports(manifest_path)
        except (OSError, ET.ParseError) as e:
            return usage(f"Không đọc được --manifest {manifest_path}: {e}")
        for tag, comp in exports:
            print(f"⚠️ [manifest] <{tag}> {comp} exported=\"true\" không có permission — kiểm ai gọi được nó")
        if not exports:
            print("  [manifest] không có component exported nào thiếu permission (ngoài launcher)")

    if findings:
        print(f"❌ Phát hiện {len(findings)} tham chiếu API nguy hiểm:")
        for loc, lbl, ref in findings:
            print(f"  • [{loc}] {lbl} — {ref}")
        return 1
    if unreadable:
        return usage("Không đọc được bảng tham chiếu của DEX, chưa kết luận sạch: " + "; ".join(unreadable))
    print("✔ Bytecode SẠCH: 0 tham chiếu API nguy hiểm.")
    return 0


def main(argv):
    args, manifest = [], None
    i = 0
    while i < len(argv):
        if argv[i] == "--manifest":
            if i + 1 >= len(argv):
                return usage("--manifest cần một đường dẫn")
            manifest = argv[i + 1]
            i += 2
            continue
        args.append(argv[i])
        i += 1
    if len(args) != 1:
        return usage("cần đúng một file apk/aab/dex")
    return scan_apk_or_dex(args[0], manifest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
