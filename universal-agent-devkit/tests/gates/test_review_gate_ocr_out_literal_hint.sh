#!/usr/bin/env bash
# Test hồi quy #992 (P3, phiên PR #993): `ocr-review --out $S/x` (biến shell) không được nhận là lượt OCR — _spec_from_run so thư mục
# của dòng `spec:` với CHỮ sau --out trong lệnh (rào chống spec làm tay, review 13/10), biến không khớp ⇒ gate chặn 3 lần dù OCR
# delegate đã chạy. Rào giữ nguyên; thông điệp chặn "thiếu OCR" nay nói --out phải là đường dẫn viết thẳng.
#  H1. sửa code + agent review, chưa có OCR ⇒ chặn (rc 2) và thông điệp có câu nhắc `--out` viết thẳng (không `$BIẾN`). Trước: không có.
#  H2. đối chứng rào: lượt `ocr-review --out $S/spec` (chữ `$S`) với output delegate thật vẫn KHÔNG tính (rc 2).
#  H3. đối chứng: cùng lượt với --out viết thẳng đường dẫn ⇒ tính, agent review sau nó ⇒ qua (rc 0).
# Không sửa tests/gates/test_review_gate_ocr*.sh (ca cũ). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

# ocr giả: delegate chạy được, `ocr review` báo thiếu endpoint (như tests/gates/test_review_gate_ocr.sh)
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
elif kind == "agent":
    e = tu({"id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}})
elif kind == "bash":
    e = tu({"id": a[0], "name": "Bash", "input": {"command": a[1]}})
else:
    e = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": a[0], "is_error": False, "content": a[1]}]}}
open(tr, "a").write(json.dumps(e) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
# thư mục spec như helper tạo (chmod 0700: _spec_from_run đòi thư mục riêng của lượt)
mkdir -p "$TMP/spec" && chmod 700 "$TMP/spec" && : > "$TMP/spec/ocr-spec.md"
FALLBACK="$(printf '%s\nmode: delegate\nspec: %s' "ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)" "$TMP/spec/ocr-spec.md")"

: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer
stop h1; rc=$?
if [ "$rc" = 2 ] && grep -q 'thiếu OCR\|BẮT BUỘC thêm một lượt OpenCodeReview' "$TMP/err" && grep -q -- '--out.*viết thẳng' "$TMP/err"; then
  ok "H1. chặn vì thiếu OCR (rc 2), thông điệp nhắc --out viết thẳng đường dẫn"
else fail "H1. rc $rc (mong 2) hoặc thiếu câu nhắc '--out … viết thẳng': $(grep -n 'OpenCodeReview\|--out' "$TMP/err" | head -4 | tr '\n' ' ')"; fi

: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 'S='"$TMP"'; python3 .agents/devkit/bin/ocr-review -b x --out $S/spec'; ev result t3 "$FALLBACK"
ev agent t4 principal-code-reviewer
stop h2; rc=$?
[ "$rc" = 2 ] && ok "H2. đối chứng rào: --out \$S/spec (biến) vẫn không tính (rc 2)" || fail "H2. --out \$S/spec được tính (rc $rc, mong 2)"

: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 "python3 .agents/devkit/bin/ocr-review -b x --out $TMP/spec"; ev result t3 "$FALLBACK"
ev agent t4 principal-code-reviewer
stop h3; rc=$?
[ "$rc" = 0 ] && ok "H3. đối chứng: --out viết thẳng + agent review sau nó ⇒ qua (rc 0)" || fail "H3. --out viết thẳng bị chặn (rc $rc, mong 0): $(tail -3 "$TMP/err" | tr '\n' ' ')"

[ "$FAILS" = 0 ] && { echo "test_review_gate_ocr_out_literal_hint: PASS"; exit 0; }
echo "test_review_gate_ocr_out_literal_hint: FAIL ($FAILS)"; exit 1
