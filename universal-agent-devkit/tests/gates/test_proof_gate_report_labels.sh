#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh reads the 4-item acceptance report by its LABELS, and the labels it knew were narrower than
# the rule's own wording. Replay of the Stop blocks of 7 days of real transcripts (scripts/governance/stop_replay.py, 2026-10-14):
# 11 replies carried all four items as a numbered list and were blocked for "thiếu 3" or "thiếu 1,3" - the agent had written
# "3. Nguy cơ mới", "1. Đã làm gì", "1. Đã thay đổi gì", "2. Chặn lỗi cũ", "3. Nguy cơ lỗi mới", and core-rules.md section 2.3 itself says
# "Đã fix được gì" / "bug cũ nào" / "Nguy cơ bug mới nào". Each block cost the agent a whole round to rename a label.
# Two-way: those labels now pass; a reply that really lacks an item (or has "Rủi ro còn lại", the residual risk, which is another
# item) still blocks and the log names the missing number.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$ROOT/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t \
  && echo "x" > a.txt && git add -A && git commit -qm init ) || { echo "fixture repo failed"; exit 1; }

# A push turn: the report is checked on the final reply (a push turn that does not open with XONG is checked for the report only).
cat > "$ROOT/turn.py" <<'PY'
import datetime, json, sys
tr = sys.argv[1]
base = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=200)
def at(off):
    return (base + datetime.timedelta(seconds=off)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
rows = [
    {"type": "user", "timestamp": at(0), "message": {"role": "user", "content": "đẩy lên origin"}},
    {"type": "assistant", "timestamp": at(10), "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "p1", "name": "Bash", "input": {"command": "git push origin main"}}]}},
    {"type": "user", "timestamp": at(11), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "p1", "is_error": False, "content": "To github.com:x/y.git\n   86f7ddc..a94c071  main -> main"}]}},
]
with open(tr, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

N=0
LOG="$REPO/.claude/audit-gate/proof_gate.log"
# check <want rc> <label> <reply> [<want log fragment>]
check() {
  local want="$1" label="$2" reply="$3" frag="${4:-}" rc line
  N=$((N + 1))
  python3 "$ROOT/turn.py" "$ROOT/t$N.jsonl"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-lbl-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$ROOT/t$N.jsonl" "$reply" "$N" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$ROOT/out" 2>"$ROOT/err"
  rc=$?
  grep -q Traceback "$ROOT/err" && rc=99
  line="$(grep "block session=s-lbl-$N " "$LOG" 2>/dev/null | tail -1)"
  if [ "$rc" != "$want" ]; then fail "$label: rc $rc (want $want) $line"; return; fi
  if [ -n "$frag" ]; then
    case "$line" in *"$frag"*) ok "$label: rc $rc, log has '$frag'" ;; *) fail "$label: rc $rc but the log lacks '$frag': '$line'" ;; esac
  else
    ok "$label: rc $rc"
  fi
}

TAIL4="4. An toàn mã nguồn: không secret, không placeholder."

# the labels real agents wrote, and the rule's own wording: all four items present, so the push turn passes
check 0 "Nguy cơ mới (no 'bug')" "Đã push lên origin/main.
1. Đã fix gì: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ mới: đã rà caller, không tác dụng phụ.
$TAIL4"
check 0 "Đã làm gì" "Đã push.
1. Đã làm gì: đổi tên một trang tài liệu.
2. Chặn bug cũ: không đụng mã.
3. Nguy cơ bug mới: không có thay đổi hành vi.
$TAIL4"
check 0 "Đã thay đổi gì" "Đã push.
1. **Đã thay đổi gì:** nối test gác.
2. **Chặn bug cũ:** hồi quy PASS.
3. **Nguy cơ bug mới:** không.
4. **An toàn mã nguồn:** sạch."
check 0 "lỗi cũ / lỗi mới" "Đã push.
1. Đã sửa gì: một lỗi.
2. Chặn lỗi cũ: 8 test mới.
3. Nguy cơ lỗi mới: reviewer độc lập đã rà.
4. An toàn mã: không secret."
check 0 "core-rules 2.3 wording, no English gloss" "Đã push.
1. Đã fix được gì: lỗi A.
2. Đã chặn đứng bug cũ nào: REG-2.
3. Nguy cơ bug mới nào đã triệt tiêu: đã rà caller.
4. Trạng thái an toàn mã nguồn: sạch."

# controls: a report that lacks an item is still a block, and the log names the number
check 2 "item 3 missing" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
$TAIL4" "report=3 "
check 2 "residual risk is not the new-bug risk" "Đã push.
1. Đã làm gì: một việc.
2. Chặn bug cũ: không.
3. Rủi ro còn lại: một việc chưa đo.
$TAIL4" "report=3 "
check 2 "only one label" "Đã push.
1. Đã làm gì: một việc." "report=2,3,4 "
# the new words in ORDINARY PROSE are no labels: a label is followed by its colon (OCR review 14/10: "Rủi ro còn lại: không có rủi ro mới"
# passed item 3 when the variants were bare words)
check 2 "residual risk that mentions 'rủi ro mới' in prose" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
3. Rủi ro còn lại: không có rủi ro mới.
$TAIL4" "report=3 "
check 2 "prose with the words but no report" "Đã push. Đã thay đổi tên một trang; không phát sinh lỗi mới; lỗi cũ vẫn bị chặn; an toàn mã OK." "report=1,2,3 "
# the phrase must be IN the label (principal-code-reviewer 14/10): after another label's colon, or after a comma, it is the content of
# another item, not an item
check 2 "'lỗi cũ' is the content of item 1, not item 2" "Đã push.
1. Đã fix gì: lỗi cũ của parser, nguyên nhân: off-by-one.
3. Nguy cơ bug mới: không.
$TAIL4" "report=2 "
check 2 "'lỗi mới' is the content of item 1, not item 3" "Đã push.
1. Đã fix gì: lỗi mới phát hiện ở parser, RED→GREEN: test_x.
2. Chặn bug cũ: REG-1.
$TAIL4" "report=3 "
check 2 "residual risk with a second label" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
3. Rủi ro còn lại: không có rủi ro mới; lý do: diff nhỏ.
$TAIL4" "report=3 "
check 2 "residual risk, prose before its colon" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
3. Rủi ro còn lại: không thấy lỗi mới, lưu ý: chưa đo hiệu năng.
$TAIL4" "report=3 "
check 2 "'đã fix được gì đó' in prose is not item 1" "Đã push. Tôi đã fix được gì đó trong parser.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: không.
$TAIL4" "report=1 "
check 2 "'đã thay đổi gì' in prose is not item 1" "Đã push. Để biết commit đã thay đổi gì, xem git log.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: không.
$TAIL4" "report=1 "
check 2 "an indented sub-bullet is content, not item 3" "Đã push.
1. Đã fix gì:
   - Nguy cơ mới: crash khi mở file rỗng.
2. Chặn bug cũ: REG-1.
$TAIL4" "report=3 "
check 2 "label-shaped line with no colon is no label" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
Không có nguy cơ mới nào.
$TAIL4" "report=3 "
check 2 "'Lỗi cũ:' alone is content, not the label 'Chặn lỗi cũ:'" "Đã push.
1. Đã fix gì:
Lỗi cũ: parser crash khi mở file rỗng.
3. Nguy cơ bug mới: không.
$TAIL4" "report=2 "
check 2 "prose with a colon at line start is not item 1" "Đã push.
Muốn biết đã thay đổi gì: xem git log.
2. Chặn bug cũ: REG-1.
3. Nguy cơ bug mới: không.
$TAIL4" "report=1 "
check 2 "a comma before the phrase: prose, not a label" "Đã push.
1. Đã fix gì: lỗi X.
2. Chặn bug cũ: REG-1.
3. OK, nguy cơ mới vẫn chặn: không.
$TAIL4" "report=3 "
# labels with a parenthesis (a list, a gloss) before their colon are labels
check 0 "label with a parenthesis" "Đã push.
1. Đã làm gì (RED→GREEN): một việc.
2. Chặn lỗi cũ (REG-1, REG-2): PASS.
3. Nguy cơ lỗi mới (v.v.): không.
$TAIL4"
check 2 "'Đã làm:' in prose is not item 1" "Đã push.
Việc đã làm: một việc.
2. Chặn bug cũ: không.
3. Nguy cơ bug mới: không.
$TAIL4" "report=1 "
check 2 "no report at all" "Đã push lên origin/main (a94c071)." "report=1,2,3,4 "

# the heading the rule words ("Đã fix được gì", core-rules 2.3) is an acceptance-report heading, never an outcome claim: the evidence gate
# (check 7) already exempts "Đã fix gì" and "What was fixed" for that reason, and must exempt the longer form the same way
TE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TE_REPO="$ROOT/te"; mkdir -p "$TE_REPO"; git -C "$TE_REPO" init -q .
: > "$ROOT/te.jsonl"
te_check() {   # te_check <want rc> <label> <reply>
  local want="$1" label="$2" reply="$3" rc
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-lbl-"+sys.argv[3],"transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$ROOT/te.jsonl" "$reply" "$N" | CLAUDE_PROJECT_DIR="$TE_REPO" bash "$TE" >/dev/null 2>"$ROOT/te_err"
  rc=$?
  grep -q Traceback "$ROOT/te_err" && rc=99
  if [ "$rc" = "$want" ]; then ok "$label: evidence gate rc $rc"; else fail "$label: evidence gate rc $rc (want $want)"; fi
}
te_check 0 "heading 'Đã fix được gì'" "1. Đã fix được gì: tên lỗi, nguyên nhân gốc, cặp ĐỎ và XANH.
2. Đã chặn đứng bug cũ nào: không."
te_check 2 "a claim after the heading is still a claim" "1. Đã fix được gì: lỗi X. Đã fix lỗi X rồi."
te_check 2 "a claim written as the heading's answer is still a claim" "Đã fix được gì: đã fix lỗi tràn bộ nhớ."
te_check 2 "'được gì đó' is an indefinite claim, not the heading" "Tôi đã fix được gì đó trong parser."
te_check 0 "heading in bold, colon after the closing bold" "1. **Đã fix được gì**: tên lỗi, nguyên nhân gốc.
2. **Đã chặn đứng bug cũ nào**: không."
te_check 0 "the fixbugs skill's own wording: headings joined by ;" "(1) Đã fix được gì; (2) Đã chặn đứng bug cũ nào; (3) Nguy cơ bug mới nào."

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
