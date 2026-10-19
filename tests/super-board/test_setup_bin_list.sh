#!/usr/bin/env bash
# Test hồi quy cho danh sách BIN của .claude/bin/super-board-setup.py.
# 19/10 (OCR): super-board-needs-you.py (runner/merge gate/skill gọi) thiếu trong BIN. `setup check` chỉ kiểm,
# `setup fix` chỉ chép script có trong BIN, nên repo khác không có script đó mà runner vẫn gọi -> file không tồn tại.
# Quy tắc: mọi script super-* nằm trong .claude/bin và được runner/workflow/skill/script khác gọi tới đều phải có trong BIN.
# Script chỉ nằm trong thư mục skill (skills/*/scripts) hoặc ở $HOME không thuộc .claude/bin nên không bị kiểm.
# Chỉ đọc repo (không ghi, không chạm repo thật). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETUP="$ROOT/.claude/bin/super-board-setup.py"
BINDIR="$ROOT/.claude/bin"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# BIN đọc bằng ast (không import, không chạy setup).
BIN_LIST="$(python3 - "$SETUP" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "BIN" for t in node.targets):
        print("\n".join(ast.literal_eval(node.value)))
        break
else:
    sys.exit("BIN not found")
PY
)" || { fail "đọc BIN từ setup.py"; exit 1; }
if [ -n "$BIN_LIST" ]; then ok "đọc được BIN ($(echo "$BIN_LIST" | wc -l | tr -d ' ') mục)"; else fail "BIN rỗng"; exit 1; fi

# Script super-* được gọi từ nơi khác trong .claude (bin, skills, workflows, hooks).
REFS="$(cd "$ROOT/.claude" && grep -rhoE 'super-[a-z0-9-]+\.(sh|py)' bin skills workflows hooks 2>/dev/null | sort -u)"
n=0
for f in $REFS; do
  [ -f "$BINDIR/$f" ] || continue          # skill-local (skills/*/scripts) hoặc tùy chọn ở $HOME: không thuộc BIN
  n=$((n + 1))
  if echo "$BIN_LIST" | grep -qxF "$f"; then ok "BIN có $f"; else fail "BIN thiếu $f (được gọi nhưng setup không chép/kiểm)"; fi
done
if [ "$n" -gt 0 ]; then ok "đã kiểm $n script tham chiếu"; else fail "không tìm thấy script tham chiếu nào (grep hỏng?)"; fi

# Mọi mục BIN phải là file có thật trong .claude/bin (tránh gõ sai tên).
for b in $BIN_LIST; do
  [ -f "$BINDIR/$b" ] || fail "BIN có $b nhưng .claude/bin không có file"
done

if [ "$FAILS" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAIL: $FAILS"; exit 1; fi
