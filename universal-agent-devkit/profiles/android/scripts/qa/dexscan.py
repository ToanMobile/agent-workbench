#!/usr/bin/env python3
"""
dexscan.py — Android DEX & Bytecode Policy Scanner
Scans a compiled .apk / .aab or a classes.dex for references to dangerous APIs, counts the methods of each DEX
(warn at 60,000 while a module still has ONE DEX; one DEX holds at most 65,536) and, with --manifest, lists exported
components that no permission guards (an SDK can export one without the app's code asking for it).

A DEX stores a reference as method_ids / field_ids entries (class -> type_ids -> string, name -> string), never as one
smali string `Lcls;->name`: this scanner resolves those tables. (Before 2026-11-19 it grepped for the smali text, which
no real DEX contains — 0 of 32 DEX of OfficeReader's APK — so it reported "clean" for every app.)

Usage: dexscan.py <apk|aab|dex> [--manifest <merged AndroidManifest.xml>] [--app-package <pkg[,pkg...]>]
  --manifest takes the text manifest the build merged, e.g.
  app/build/intermediates/merged_manifests/release/AndroidManifest.xml (the one inside an APK is binary XML).
  --app-package chỉ tính lỗi cho lời gọi xuất phát từ class thuộc package của app; lời gọi từ thư viện ngoài và class R8 không package được báo riêng.
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
USAGE = "Usage: dexscan.py <apk|aab|dex> [--manifest <merged AndroidManifest.xml>] [--app-package <pkg[,pkg...]>]"
PKG_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$")


def _dalvik_op_widths():
    """Bảng độ dài (tính theo code unit 16-bit) cho 256 opcode Dalvik chuẩn."""
    widths = [1] * 256
    for op in (0x02, 0x05, 0x08, 0x13, 0x15, 0x16, 0x19, 0x1A, 0x1C, 0x1F, 0x20, 0x22, 0x23, 0x29, 0xFE, 0xFF):
        widths[op] = 2
    for op in (0x03, 0x06, 0x09, 0x14, 0x17, 0x1B, 0x24, 0x25, 0x26, 0x2A, 0x2B, 0x2C, 0xFC, 0xFD):
        widths[op] = 3
    widths[0x18] = 5  # const-wide (51l)
    for op in range(0x2D, 0x3E):  # cmp*, if-*
        widths[op] = 2
    for op in range(0x44, 0x6E):  # aget/aput/iget/iput/sget/sput
        widths[op] = 2
    for op in (0x6E, 0x6F, 0x70, 0x71, 0x72, 0x74, 0x75, 0x76, 0x77, 0x78):  # invoke-*
        widths[op] = 3
    for op in range(0x90, 0xB0):  # toán tử 2 ngôi 23x
        widths[op] = 2
    for op in range(0xD0, 0xE3):  # /lit16, /lit8
        widths[op] = 2
    for op in (0xFA, 0xFB):  # invoke-polymorphic (/range)
        widths[op] = 4
    return tuple(widths)


OP_WIDTHS = _dalvik_op_widths()


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


def _read_uleb128(data, pos):
    """Đọc số nguyên uleb128 tại vị trí pos có kiểm biên; trả (giá trị, vị trí mới)."""
    val, shift = 0, 0
    while True:
        if pos >= len(data):
            raise DexError("uleb128 out of range")
        b = data[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7
        if shift > 28:
            raise DexError("bad uleb128")


def _bad_id_maps(data):
    """Giải các bảng field_ids/method_ids tìm tham chiếu nguy hiểm; trả (bad_fields, bad_methods, ref_list)."""
    n_str, str_off = struct.unpack_from("<II", data, 0x38)
    n_type, type_off = struct.unpack_from("<II", data, 0x40)
    members = [struct.unpack_from("<II", data, at) for at in (0x50, 0x58)]  # field_ids, method_ids
    for size, off, item in ((n_str, str_off, 4), (n_type, type_off, 4), *((s, o, 8) for s, o in members)):
        if size and off + size * item > len(data):
            raise DexError("table out of range")
    wanted = [(c, n, label) for c, n, label in DANGEROUS_REFS if c in data and n in data]
    if not wanted:
        return {}, {}, []
    pairs = {(c, n): label for c, n, label in wanted}
    bad_fields, bad_methods, found = {}, {}, []
    for is_method, (size, off) in enumerate(members):  # mục: (u16 class_idx, u16 type/proto, u32 name_idx)
        if not size:
            continue
        names = {}
        target_map = bad_methods if is_method else bad_fields
        for i in range(size):
            class_idx, _, name_idx = struct.unpack_from("<HHI", data, off + 8 * i)
            if class_idx >= n_type:
                raise DexError("type index out of range")
            (desc_idx,) = struct.unpack_from("<I", data, type_off + 4 * class_idx)
            key = (desc_idx, name_idx)
            ref = names.get(key)
            if ref is None:
                ref = (_string(data, str_off, desc_idx, n_str), _string(data, str_off, name_idx, n_str))
                names[key] = ref
            if ref in pairs:
                ref_str = ref[0].decode(errors="replace") + "->" + ref[1].decode(errors="replace")
                entry = (pairs[ref], ref_str)
                target_map[i] = entry
                if entry not in found:
                    found.append(entry)
    return bad_fields, bad_methods, found


def dangerous_refs(data):
    """[(label, 'Lcls;->name')] of dangerous references in one DEX. Raises DexError / struct.error on broken tables."""
    _, _, found = _bad_id_maps(data)
    return found


def _insn_units(data, pos, end):
    """Độ dài (code unit 16-bit) của một lệnh hoặc pseudo-payload Dalvik tại pos, kèm opcode."""
    if pos + 2 > end:
        raise DexError("instruction truncated")
    insw = struct.unpack_from("<H", data, pos)[0]
    op = insw & 0xFF
    if insw == 0x0100:  # packed-switch-payload
        if pos + 4 > end:
            raise DexError("packed-switch-payload out of range")
        size = struct.unpack_from("<H", data, pos + 2)[0]
        return op, 4 + 2 * size
    if insw == 0x0200:  # sparse-switch-payload
        if pos + 4 > end:
            raise DexError("sparse-switch-payload out of range")
        size = struct.unpack_from("<H", data, pos + 2)[0]
        return op, 2 + 4 * size
    if insw == 0x0300:  # fill-array-data-payload
        if pos + 8 > end:
            raise DexError("fill-array-data-payload out of range")
        elem_w, size = struct.unpack_from("<HI", data, pos + 2)
        return op, 4 + (size * elem_w + 1) // 2
    return op, OP_WIDTHS[op]


def dangerous_callers(data):
    """Quét class_defs + bytecode code_item trong một DEX để quy thuộc từng tham chiếu nguy hiểm tới class gọi.
    Trả về ([(caller_desc_bytes, label, ref_str)], dead_table_refs) hoặc ([], []) nếu không có tham chiếu nguy hiểm."""
    bad_fields, bad_methods, _ = _bad_id_maps(data)
    if not bad_fields and not bad_methods:
        return [], []
    n_str, str_off = struct.unpack_from("<II", data, 0x38)
    n_type, type_off = struct.unpack_from("<II", data, 0x40)
    n_fld, _ = struct.unpack_from("<II", data, 0x50)
    n_mth, _ = struct.unpack_from("<II", data, 0x58)
    n_cls, cls_off = struct.unpack_from("<II", data, 0x60)
    if n_cls == 0:
        raise DexError("DEX không có class_defs để đối chiếu --app-package")
    if cls_off + 32 * n_cls > len(data):
        raise DexError("class_defs table out of range")

    results = []
    seen = set()
    used_fields, used_methods = set(), set()

    for ci in range(n_cls):
        cls_type_idx, _, _, _, _, _, cls_data_off, _ = struct.unpack_from("<IIIIIIII", data, cls_off + 32 * ci)
        if cls_type_idx >= n_type:
            raise DexError("class type index out of range")
        if cls_data_off == 0:
            continue
        if cls_data_off >= len(data):
            raise DexError("class_data_off out of range")
        (desc_idx,) = struct.unpack_from("<I", data, type_off + 4 * cls_type_idx)
        caller_desc = _string(data, str_off, desc_idx, n_str)

        p = cls_data_off
        sf, p = _read_uleb128(data, p)
        inf, p = _read_uleb128(data, p)
        dm, p = _read_uleb128(data, p)
        vm, p = _read_uleb128(data, p)
        for _ in range(sf + inf):
            _, p = _read_uleb128(data, p)
            _, p = _read_uleb128(data, p)
        for m_count in (dm, vm):
            for _ in range(m_count):
                _, p = _read_uleb128(data, p)
                _, p = _read_uleb128(data, p)
                code_off, p = _read_uleb128(data, p)
                if code_off == 0:
                    continue
                if code_off + 16 > len(data):
                    raise DexError("code_item header out of range")
                (insns_sz,) = struct.unpack_from("<I", data, code_off + 12)
                pos = code_off + 16
                end = pos + 2 * insns_sz
                if end > len(data):
                    raise DexError("code_item insns out of range")
                while pos < end:
                    op, units = _insn_units(data, pos, end)
                    nxt = pos + 2 * units
                    if nxt > end:
                        raise DexError("dalvik instruction exceeds code_item")
                    if 0x52 <= op <= 0x6D:  # iget/iput/sget/sput -> u16 field_idx ở word 1
                        (f_idx,) = struct.unpack_from("<H", data, pos + 2)
                        if f_idx >= n_fld:
                            raise DexError("field index out of range")
                        if f_idx in bad_fields:
                            used_fields.add(f_idx)
                            lbl, ref_str = bad_fields[f_idx]
                            k = (caller_desc, lbl, ref_str)
                            if k not in seen:
                                seen.add(k)
                                results.append(k)
                    elif (0x6E <= op <= 0x72) or (0x74 <= op <= 0x78) or op in (0xFA, 0xFB):  # invoke-* -> u16 method_idx ở word 1
                        (m_idx,) = struct.unpack_from("<H", data, pos + 2)
                        if m_idx >= n_mth:
                            raise DexError("method index out of range")
                        if m_idx in bad_methods:
                            used_methods.add(m_idx)
                            lbl, ref_str = bad_methods[m_idx]
                            k = (caller_desc, lbl, ref_str)
                            if k not in seen:
                                seen.add(k)
                                results.append(k)
                    pos = nxt

    dead_refs = (
        [v for idx, v in bad_fields.items() if idx not in used_fields]
        + [v for idx, v in bad_methods.items() if idx not in used_methods]
    )
    return results, dead_refs


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
    with open(manifest_path, "rb") as f:
        raw = f.read()
    # A real manifest has no DTD: refuse one (entity expansion / external entities) instead of parsing it.
    if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
        raise ET.ParseError("manifest has a DOCTYPE/ENTITY declaration, refused")
    root = ET.fromstring(raw)
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


def scan_apk_or_dex(target_path, manifest_path=None, app_packages=None):
    print(f"🔍 [DEXSCAN] Đang quét bytecode: {target_path}...")
    if not os.path.isfile(target_path):
        return usage(f"Tệp không tồn tại: {target_path}")
    if manifest_path is not None and not os.path.isfile(manifest_path):
        return usage(f"--manifest không tồn tại: {manifest_path}")
    app_prefixes = tuple(("L" + pkg.replace(".", "/") + "/").encode("ascii") for pkg in (app_packages or ()))
    try:
        blobs = dex_blobs(target_path)
    except (*UNREADABLE, ValueError) as e:
        return usage(f"Không đọc được {target_path}: {e}")
    if not blobs:
        return usage(f"Không có classes*.dex nào trong {target_path} — không có gì để quét")

    findings, counts, unreadable = [], [], []
    third_party, obfuscated, dead_notes = [], [], []
    for name, module, data in blobs:
        count = method_count(data)
        if count is None:
            print(f"⚠️ [{name}] không đọc được header DEX — chưa đếm method, chưa quét API")
            unreadable.append(f"{name}: không phải header DEX")  # never let a skipped entry read as clean
            continue
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
            if app_prefixes:
                callers, dead_refs = dangerous_callers(data)
                for lbl, ref_str in dead_refs:
                    dead_notes.append((name, lbl, ref_str))
                for caller_desc, lbl, ref_str in callers:
                    caller_str = caller_desc.decode(errors="replace")
                    if any(caller_desc.startswith(p) for p in app_prefixes):
                        findings.append((name, lbl, f"{ref_str} (từ {caller_str})"))
                    elif b"/" not in caller_desc:
                        # Lớp ở root package do R8 repackage/obfuscate (không biết thuộc app hay SDK): cảnh báo thay vì im lặng
                        obfuscated.append((name, caller_str, lbl, ref_str))
                    else:
                        third_party.append((name, caller_str, lbl, ref_str))
            else:
                refs = dangerous_refs(data)
                findings += [(name, label, ref) for label, ref in refs]
        except (DexError, struct.error) as e:
            unreadable.append(f"{name}: {e}")
            continue
        counts.append((name, module, count))  # only a DEX that read cleanly: a broken one gives a garbage count
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

    if third_party:
        sample_cls = ", ".join(dict.fromkeys(c for _, c, _, _ in third_party[:3]))
        print(f"ℹ️ [thư viện ngoài --app-package] bỏ qua {len(third_party)} lời gọi từ class thư viện (vd: {sample_cls})")
    if obfuscated:
        sample_obf = ", ".join(dict.fromkeys(c for _, c, _, _ in obfuscated[:3]))
        print(f"⚠️ [R8 root-package] {len(obfuscated)} lời gọi từ class không có package sau obfuscate (vd: {sample_obf}) — cần mapping R8 nếu muốn quy thuộc app/SDK")
    if dead_notes:
        print(f"ℹ️ [bảng DEX] {len(dead_notes)} tham chiếu nằm trong method_ids/field_ids nhưng không có lệnh bytecode nào gọi")

    if findings:
        print(f"❌ Phát hiện {len(findings)} tham chiếu API nguy hiểm:")
        for loc, lbl, ref in findings:
            print(f"  • [{loc}] {lbl} — {ref}")
        for entry in unreadable:  # a finding wins the exit code, but a DEX that could not be read is never hidden
            print(f"⚠️ chưa quét được: {entry}")
        return 1
    if unreadable:
        return usage("Không đọc được bảng tham chiếu của DEX, chưa kết luận sạch: " + "; ".join(unreadable))
    print("✔ Bytecode SẠCH: 0 tham chiếu API nguy hiểm.")
    return 0


def main(argv):
    args, manifest, raw_pkgs = [], None, []
    i = 0
    while i < len(argv):
        if argv[i] == "--manifest":
            if i + 1 >= len(argv):
                return usage("--manifest cần một đường dẫn")
            manifest = argv[i + 1]
            i += 2
            continue
        if argv[i] == "--app-package":
            if i + 1 >= len(argv):
                return usage("--app-package cần tên package")
            parts = [p.strip() for p in argv[i + 1].split(",")]
            if not any(parts) or any(not p or not PKG_RE.fullmatch(p) for p in parts):
                return usage(f"--app-package không hợp lệ: {argv[i + 1]!r}")
            raw_pkgs.extend(parts)
            i += 2
            continue
        args.append(argv[i])
        i += 1
    if len(args) != 1:
        return usage("cần đúng một file apk/aab/dex")
    return scan_apk_or_dex(args[0], manifest, raw_pkgs)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
