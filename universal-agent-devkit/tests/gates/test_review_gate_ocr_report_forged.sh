#!/usr/bin/env bash
# #1332 (lỗ P2 PR #1335): bin/ocr-review không còn in `mode: review` và không ghi report/`content_sha256`; LLM của OCR đã gỡ.
# Một report OCR mà hooks/review_gate.sh đọc được giờ chỉ có thể do agent tự viết. Gate không được coi report đó là review:
# agent tự viết `{"comments":[]}` rồi in `mode: review` + `report:` (hoặc `ocr review -o <file> || true`, hoặc report có content map
# khớp sha) mà không có agent review nào — vẫn phải bị giữ (rc 2). Đường delegate do test_review_gate_ocr_delegate_credit.sh giữ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

# `ocr` có trên PATH: OCR bắt buộc; mọi lệnh khác ngoài delegation đều lỗi (không có LLM)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
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

# report do agent tự viết, mới hơn app.py (đúng luật mtime cũ)
R="$TMP/r.json"; echo '{"comments":[]}' > "$R"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()-60,)*2); os.utime(sys.argv[2],(time.time()+5,)*2)' "$P/app.py" "$R"
mkdir -p "$TMP/d"; chmod 700 "$TMP/d"

# 0. đối chứng: chỉ sửa code, không review: giữ
: > "$TR"; ev edit t1 "$P/app.py"
stop z; rc=$?
[ "$rc" = 2 ] && ok "đối chứng: chỉ sửa code bị giữ (rc 2)" || fail "đối chứng: chỉ sửa code mà qua (rc $rc)"
# 1. ocr-review rồi printf giả `mode: review` + `report:` trỏ report tự viết, không agent review: giữ
: > "$TR"; ev edit t1 "$P/app.py"
ev bash t2 "ocr-review --out $TMP/d; printf 'mode: review\\nreport: $R\\n'"
ev result t2 ok "$(printf 'mode: review\nreport: %s' "$R")"
stop a; rc=$?
[ "$rc" = 2 ] && ok "  … report tự viết qua 'mode: review' + 'report:' không được tính (rc 2)" \
  || fail "report tự viết qua 'mode: review' được tính là review (rc $rc)"
# 2. `ocr review -o <report tự viết> || true`, không agent review: giữ
: > "$TR"; ev edit t1 "$P/app.py"
ev bash t2 "ocr review -o $R || true"
ev result t2 ok ""
stop b; rc=$?
[ "$rc" = 2 ] && ok "  … 'ocr review -o <file> || true' không được tính (rc 2)" \
  || fail "'ocr review -o <file> || true' được tính là review (rc $rc)"
# 3. report tự viết kèm content map khớp sha hiện tại, không agent review: giữ
HEAD_SHA="$(git -C "$P" rev-parse HEAD)"
python3 -c 'import hashlib,json,sys; json.dump({"comments":[],"content_base":sys.argv[3],"content_sha256":{"app.py":hashlib.sha256(open(sys.argv[2],"rb").read()).hexdigest()}},open(sys.argv[1],"w"))' \
  "$TMP/m.json" "$P/app.py" "$HEAD_SHA"
: > "$TR"; ev edit t1 "$P/app.py"
ev bash t2 "ocr-review --out $TMP/d; printf 'mode: review\\nreport: $TMP/m.json\\n'"
ev result t2 ok "$(printf 'mode: review\nreport: %s' "$TMP/m.json")"
stop c; rc=$?
[ "$rc" = 2 ] && ok "  … report tự viết có content map không được tính (rc 2)" \
  || fail "report tự viết có content map được tính là review (rc $rc)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
