#!/usr/bin/env bash
# Test hồi quy: dexscan.py --app-package lọc tham chiếu API nguy hiểm theo class gọi trong bytecode Dalvik,
# tách thư viện ngoài khỏi code app, giữ tương thích ngược khi không truyền cờ và fail-closed khi thiếu class_defs.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCAN="$DEVKIT_DIR/profiles/android/scripts/qa/dexscan.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dexscan-pkg.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Dựng các file APK/DEX tổng hợp có đầy đủ class_defs, class_data_item và code_item hợp lệ
python3 - "$TMP" <<'PY'
import struct
import sys
import zipfile
import zlib

out_dir = sys.argv[1]


def uleb128(n):
    buf = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            buf.append(b | 0x80)
        else:
            buf.append(b)
            return bytes(buf)


def build_dex(classes, extra_methods=(), extra_fields=(), drop_class_defs=False):
    """Dựng DEX 035 chuẩn cho test bytecode:
    classes = [(class_desc, [(target_kind, target_cls, target_name, insns_builder_type)])]
    """
    m_refs = []
    f_refs = []
    for _, calls in classes:
        for kind, cls, name, _ in calls:
            pair = (cls, name)
            if kind == "method" and pair not in m_refs:
                m_refs.append(pair)
            elif kind == "field" and pair not in f_refs:
                f_refs.append(pair)
    for pair in extra_methods:
        if pair not in m_refs:
            m_refs.append(pair)
    for pair in extra_fields:
        if pair not in f_refs:
            f_refs.append(pair)

    types_set = {"Ljava/lang/Object;", "V"}
    for c, calls in classes:
        types_set.add(c)
        for _, tc, _, _ in calls:
            types_set.add(tc)
    for tc, _ in m_refs + f_refs:
        types_set.add(tc)
    if f_refs:
        types_set.add("Ljava/lang/String;")
    classes_types = sorted(types_set)
    strings_set = set(classes_types) | {"run"} | {n for _, n in m_refs + f_refs}
    strings = sorted(strings_set)

    sidx = {s: i for i, s in enumerate(strings)}
    tidx = {t: i for i, t in enumerate(classes_types)}
    fidx = {pair: i for i, pair in enumerate(f_refs)}
    midx = {pair: i for i, pair in enumerate(m_refs)}

    # Bố trí bảng ở đầu file
    off = 0x70
    string_ids_off = off
    off += 4 * len(strings)
    type_ids_off = off
    off += 4 * len(classes_types)
    proto_ids_off = off
    n_protos = 1
    off += 12 * n_protos
    field_ids_off = off
    off += 8 * len(f_refs)
    method_ids_off = off
    off += 8 * len(m_refs)
    cls_list = [] if drop_class_defs else classes
    class_defs_off = off
    off += 32 * len(cls_list)

    data_off = off
    data = bytearray()

    def align4():
        while (data_off + len(data)) % 4 != 0:
            data.append(0)

    # Ghi chuỗi dạng MUTF-8 kèm độ dài uleb128
    string_offs = []
    for s in strings:
        string_offs.append(data_off + len(data))
        raw = s.encode("utf-8")
        data += uleb128(len(raw)) + raw + b"\0"

    # Tạo 1 method cho mỗi calls để mang bytecode invoke / sget / const
    cls_data_offs = []
    # Đảm bảo method nội bộ "run" nằm sẵn trong method_ids để làm direct_method
    for c, calls in cls_list:
        if (c, "run") not in midx:
            # Nếu thiếu sẽ thêm vào sau; ta chèn run vào extra_methods từ đầu
            raise RuntimeError(f"Thiếu {c}->run trong extra_methods")

    for c, calls in cls_list:
        insns = bytearray()
        for kind, tc, tn, mode in calls:
            if mode == "invoke":
                idx = midx[(tc, tn)]
                # invoke-virtual {v0}, method@idx (opcode 0x6e, 3 word = 6 byte)
                insns += struct.pack("<HHH", 0x006E, idx, 0x0000)
            elif mode == "sget":
                idx = fidx[(tc, tn)]
                # sget-object v0, field@idx (opcode 0x62, 2 word = 4 byte)
                insns += struct.pack("<HH", 0x0062, idx)
            elif mode == "const_trick":
                # const v0, 0x0000006e (opcode 0x14 = 31i, dài 3 word; word thứ 2 là 0x006e trùng invoke-virtual,
                # word thứ 3 là idx của Method;->setAccessible = midx[(tc, tn)]). Bộ đọc sai căn chỉnh sẽ báo nhầm!
                idx = midx[(tc, tn)]
                insns += struct.pack("<HHH", 0x0014, 0x006E, idx)
        # return-void (0x000e)
        insns += struct.pack("<H", 0x000E)

        align4()
        code_item_off = data_off + len(data)
        insns_size_words = len(insns) // 2
        data += struct.pack("<HHHHII", 2, 1, 1, 0, 0, insns_size_words) + insns

        class_data_off = data_off + len(data)
        cls_data_offs.append(class_data_off)
        # 0 static_fields, 0 instance_fields, 1 direct_method, 0 virtual_methods
        data += uleb128(0) + uleb128(0) + uleb128(1) + uleb128(0)
        data += uleb128(midx[(c, "run")]) + uleb128(0x0001) + uleb128(code_item_off)

    body = bytearray()
    body += b"".join(struct.pack("<I", o) for o in string_offs)
    body += b"".join(struct.pack("<I", sidx[t]) for t in classes_types)
    # 1 proto: (shorty="V", return_type="V", parameters_off=0)
    body += struct.pack("<III", sidx["V"], tidx["V"], 0)
    body += b"".join(struct.pack("<HHI", tidx[tc], tidx["Ljava/lang/String;"], sidx[tn]) for tc, tn in f_refs)
    body += b"".join(struct.pack("<HHI", tidx[tc], 0, sidx[tn]) for tc, tn in m_refs)
    for (c, _), cd_off in zip(cls_list, cls_data_offs):
        body += struct.pack("<IIIIIIII", tidx[c], 0x0001, tidx["Ljava/lang/Object;"], 0, 0, 0, cd_off, 0)

    header = bytearray(0x70)
    header[0:8] = b"dex\n035\x00"
    struct.pack_into("<II", header, 0x20, 0x70 + len(body) + len(data), 0x70)
    struct.pack_into("<I", header, 0x28, 0x12345678)
    struct.pack_into("<II", header, 0x38, len(strings), string_ids_off)
    struct.pack_into("<II", header, 0x40, len(classes_types), type_ids_off)
    struct.pack_into("<II", header, 0x48, n_protos, proto_ids_off)
    struct.pack_into("<II", header, 0x50, len(f_refs), field_ids_off if f_refs else 0)
    struct.pack_into("<II", header, 0x58, len(m_refs), method_ids_off if m_refs else 0)
    struct.pack_into("<II", header, 0x60, len(cls_list), class_defs_off if cls_list else 0)
    struct.pack_into("<II", header, 0x68, len(data), data_off)

    whole = bytearray(bytes(header) + bytes(body) + bytes(data))
    struct.pack_into("<I", whole, 0x08, zlib.adler32(bytes(whole[12:])))
    return bytes(whole)


# Ca 1: Chỉ thư viện ngoài Landroidx/ gọi setAccessible, code com.myapp an toàn
dex1 = build_dex(
    classes=[
        ("Landroidx/appcompat/widget/AppCompatTextView;", [
            ("method", "Ljava/lang/reflect/AccessibleObject;", "setAccessible", "invoke"),
        ]),
        ("Lcom/myapp/Safe;", []),
    ],
    extra_methods=[("Landroidx/appcompat/widget/AppCompatTextView;", "run"), ("Lcom/myapp/Safe;", "run")],
)
with zipfile.ZipFile(f"{out_dir}/thirdparty_only.apk", "w") as z:
    z.writestr("classes.dex", dex1)

# Ca 2a: Chính code app com.myapp gọi Method;->setAccessible
dex2 = build_dex(
    classes=[
        ("Lcom/myapp/Reflector;", [
            ("method", "Ljava/lang/reflect/Method;", "setAccessible", "invoke"),
        ]),
    ],
    extra_methods=[("Lcom/myapp/Reflector;", "run")],
)
with zipfile.ZipFile(f"{out_dir}/app_refl.apk", "w") as z:
    z.writestr("classes.dex", dex2)

# Ca 2b: Chính code app com.myapp đọc Build.SERIAL
dex2b = build_dex(
    classes=[
        ("Lcom/myapp/IdReader;", [
            ("field", "Landroid/os/Build;", "SERIAL", "sget"),
        ]),
    ],
    extra_methods=[("Lcom/myapp/IdReader;", "run")],
)
with zipfile.ZipFile(f"{out_dir}/app_serial.apk", "w") as z:
    z.writestr("classes.dex", dex2b)

# Ca 3: Lệnh const v0, 0x0000006e có 2 byte sau trùng 0x006e + idx Method;->setAccessible trong com.myapp,
# trong khi chỉ thư viện Landroidx/lib/X; gọi thật sự -> lọc đúng không được báo nhầm com.myapp
dex3 = build_dex(
    classes=[
        ("Lcom/myapp/ConstOnly;", [
            ("method", "Ljava/lang/reflect/Method;", "setAccessible", "const_trick"),
        ]),
        ("Landroidx/lib/X;", [
            ("method", "Ljava/lang/reflect/Method;", "setAccessible", "invoke"),
        ]),
    ],
    extra_methods=[("Ljava/lang/reflect/Method;", "setAccessible"), ("Lcom/myapp/ConstOnly;", "run"), ("Landroidx/lib/X;", "run")],
)
with zipfile.ZipFile(f"{out_dir}/const_align.apk", "w") as z:
    z.writestr("classes.dex", dex3)

# Ca 4: DEX có Method;->setAccessible trong method_ids nhưng class_defs_size == 0 -> phải từ chối fail-closed (exit 2)
dex4 = build_dex(
    classes=[
        ("Lcom/myapp/NoClassDefs;", []),
    ],
    extra_methods=[("Ljava/lang/reflect/Method;", "setAccessible"), ("Lcom/myapp/NoClassDefs;", "run")],
    drop_class_defs=True,
)
open(f"{out_dir}/noclassdefs.dex", "wb").write(dex4)
PY

FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Ca 1a: không truyền --app-package vẫn giữ tương thích ngược -> exit 1
python3 "$SCAN" "$TMP/thirdparty_only.apk" >"$TMP/c1a.log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'setAccessible' "$TMP/c1a.log" \
  && ok "Ca 1a: không truyền --app-package vẫn giữ tương thích ngược (exit 1)" \
  || bad "Ca 1a: mong đợi exit 1 nhưng ra rc=$rc: $(cat "$TMP/c1a.log")"

# Ca 1b: truyền --app-package com.myapp -> exit 0, ghi chú thư viện ngoài và không báo lỗi ❌
python3 "$SCAN" "$TMP/thirdparty_only.apk" --app-package com.myapp >"$TMP/c1b.log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'Landroidx/' "$TMP/c1b.log" && ! grep -q '❌' "$TMP/c1b.log"; then
  ok "Ca 1b: --app-package com.myapp lọc thư viện ngoài Landroidx/ -> exit 0"
else
  bad "Ca 1b: mong đợi exit 0 với --app-package nhưng ra rc=$rc: $(cat "$TMP/c1b.log")"
fi

# Ca 2a: chính class của app com.myapp gọi setAccessible -> exit 1, nêu rõ tên class gọi
python3 "$SCAN" "$TMP/app_refl.apk" --app-package com.myapp >"$TMP/c2a.log" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'Lcom/myapp/Reflector;' "$TMP/c2a.log"; then
  ok "Ca 2a: code app gọi setAccessible -> exit 1 kèm tên class caller"
else
  bad "Ca 2a: mong đợi exit 1 nêu Lcom/myapp/Reflector; nhưng ra rc=$rc: $(cat "$TMP/c2a.log")"
fi

# Ca 2b: chính class của app com.myapp đọc Build.SERIAL -> exit 1, nêu rõ tên class gọi
python3 "$SCAN" "$TMP/app_serial.apk" --app-package com.myapp >"$TMP/c2b.log" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'Lcom/myapp/IdReader;' "$TMP/c2b.log"; then
  ok "Ca 2b: code app đọc Build.SERIAL -> exit 1 kèm tên class caller"
else
  bad "Ca 2b: mong đợi exit 1 nêu Lcom/myapp/IdReader; nhưng ra rc=$rc: $(cat "$TMP/c2b.log")"
fi

# Ca 3: an toàn căn chỉnh opcode Dalvik qua lệnh const 31i
python3 "$SCAN" "$TMP/const_align.apk" --app-package com.myapp >"$TMP/c3.log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'Lcom/myapp/ConstOnly;' "$TMP/c3.log"; then
  ok "Ca 3: bước nhảy độ dài lệnh Dalvik qua const 31i đúng, không dương tính giả"
else
  bad "Ca 3: đọc nhầm tham chiếu trong hằng số const -> rc=$rc: $(cat "$TMP/c3.log")"
fi

# Ca 4: lỗi tham số & fail-closed khi DEX thiếu class_defs
python3 "$SCAN" "$TMP/thirdparty_only.apk" --app-package >"$TMP/c4a.log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "Ca 4a: --app-package thiếu giá trị -> exit 2" || bad "Ca 4a: rc=$rc"

python3 "$SCAN" "$TMP/thirdparty_only.apk" --app-package "" >"$TMP/c4b.log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "Ca 4b: --app-package rỗng -> exit 2" || bad "Ca 4b: rc=$rc"

python3 "$SCAN" "$TMP/noclassdefs.dex" --app-package com.myapp >"$TMP/c4c.log" 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'class_defs' "$TMP/c4c.log" && ! grep -q 'SẠCH' "$TMP/c4c.log"; then
  ok "Ca 4c: DEX thiếu class_defs khi dùng --app-package -> exit 2 (fail-closed, không báo SẠCH)"
else
  bad "Ca 4c: DEX thiếu class_defs bị lọt -> rc=$rc: $(cat "$TMP/c4c.log")"
fi

[ "$FAILS" -eq 0 ] && { echo "test_dexscan_app_package: PASS"; exit 0; }
echo "test_dexscan_app_package: $FAILS FAILED"
exit 1
