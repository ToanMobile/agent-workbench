#!/usr/bin/env bash
# Test: super-build SKILL.md "Lifecycle (Builder, rebuild)" — sau khi sửa theo review, cây đổi nên gate scoped chạy lại
# đúng MỘT lần trên cây sau sửa, ở lane QA (QA sở hữu gate, run.md); Builder chỉ chạy test đích + `bash <test>` của file sửa.
# Số đo 03/11/2026 (workbench 24 h): 18 lượt gate scoped lặp sau một lượt exit 0 = 12,6 % giây suite.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_MD="$ROOT/.claude/skills/super-build/SKILL.md"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$BUILD_MD" ] || { echo "✖ thiếu $BUILD_MD"; exit 1; }
# chỉ đoạn rebuild: từ "### Lifecycle (Builder, rebuild)" tới heading ### kế tiếp, nối thành một dòng
reb="$(awk '/^### Lifecycle \(Builder, rebuild\)/{f=1; next} f && /^### /{f=0} f' "$BUILD_MD" | tr '\n' ' ' | tr -s ' ')"
[ -n "$reb" ] || { echo "✖ không thấy đoạn Lifecycle (Builder, rebuild)"; exit 1; }
has() { case "$reb" in *"$1"*) return 0 ;; esac; return 1; }

has "post-fix-gate.py --run-tests --scoped --brief" && ok "rebuild nêu lệnh gate scoped" \
  || fail "rebuild không nêu gate scoped chạy lại trên cây sau sửa"
has "once on the post-fix tree" && ok "rebuild: gate chạy lại một lần trên cây sau sửa" \
  || fail "rebuild không nói gate chạy lại đúng một lần trên cây sau sửa"
has "\`bash <test>\`" && ok "rebuild: Builder chạy test đích + bash <test> của file sửa" \
  || fail "rebuild không nói Builder chỉ chạy test đích + bash <test>"
has "no gate of its own" && ok "rebuild: Builder không tự gate (QA sở hữu gate)" \
  || fail "rebuild không nói Builder không tự chạy gate (sẽ gate hai lần)"
# đoạn 'Too big' vẫn giữ một --scoped mỗi PR
grep -q "one \`post-fix-gate.py --run-tests --scoped\`" "$BUILD_MD" && ok "Too big: một --scoped mỗi PR còn nguyên" \
  || fail "Too big: mất câu một --scoped mỗi PR"

[ "$FAILS" = 0 ] && echo "✅ test_rebuild_gate_once: all checks passed" || { echo "❌ test_rebuild_gate_once: $FAILS failed"; exit 1; }
