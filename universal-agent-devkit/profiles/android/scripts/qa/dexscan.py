#!/usr/bin/env python3
"""
dexscan.py — Android DEX & Bytecode Policy Scanner
Scans a compiled .apk / .aab / .aar or a classes.dex for dangerous APIs, counts the methods of each DEX
(warn at 60,000; one DEX holds at most 65,536) and, with --manifest, lists exported components that no
permission guards (an SDK can export one without the app's code asking for it).

Usage: dexscan.py <apk|aab|aar|dex> [--manifest <merged AndroidManifest.xml>]
  --manifest takes the text manifest the build merged, e.g.
  app/build/intermediates/merged_manifests/release/AndroidManifest.xml (the one inside an APK is binary XML).
Exit: 0 clean (warnings may be printed) · 1 dangerous API found · 2 usage, missing or unreadable input
"""

import os
import re
import struct
import sys
import zipfile
import xml.etree.ElementTree as ET

DANGEROUS_PATTERNS = [
    (re.compile(rb"Ljava/lang/reflect/Method;->setAccessible"), "Bypassing Java Access Control (Reflection setAccessible)"),
    (re.compile(rb"Landroid/os/Build;->SERIAL"), "Restricted Hardware Identifier Access (Build.SERIAL)"),
    (re.compile(rb"Landroid/telephony/TelephonyManager;->getDeviceId"), "Restricted Device ID Access (IMEI / getDeviceId)"),
    (re.compile(rb"Landroid/os/Environment;->getExternalStorageDirectory"), "Non-scoped legacy storage API (getExternalStorageDirectory)")
]
# classes.dex, classes2.dex … in an APK/AAR; <module>/dex/classes*.dex in an AAB (base and feature modules).
DEX_ENTRY = re.compile(r"^(?:[^/]+/dex/)?classes\d*\.dex$")
METHOD_WARN = 60000
METHOD_CAP = 65536
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
COMPONENTS = ("activity", "activity-alias", "service", "receiver", "provider")


def usage(message):
    print(f"✖ {message}\nUsage: dexscan.py <apk|aab|aar|dex> [--manifest <merged AndroidManifest.xml>]", file=sys.stderr)
    return 2


def method_count(data):
    """method_ids_size from the DEX header (uint32 LE at 0x58), or None when this is not a DEX."""
    if len(data) < 0x5C or data[:4] != b"dex\n":
        return None
    return struct.unpack_from("<I", data, 0x58)[0]


def dex_blobs(target_path):
    """[(name, bytes)] of every DEX in the input; raises OSError / zipfile.BadZipFile on unreadable input."""
    if zipfile.is_zipfile(target_path):
        with zipfile.ZipFile(target_path, "r") as z:
            return [(n, z.read(n)) for n in z.namelist() if DEX_ENTRY.match(n)]
    with open(target_path, "rb") as f:
        return [(os.path.basename(target_path), f.read())]


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


def scan_apk_or_dex(target_path, manifest_path=None):
    print(f"🔍 [DEXSCAN] Đang quét bytecode: {target_path}...")
    if not os.path.isfile(target_path):
        return usage(f"Tệp không tồn tại: {target_path}")
    if manifest_path is not None and not os.path.isfile(manifest_path):
        return usage(f"--manifest không tồn tại: {manifest_path}")
    try:
        blobs = dex_blobs(target_path)
    except (OSError, zipfile.BadZipFile) as e:
        return usage(f"Không đọc được {target_path}: {e}")
    if not blobs:
        return usage(f"Không có classes*.dex nào trong {target_path} — không có gì để quét")

    findings = []
    counts = []
    for name, data in blobs:
        for pat, label in DANGEROUS_PATTERNS:
            if pat.search(data):
                findings.append((name, label))
        count = method_count(data)
        if count is None:
            print(f"⚠️ [{name}] không đọc được header DEX — chưa đếm method")
        else:
            counts.append((name, count))
    # d8 fills every DEX of a multidex app close to the cap on purpose (real run on OfficeReader 2026-11-18: 8 of 31):
    # the 60,000 warning only means something while the app still has ONE DEX.
    if len(counts) == 1:
        name, count = counts[0]
        if count >= METHOD_WARN:
            print(f"⚠️ [{name}] {count} method — sát trần {METHOD_CAP} của một DEX (cảnh báo từ {METHOD_WARN}); thêm code sẽ buộc multidex")
        else:
            print(f"  [{name}] {count} method")
    elif counts:
        print(f"  multidex: {len(counts)} DEX, tổng {sum(c for _, c in counts)} method (DEX gần đầy là bình thường)")

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
        print(f"❌ Phát hiện {len(findings)} cảnh báo bytecode vi phạm chính sách:")
        for loc, lbl in findings:
            print(f"  • [{loc}] {lbl}")
        return 1
    print("✔ Bytecode SẠCH: 0 vi phạm chính sách API nguy hiểm.")
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
        return usage("cần đúng một file apk/aab/aar/dex")
    return scan_apk_or_dex(args[0], manifest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
