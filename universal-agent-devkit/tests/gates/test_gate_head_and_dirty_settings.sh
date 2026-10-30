#!/usr/bin/env bash
# bin/post-fix-gate.py head_and_dirty(), #691 (plan r5, mục 3, ca H1-H5): tree_fingerprint() ghim .claude/settings.json về blob HEAD, nên biên
# nhận KHÔNG được ghi path đó (hay con của nó) vào `dirty`: push_gate.tested_fingerprint dựng lại cây từ head+dirty và proof_gate.foreign_dirty_only
# đọc `dirty`; để lại path ghim thì fingerprint dựng lại lệch fingerprint đã ghim và biên nhận hợp lệ bị bác. File khác vẫn phải có mặt.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# hd <thư mục project>: các khoá của dirty trong head_and_dirty(), cách nhau bằng dấu phẩy ("" khi rỗng), hay NONE khi (None, {})
hd() { python3 - "$GATE" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
head, dirty = m.head_and_dirty(sys.argv[2])
print("NONE" if head is None else ",".join(sorted(dirty)))
PY
}
newrepo() { git -C "$1" init -q -b main . && git -C "$1" config user.email t@t && git -C "$1" config user.name t && git -C "$1" config commit.gpgsign false; }

R="$TMP/repo"; mkdir -p "$R/src" "$R/.claude"; newrepo "$R"
printf 'fun ok() = 1\n' > "$R/src/Core.kt"; printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
git -C "$R" add -A && git -C "$R" commit -qm init
[ "$(hd "$R")" = "" ] && ok "H0 cây sạch: dirty rỗng" || bad "H0 cây sạch mà dirty không rỗng: $(hd "$R")"

# H1 (đỏ-thật trên da9ad59e: path ghim có mặt trong dirty): sửa, xoá settings.json không vào dirty
printf '{"hooks":{"PreToolUse":[]}}\n' > "$R/.claude/settings.json"
[ "$(hd "$R")" = "" ] && ok "H1 settings.json sửa chưa commit: không có trong dirty" || bad "H1 settings.json sửa còn nằm trong dirty: $(hd "$R")"
rm -f "$R/.claude/settings.json"
[ "$(hd "$R")" = "" ] && ok "H1b settings.json bị xoá: không có trong dirty" || bad "H1b settings.json xoá còn nằm trong dirty: $(hd "$R")"
git -C "$R" checkout -q -- .claude/settings.json

# H5 (chốt chặn: xanh cả trước lẫn sau): file khác vẫn có mặt
printf 'fun ok() = 2\n' > "$R/src/Core.kt"
[ "$(hd "$R")" = "src/Core.kt" ] && ok "H5 file khác bẩn vẫn có trong dirty" || bad "H5 file khác bẩn mất khỏi dirty: $(hd "$R")"
printf '{"hooks":{"PreToolUse":[]}}\n' > "$R/.claude/settings.json"
[ "$(hd "$R")" = "src/Core.kt" ] && ok "H5b settings.json bẩn cùng file khác: chỉ file khác còn trong dirty" || bad "H5b dirty không đúng: $(hd "$R")"
git -C "$R" checkout -q -- .

# H1c (đỏ-thật): HEAD không có settings.json, file mới chưa track
R2="$TMP/repo2"; mkdir -p "$R2/src"; newrepo "$R2"
printf 'fun ok() = 1\n' > "$R2/src/Core.kt"; git -C "$R2" add -A && git -C "$R2" commit -qm init
mkdir -p "$R2/.claude" && printf '{"hooks":{}}\n' > "$R2/.claude/settings.json"
[ "$(hd "$R2")" = "" ] && ok "H1c HEAD không có settings.json, file mới chưa track: không có trong dirty" || bad "H1c file chưa track còn trong dirty: $(hd "$R2")"

# H2 (đỏ-thật): thư mục .claude/settings.json/ có file con chưa track (khớp cả con của path ghim, như EXCLUDE)
rm -rf "$R2/.claude"; mkdir -p "$R2/.claude/settings.json" && printf 'x\n' > "$R2/.claude/settings.json/foo"
[ "$(hd "$R2")" = "" ] && ok "H2 con của path ghim (.claude/settings.json/foo): không có trong dirty" || bad "H2 con của path ghim còn trong dirty: $(hd "$R2")"

# H3: project nằm dưới gốc repo (app/): chỉ path ghim CỦA project (tiền tố app/) bị lọc
R3="$TMP/repo3"; mkdir -p "$R3/app/.claude" "$R3/app/src" "$R3/.claude"; newrepo "$R3"
printf 'x\n' > "$R3/app/src/a.kt"; printf '{}\n' > "$R3/app/.claude/settings.json"; printf '{}\n' > "$R3/.claude/settings.json"
git -C "$R3" add -A && git -C "$R3" commit -qm init
printf '{"local":1}\n' > "$R3/app/.claude/settings.json"
[ "$(hd "$R3/app")" = "" ] && ok "H3 project con: app/.claude/settings.json sửa không có trong dirty" || bad "H3 project con: path ghim còn trong dirty: $(hd "$R3/app")"
printf '{"local":2}\n' > "$R3/.claude/settings.json"
[ "$(hd "$R3/app")" = ".claude/settings.json" ] && ok "H3b settings.json ở gốc repo (ngoài project app/) vẫn có trong dirty (chốt chặn)" || bad "H3b dirty không đúng: $(hd "$R3/app")"

# H4 (đỏ-thật): rev-parse --show-prefix lỗi thì (None, {}) như top/head, không đoán tiền tố
REALGIT="$(command -v git)"; SHIM="$TMP/shim"; mkdir -p "$SHIM"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "--show-prefix" ] && exit 128; done\nexec "%s" "$@"\n' "$REALGIT" > "$SHIM/git"; chmod +x "$SHIM/git"
OUT="$(PATH="$SHIM:$PATH" hd "$R")"
[ "$OUT" = "NONE" ] && ok "H4 --show-prefix lỗi: head_and_dirty trả (None, {})" || bad "H4 --show-prefix lỗi mà head_and_dirty không fail-closed: $OUT"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
