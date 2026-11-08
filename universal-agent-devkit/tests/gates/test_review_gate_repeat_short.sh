#!/usr/bin/env bash
# Chủ repo 08/11: Stop hook REVIEW-GATE in lại nguyên ~15 dòng giải thích mỗi lần dừng ("spam lắm và dài vậy").
# Cùng thông điệp lần thứ hai trong một phiên: giữ dòng ⛔ (yêu cầu), lệnh cần chạy và danh sách file, bỏ phần giải thích
# (như test_evidence_gate.sh O4). Phiên khác hay thông điệp đổi thì in đủ.
#  R1. lần đầu: đủ giải thích.
#  R2. lần hai cùng phiên, cùng code: ngắn hơn, còn ⛔, còn lệnh ocr-review, còn file, có dòng "Như lần chặn trước".
#  R3. phiên khác: lại đủ giải thích.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*) echo "Error: resolve LLM endpoint: no valid LLM endpoint configured" >&2; exit 1 ;;
  "delegate preview") printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"app.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0 ;;
  "delegate rule") printf '{"schema_version":"1","groups":[{"group_id":1,"files":["app.py"],"rule":"ZeroDivisionError"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys
kind, tr = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
tu = lambda b: {"type": "assistant", "message": {"role": "assistant", "content": [dict(b, type="tool_use")]}}
if kind == "edit":
    e = tu({"id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}})
else:
    e = tu({"id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}})
open(tr, "a").write(json.dumps(e) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" CLAIM_MAX=9 bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$2"; }

: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer   # agent review, thiếu OCR
stop a "$TMP/e1"; rc1=$?
stop a "$TMP/e2"; rc2=$?
stop b "$TMP/e3"; rc3=$?
n1=$(wc -l < "$TMP/e1" | tr -d ' '); n2=$(wc -l < "$TMP/e2" | tr -d ' '); n3=$(wc -l < "$TMP/e3" | tr -d ' ')

[ "$rc1" = 2 ] && grep -q 'hai bên tìm ra lỗi khác nhau' "$TMP/e1" \
  && ok "R1. lần đầu: chặn (rc 2), đủ giải thích ($n1 dòng)" || fail "R1. rc $rc1, $n1 dòng: $(head -3 "$TMP/e1" | tr '\n' ' ')"
if [ "$rc2" = 2 ] && [ "$n2" -lt "$n1" ] && ! grep -q 'hai bên tìm ra lỗi khác nhau' "$TMP/e2" \
   && grep -q '^⛔ REVIEW-GATE' "$TMP/e2" && grep -q 'ocr-review' "$TMP/e2" && grep -q 'app.py' "$TMP/e2" \
   && grep -q 'Như lần chặn trước' "$TMP/e2" && grep -q -- '--out viết thẳng' "$TMP/e2" && grep -q '| tail' "$TMP/e2"; then
  ok "R2. lần hai cùng phiên: ngắn ($n2 < $n1 dòng), còn ⛔ + lệnh + file"
else fail "R2. rc $rc2, $n2 dòng (lần đầu $n1): $(cat "$TMP/e2" | head -6 | tr '\n' '|')"; fi
[ "$rc3" = 2 ] && grep -q 'hai bên tìm ra lỗi khác nhau' "$TMP/e3" \
  && ok "R3. phiên khác: đủ giải thích ($n3 dòng)" || fail "R3. rc $rc3, $n3 dòng"

# R4 (review PR #1059, P2): đường chặn thường (chưa có review nào): bản ngắn vẫn giữ các lựa chọn A–D (lệnh cần chạy).
: > "$TR"; ev edit t1 "$P/app.py"
stop c "$TMP/e4"; stop c "$TMP/e5"; rc5=$?
n4=$(wc -l < "$TMP/e4" | tr -d ' '); n5=$(wc -l < "$TMP/e5" | tr -d ' ')
if [ "$rc5" = 2 ] && [ "$n5" -lt "$n4" ] && grep -q 'A) Agent principal-code-reviewer' "$TMP/e5" && grep -q 'Như lần chặn trước' "$TMP/e5"; then
  ok "R4. chặn thường lặp lại: ngắn ($n5 < $n4 dòng), còn lựa chọn A–D"
else fail "R4. rc $rc5, $n5 dòng (lần đầu $n4): $(cat "$TMP/e5" | tr '\n' '|')"; fi

[ "$FAILS" = 0 ] && { echo "test_review_gate_repeat_short: PASS"; exit 0; }
echo "test_review_gate_repeat_short: FAIL ($FAILS)"; exit 1
