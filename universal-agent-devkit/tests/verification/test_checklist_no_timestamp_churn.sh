#!/usr/bin/env bash
# 18/10 (agent-workbench, GeelyEx2): mỗi lần gate chạy, bin/regression_checklist.py save() ghi lại `.agents/CHECKLIST.md` (file được track) chỉ để
# đổi dòng "> Sinh tự động lúc <giờ>", nên main không bao giờ sạch và commit bookkeeping luôn đuổi theo. Luật:
#   1 save lại khi nội dung không đổi: CHECKLIST.md giữ nguyên byte (giờ sinh cũ), regression_status.json không bị ghi lại (cùng inode)
#   2 có thay đổi thật (thêm một bug): cả hai file được ghi, giờ sinh mới
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; RC="$DEVKIT_DIR/bin/regression_checklist.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo 1 > src/x.txt
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Lõi","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"true"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
V="$P/.agents/CHECKLIST.md"; S="$P/.agents/regression_status.json"
python3 "$RC" render >/dev/null 2>&1
# giờ sinh cũ hẳn (không phụ thuộc đồng hồ giây): sửa dòng giờ thành một ngày xa
python3 - "$V" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"Sinh tự động lúc [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}","Sinh tự động lúc 2001-01-01 00:00:00", s))
PY
before="$(shasum "$V" | cut -d' ' -f1)"; ino="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$S")"
python3 "$RC" render >/dev/null 2>&1
after="$(shasum "$V" | cut -d' ' -f1)"; ino2="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$S")"
[ "$before" = "$after" ] && grep -q "Sinh tự động lúc 2001-01-01 00:00:00" "$V" && ok "nothing changed: CHECKLIST.md kept byte for byte (old timestamp)" \
  || fail "CHECKLIST.md rewritten for the timestamp only: $(grep -m1 'Sinh tự động' "$V")"
[ -s "$S" ] && [ -n "$ino" ] && [ "$ino" = "$ino2" ] && ok "nothing changed: regression_status.json not rewritten (same inode)" || fail "regression_status.json rewritten with the same content"

bash "$KIT" bugs add "Lỗi thật mới" --module "Lõi" >/dev/null 2>&1
grep -q "Lỗi thật mới" "$V" && ! grep -q "Sinh tự động lúc 2001-01-01" "$V" && grep -q "Lỗi thật mới" "$S" \
  && ok "a real change: both files written, a fresh timestamp" || fail "real change not written: $(grep -m1 'Sinh tự động' "$V")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_checklist_no_timestamp_churn: PASS"; exit 0; } || { echo "test_checklist_no_timestamp_churn: FAIL ($FAILS)"; exit 1; }
