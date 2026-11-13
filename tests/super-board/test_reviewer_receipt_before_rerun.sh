#!/usr/bin/env bash
# Đợt 2 tối ưu gate, mục 5 (v3): sau khi duyệt test sửa, lane Review đọc biên nhận gate theo head (commit đã gate, kể cả khi QA đã
# merge base trước khi gate) và CHỈ bỏ lần chạy lại khi đã có biên nhận exit 0 đúng head + fingerprint; chưa có thì vẫn chạy MỘT lần
# `post-fix-gate.py --run-tests --scoped --brief` sau khi ghi ledger. QA vẫn chạy gate (không đổi thành chỉ đọc biên nhận).
# 13/11 (chủ repo bỏ Grok): approved-by / edited-tests không còn nhận reviewer grok, không còn chỉ `agent=grok`. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="${RUN_MD:-$ROOT/.claude/skills/super-board/references/run.md}"
PRE="${PREAMBLE_MD:-$ROOT/.claude/skills/super-build/references/worker-preamble.md}"
DOC="${FACTORY_MD:-$ROOT/universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md}"
QAF="${FINDINGS_MD:-$ROOT/.claude/skills/super-qa/references/findings-and-green.md}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

for f in "$RUN" "$PRE" "$DOC" "$QAF"; do [ -f "$f" ] || { echo "✖ thiếu $f"; exit 1; }; done

# Dòng "After the audit pass" của bước 5 Reviewer (Reviewer-side test rerun).
REV="$(awk '/\*\*Reviewer-side test rerun\*\*/{on=1} on && /Tests green/{exit} on' "$RUN")"
AFTER="$(printf '%s\n' "$REV" | grep -F -- '- After the audit pass')"
[ -n "$AFTER" ] || { echo "✖ run.md: không thấy dòng 'After the audit pass' của bước 5 Reviewer"; exit 1; }

has "$AFTER" 'agent-kit approve-tests' && ok "Reviewer ghi ledger bằng agent-kit approve-tests" \
  || fail "Reviewer chưa ghi ledger bằng agent-kit approve-tests"
has "$AFTER" 'verdicts.audit.reviewer' && ok "ledger lấy reviewer từ verdicts.audit.reviewer của PM" \
  || fail "dòng duyệt không nói reviewer lấy từ verdicts.audit.reviewer"
has "$AFTER" '.claude/bin/super-board-gate-receipt.sh <head sha40>' && ok "Reviewer đọc biên nhận theo head" \
  || fail "Reviewer không đọc biên nhận bằng super-board-gate-receipt.sh <head sha40>"
has "$AFTER" 'Skip the rerun only when' && has "$AFTER" 'an exit 0 receipt for this exact head and fingerprint' \
  && ok "chỉ bỏ chạy lại khi có biên nhận exit 0 đúng head + fingerprint" \
  || fail "điều kiện bỏ chạy lại không phải 'biên nhận exit 0 đúng head + fingerprint'"
has "$AFTER" 'tree_fp.py' && ok "fingerprint so với cây hiện tại (tree_fp.py)" || fail "không so fingerprint với cây hiện tại"
has "$AFTER" 'carried_from' && has "$AFTER" 'read-only run writes no receipt' \
  && ok "nêu bản chép carried_from và lượt read-only không tính" || fail "không nêu carried_from / read-only"
has "$AFTER" 'the commit the gate ran on' && has "$AFTER" 'git merge --no-edit origin/<base>' \
  && ok "head = commit đã gate, kể cả sau khi QA merge base" || fail "không nói head là commit đã gate sau merge base của QA"
has "$AFTER" 'post-fix-gate.py --run-tests --scoped --brief' && has "$AFTER" 'once' \
  && ok "chưa có biên nhận thì vẫn chạy một lần --run-tests --scoped" || fail "mất lệnh chạy lại --run-tests --scoped khi chưa có biên nhận"
if printf '%s\n' "$REV" | grep -q -- 'post-fix-gate.py --run-tests --brief'; then
  fail "bước 5 Reviewer còn lệnh chạy lại không --scoped"
else ok "bước 5 Reviewer không còn lệnh chạy lại không --scoped"; fi
# thứ tự: ghi ledger, rồi đọc biên nhận, rồi mới (nếu cần) chạy gate
pos() { printf '%s' "$AFTER" | awk -v n="$1" '{ i = index($0, n); if (i) { print i; exit } } END { }'; }
p1=$(pos 'agent-kit approve-tests'); p2=$(pos 'super-board-gate-receipt.sh <head sha40>'); p3=$(pos 'post-fix-gate.py --run-tests --scoped --brief')
if [ -n "$p1" ] && [ -n "$p2" ] && [ -n "$p3" ] && [ "$p1" -lt "$p2" ] && [ "$p2" -lt "$p3" ]; then
  ok "thứ tự: ledger, biên nhận, rồi gate scoped"
else fail "thứ tự sai (ledger=$p1 biên nhận=$p2 gate=$p3)"; fi

# QA vẫn chạy gate: bước pipeline QA, bước 4c QA và findings-and-green.md
QAPIPE="$(grep -F 'Run `git merge --no-edit origin/<base>`, the card' "$RUN")"
QA4C="$(grep -F '4c. **Target tests + impacted gate on the merged base' "$RUN")"
has "$QAPIPE" 'post-fix-gate.py --run-tests --scoped --brief --json' && ! has "$QAPIPE" 'gate-receipt' \
  && ok "pipeline QA vẫn chạy gate scoped" || fail "pipeline QA không còn chạy gate scoped"
has "$QA4C" 'post-fix-gate.py --run-tests --scoped --brief --json' && ! has "$QA4C" 'gate-receipt' \
  && ok "QA 4c vẫn chạy gate scoped" || fail "QA 4c không còn chạy gate scoped"
grep -qF 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief' "$QAF" \
  && ok "findings-and-green.md: QA vẫn chạy gate scoped" || fail "findings-and-green.md mất gate scoped của QA"

# 13/11: không bản chép nào của khối pipeline còn nhận reviewer grok hay chỉ `agent=grok`; approved-by ký reviewer antigravity
for f in "$RUN" "$PRE" "$DOC"; do
  t="$(cat "$f")"
  if ! has "$t" '"reviewer":"grok"' && ! has "$t" 'agent=grok' && ! has "$t" 'Antigravity or Grok audit' && has "$t" '"reviewer":"antigravity"'; then
    ok "$(basename "$f"): approved-by chỉ reviewer antigravity, không Grok"
  else fail "$(basename "$f"): approved-by còn nhận Grok"; fi
done
BEF="$(awk '/\*\*Before the gate, post the approval\*\*/,/The runner reads the latest/' "$RUN")"
! has "$BEF" '"reviewer":"grok"' && has "$BEF" '"reviewer":"antigravity"' && ok "trước merge gate: approved-by chỉ antigravity" \
  || fail "trước merge gate: approved-by còn nhận grok"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
