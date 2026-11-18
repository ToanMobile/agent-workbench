#!/usr/bin/env bash
# #1332: LLM của OCR bị gỡ hẳn, bin/ocr-review luôn ra `mode: delegate` + `spec:` mà không còn dòng lỗi LLM endpoint.
# hooks/review_gate.sh phải ghi nhận lượt delegate đó (spec hợp lệ trong thư mục --out của chính lượt chạy) + một agent review sau nó
# là đủ — không đòi chuỗi "no valid LLM endpoint configured" / "LLM endpoint unusable". Không nới chỗ khác: thiếu agent review sau spec,
# hay lượt --delegate-only (gate tự chạy), vẫn bị giữ; block message không còn nhắc LLM endpoint.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

# ocr giả: chỉ delegation (OCR bắt buộc vì `ocr` có trên PATH)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
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
if kind == "edit":
    c = {"type": "tool_use", "id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}}
elif kind == "agent":
    c = {"type": "tool_use", "id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}}
elif kind == "bash":
    c = {"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}
else:
    c = {"type": "tool_result", "tool_use_id": a[0], "is_error": a[1] == "err", "content": a[2]}
role = "user" if kind == "result" else "assistant"
with open(tr, "a") as f:
    f.write(json.dumps({"type": role, "message": {"role": role, "content": [c]}}) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$TR" "$P" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }

# spec thật do lượt delegate tạo (thư mục --out riêng 0700), mới hơn app.py; output đúng như ocr-review mới in, không dòng LLM
mkdir -p "$TMP/spec"; chmod 700 "$TMP/spec"; echo "# OCR review spec" > "$TMP/spec/ocr-spec.md"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()-60,)*2); os.utime(sys.argv[2],(time.time()+5,)*2)' "$P/app.py" "$TMP/spec/ocr-spec.md"
OUT="$(printf 'mode: delegate\nspec: %s\nnext: give this spec to a fresh-context reviewer (Agent tool); its findings are the OCR review' "$TMP/spec/ocr-spec.md")"

# 1. delegate (không chuỗi LLM) + agent review sau nó: qua
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok "$OUT"
ev agent t4 principal-code-reviewer
stop a; rc=$?
[ "$rc" = 0 ] && ok "delegate không chuỗi LLM + agent review sau nó: qua (rc 0)" || fail "delegate không chuỗi LLM bị giữ (rc $rc): $(head -3 "$TMP/err")"
# 2. cùng lượt delegate nhưng không có agent review sau nó: vẫn giữ
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok "$OUT"
stop b; rc=$?
[ "$rc" = 2 ] && ok "  … không có agent review sau spec: vẫn giữ (rc 2)" || fail "delegate một mình được tính (rc $rc)"
# 3. agent review TRƯỚC lượt delegate (không ai đọc spec): vẫn giữ
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok "$OUT"
stop c; rc=$?
[ "$rc" = 2 ] && ok "  … agent review trước lượt delegate: vẫn giữ (rc 2)" || fail "delegate sau agent review được tính (rc $rc)"
# 4. --delegate-only (đường gate tự chạy) vẫn không tính
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --delegate-only --out $TMP/spec"; ev result t3 ok "$OUT"
ev agent t4 principal-code-reviewer
stop d; rc=$?
[ "$rc" = 2 ] && ok "  … --delegate-only vẫn không tính (rc 2)" || fail "--delegate-only được tính (rc $rc)"
# 5. lời nhắc của block không còn nhắc LLM endpoint
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer
stop e; rc=$?
[ "$rc" = 2 ] && ! grep -q 'LLM endpoint' "$TMP/err" && ok "  … block message không nhắc LLM endpoint (rc 2)" \
  || fail "block message còn nhắc LLM endpoint (rc $rc): $(grep 'LLM' "$TMP/err" | head -2)"
# 6. REVIEW_GATE_OCR=full (OCR review đầy đủ bằng LLM chạy nền) đã gỡ: không còn dựng thư mục full-* hay chạy nền
: > "$TR"; ev edit t1 "$P/app.py"
printf '{"session_id":"s-f","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$TR" "$P" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_OCR=full bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && ! ls -d "$P"/.git/ocr-review/full-* >/dev/null 2>&1 && ! grep -q 'LLM' "$TMP/err" \
  && ok "  … REVIEW_GATE_OCR=full: vẫn giữ, không dựng OCR review LLM chạy nền (rc 2)" \
  || fail "REVIEW_GATE_OCR=full còn chạy review LLM (rc $rc): $(ls -d "$P"/.git/ocr-review/full-* 2>&1 | head -1) $(grep 'LLM' "$TMP/err" | head -1)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
