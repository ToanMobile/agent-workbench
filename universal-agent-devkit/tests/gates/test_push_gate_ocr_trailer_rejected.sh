#!/usr/bin/env bash
# #1332: LLM của OCR bị gỡ hẳn (chủ repo 19/11) — `Test-approved-by: ocr <uuid>` không còn là người duyệt chéo test sửa.
# Dựng đúng phiên mà luật cũ (#1258) chấp nhận: `ocr` giả trả phiên LLM range review hoàn tất của đúng head, rồi kiểm:
# push_gate.approved() từ chối trailer như giá trị lạ (sai dạng), post-fix-gate không tính nó, không còn ocr_review / công tắc.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1   # công tắc chỉ cho test: binary ocr giả dưới $TMP
export FAKE_OCR_DIR="$TMP/store"; mkdir -p "$FAKE_OCR_DIR" "$TMP/bin"
unset DEVKIT_OCR_CROSS_REVIEW DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID CLAUDECODE
cat > "$TMP/bin/ocr" <<'PY'
#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]
f = os.path.join(os.environ["FAKE_OCR_DIR"], f"{a[1]}-{a[-1]}.json") if len(a) > 2 and a[0] == "session" else ""
if not os.path.exists(f):
    sys.exit(1)
sys.stdout.write(open(f).read())
PY
chmod +x "$TMP/bin/ocr"
export DEVKIT_OCR_BIN="$TMP/bin/ocr"

R="$TMP/repo"; mkdir -p "$R/tests" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
git add -A && git commit -qm init && git update-ref refs/remotes/origin/main HEAD
git checkout -q -b pr
printf '#!/bin/sh\nexit 0\n' > tests/test_old.sh && git commit -qam "edit test"
HEAD_SHA="$(git rev-parse HEAD)"; BASE_SHA="$(git rev-parse origin/main)"
A=11111111-1111-4111-8111-111111111111
git commit -q --allow-empty -m "ocr trailer" -m "Test-approved-by: ocr $A"
TRAILER_SHA="$(git rev-parse HEAD)"
# phiên OCR LLM hợp lệ theo luật cũ: range, có model, hoàn tất, đúng head/base, bắt đầu sau commit head, phủ file test, không finding chặn
python3 - "$FAKE_OCR_DIR" "$R" "$HEAD_SHA" "$BASE_SHA" "$A" <<'PY'
import json, os, sys, time
d, repo, head, base, sid = sys.argv[1:]
cov = [{"path": "tests/test_old.sh", "item_id": "tests/test_old.sh", "fingerprint": "f"}]
man = {"run_id": sid, "terminal_state": "complete", "input": {"mode": "range", "resolved_base": base, "resolved_head": head},
       "coverage": {"selected": cov, "completed": cov, "reused": [], "failed": [], "waived": [], "excluded": []}}
summ = {"session_id": sid, "repo_dir": repo, "review_mode": "range", "model": "m-1", "legacy": False, "aborted": False,
        "start_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 300)), "completed_files": 1, "failed_files": 0,
        "llm_failures": 0, "total_comments": 0, "run_manifest": man}
json.dump({"summary": summ, "items": []}, open(os.path.join(d, f"show-{sid}.json"), "w"))
json.dump([], open(os.path.join(d, f"comments-{sid}.json"), "w"))
PY

# 1. approved(): trailer ocr bị từ chối như giá trị lạ (thông báo "sai dạng"), không đi qua phiên OCR nào
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.approved(sys.argv[2], sys.argv[3]))' \
  "$DEVKIT_DIR/bin" "$R" "$TRAILER_SHA^!" 2>&1 | tail -1)"
case "$got" in
  "(False,"*"sai dạng"*) ok "approved(): Test-approved-by: ocr <uuid> bị từ chối như giá trị lạ" ;;
  *) fail "approved() vẫn xét trailer ocr: $got" ;;
esac
# 2. regex chỉ còn antigravity; push_gate không còn ocr_review
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p
print(p.APPROVED_VALUE.fullmatch("ocr " + sys.argv[2]) is None, p.APPROVED_VALUE.fullmatch("antigravity T0001-x") is not None, hasattr(p, "ocr_review"))' \
  "$DEVKIT_DIR/bin" "$A" 2>&1 | tail -1)"
[ "$got" = "True True False" ] && ok "APPROVED_VALUE: chỉ antigravity; ocr_review đã gỡ" || fail "APPROVED_VALUE/ocr_review: $got"
# 3. post-fix-gate (_trailer_cross_review) không tính trailer ocr
cat > "$TMP/pfg.py" <<'PY'
import importlib.util, os, sys
sys.path.insert(0, sys.argv[1] + "/bin")
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1] + "/bin/post-fix-gate.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.chdir(sys.argv[2]); r = m._trailer_cross_review(["tests/test_old.sh"], sys.argv[2]); print(sorted(v[0] for v in r.values()))
PY
got="$(env CLAUDE_PROJECT_DIR="$R" python3 "$TMP/pfg.py" "$DEVKIT_DIR" "$R" 2>&1 | tail -1)"
[ "$got" = "[]" ] && ok "post-fix-gate: trailer ocr không duyệt test sửa" || fail "post-fix-gate vẫn tính trailer ocr: $got"
# 4. không còn công tắc DEVKIT_OCR_CROSS_REVIEW trong push_gate / post-fix-gate
if grep -q "DEVKIT_OCR_CROSS_REVIEW" "$DEVKIT_DIR/bin/push_gate.py" "$DEVKIT_DIR/bin/post-fix-gate.py"; then
  fail "còn DEVKIT_OCR_CROSS_REVIEW trong gate"
else
  ok "không còn DEVKIT_OCR_CROSS_REVIEW"
fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
