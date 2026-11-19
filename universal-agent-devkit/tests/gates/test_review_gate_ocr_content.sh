#!/usr/bin/env bash
# hooks/review_gate.sh + report OCR (content map `content_sha256`/`content_base`, wave 2 lane D 03/11; luật mtime trước đó).
# #1332 (lỗ P2 PR #1335): LLM của OCR đã gỡ, bin/ocr-review không còn in `mode: review` và không ghi report hay content map —
# một report OCR mà gate đọc được giờ chỉ có thể do agent tự viết. Gate không còn tính report nào (có map hay không, workspace hay
# range, delta hay content_excluded) là review: mọi ca từng qua bằng report nay bị giữ (rc 2). Đường delegate (spec của chính lượt
# chạy + agent review sau nó): tests/gates/test_review_gate_ocr_delegate_credit.sh và test_review_gate_ocr.sh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# fake ocr on PATH (OCR is then REQUIRED by the gate): no LLM endpoint, the delegation the block path runs works
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*) echo "Error: resolve LLM endpoint: no valid LLM endpoint configured" >&2; exit 1 ;;
  "delegate preview") printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"a.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0 ;;
  "delegate rule") printf '{"schema_version":"1","groups":[{"group_id":1,"files":["a.py"],"rule":"x"}]}\n'; exit 0 ;;
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
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}}]}}
elif kind == "agent":
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}}]}}
elif kind == "bash":
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}]}}
elif kind == "result":
    e = {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": a[0], "is_error": False, "content": a[1]}]}}
with open(tr, "a") as f:
    f.write(json.dumps(e) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
# ocr <tool id> <report> [helper args…]: an ocr-review run in review mode that named <report>
ocr_run() { local id="$1" rp="$2"; shift 2; ev bash "$id" ".agents/devkit/bin/ocr-review $* --out $(dirname "$rp")"
  ev result "$id" "$(printf 'mode: review\nreport: %s' "$rp")"; }
# rep <file> <repo> <base> <ws|HEAD> <path=content-source>… : an OCR report whose map holds, for each path, the sha256 of the
# working-tree file (ws) or of the blob at HEAD; "path=@hex" puts that literal sha; "-" as base leaves the map out (old report)
rep() { python3 - "$@" <<'PY'
import hashlib, json, os, subprocess, sys
out, repo, base, src = sys.argv[1:5]
m = {}
for kv in sys.argv[5:]:
    p, _, v = kv.partition("=")
    if v.startswith("@"):
        m[p] = v[1:]
    elif src == "ws":
        m[p] = hashlib.sha256(open(os.path.join(repo, p), "rb").read()).hexdigest()
    else:
        m[p] = hashlib.sha256(subprocess.run(["git", "-C", repo, "cat-file", "blob", "HEAD:" + p], capture_output=True, check=True).stdout).hexdigest()
d = {"status": "complete", "summary": {"files_reviewed": len(m) or 1}, "comments": []}
if base != "-":
    d["content_sha256"] = m
    d["content_base"] = base
os.makedirs(os.path.dirname(out), mode=0o700, exist_ok=True)
with open(out, "w") as fh:
    json.dump(d, fh)
PY
}
# age <seconds from now> <file>… : set mtimes (never left to the clock: a 1 s filesystem gives two writes one mtime)
age() { local s="$1"; shift; python3 -c 'import os,sys,time; t=time.time()+float(sys.argv[1]); [os.utime(f,(t,t)) for f in sys.argv[2:]]' "$s" "$@"; }
sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# ── workspace scope: repo P, a.py and b.py new (untracked), nothing committed since the verified head ──
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > x.txt && git add x.txt && git commit -qm i)
PH="$(git -C "$P" rev-parse HEAD)"
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$TR" "$P" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
reset_ws() { printf 'def a(x):\n    return x\n' > "$P/a.py"; printf 'def b(x):\n    return 1 / x\n' > "$P/b.py"; }

# #1332: mọi report dưới đây — kể cả map khớp sha, delta, content_excluded, report không map mới hơn mọi file — từng cho qua (rc 0).
# Giờ chúng chỉ có thể do agent tự viết, nên đều bị giữ (rc 2) dù đã có agent review sau lần sửa cuối.
# (a) R1 maps a.py+b.py; b.py edited then put back to the same bytes; the agent ran after
reset_ws; rep "$TMP/r1/ocr-review.json" "$P" "$PH" ws a.py b.py
age -300 "$P/a.py"; age -200 "$TMP/r1/ocr-review.json"; age 0 "$P/b.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"; ev agent t5 principal-code-reviewer
stop a1; rc=$?
[ "$rc" = 2 ] && ok "(a) a workspace map whose sha matches: no longer counted (rc 2)" || fail "(a) a content-mapped report counted (rc $rc)"

# (b) R1 maps a.py+b.py; R2 (another --out) maps the new b.py only: the delta run is no review either
reset_ws; rep "$TMP/r1/ocr-review.json" "$P" "$PH" ws a.py b.py
printf 'def b(x):\n    return 2 / x if x else 0\n' > "$P/b.py"; rep "$TMP/r2/ocr-review.json" "$P" "$PH" ws b.py
age -400 "$TMP/r1/ocr-review.json"; age -300 "$P/b.py"; age -200 "$TMP/r2/ocr-review.json"; age 0 "$P/a.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"
ocr_run t5 "$TMP/r2/ocr-review.json"; ev edit t6 "$P/a.py"; ev agent t7 principal-code-reviewer
stop b1; rc=$?
[ "$rc" = 2 ] && ok "(b) a delta map run: no longer counted (rc 2)" || fail "(b) a delta map report counted (rc $rc)"

# (e) content_excluded of a run after the last edit: no longer exempts anything
reset_ws; echo "var x = 1" > "$P/x.min.js"; rep "$TMP/r9/ocr-review.json" "$P" "$PH" ws a.py
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["content_excluded"]=["x.min.js"]; json.dump(d,open(sys.argv[1],"w"))' "$TMP/r9/ocr-review.json"
age -300 "$P/a.py" "$P/x.min.js"; age 0 "$TMP/r9/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/x.min.js"; ocr_run t3 "$TMP/r9/ocr-review.json"; ev agent t4 principal-code-reviewer
stop e1; rc=$?
[ "$rc" = 2 ] && ok "(e) content_excluded in a report: no longer counted (rc 2)" || fail "(e) content_excluded report counted (rc $rc)"
rm -f "$P/x.min.js"

# (d) a report without the map, newer than every edit (the old mtime rule): no longer counted
reset_ws; rep "$TMP/r4/ocr-review.json" "$P" - ws
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r4/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r4/ocr-review.json"
stop d1; rc=$?
[ "$rc" = 2 ] && ok "(d) a map-less report newer than every edit: no longer counted (rc 2)" || fail "(d) map-less fresh report counted (rc $rc)"

# G6 (review 03/11): a report nested too deep for json: the gate does not crash (a crash lets the Stop through) and blocks
reset_ws; mkdir -p "$TMP/r11"; python3 -c 'import sys; open(sys.argv[1],"w").write("["*200000 + "]"*200000)' "$TMP/r11/ocr-review.json"
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r11/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r11/ocr-review.json"
stop g6; rc=$?
[ "$rc" = 2 ] && ! grep -q "RecursionError\|Traceback" "$TMP/err" && ok "G6: a deeply nested report: no crash, blocked (rc 2)" \
  || fail "G6: deeply nested report crashed or passed (rc $rc)"

# ── range scope: repo C, app.py committed after the verified head ──
C="$TMP/c"; mkdir -p "$C/.claude/audit-gate"; (cd "$C" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo "def g(x): return x" > app.py && git add app.py && git commit -qm i)
VH="$(git -C "$C" rev-parse HEAD)"
printf '{"verified_head": "%s"}\n' "$VH" > "$C/.claude/audit-gate/regression_gate.state.json"
echo "def g(x): return 2 / x" > "$C/app.py" && git -C "$C" commit -qam "committed before any review"
CH="$(git -C "$C" rev-parse HEAD)"
crun() { printf '{"session_id":"s-%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$TR" "$C" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$C" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
# (r) a range map over the committed code (blob at HEAD), from a run that covers the verified head: no longer counted
rep "$TMP/r6/ocr-review.json" "$C" "$VH" HEAD app.py; age 0 "$C/app.py"; age -300 "$TMP/r6/ocr-review.json"
: > "$TR"; ocr_run t1 "$TMP/r6/ocr-review.json" --from "$VH" --to HEAD; ev edit t2 "$C/app.py"; ev agent t3 principal-code-reviewer
crun r1; rc=$?
[ "$rc" = 2 ] && grep -q -- "--from" "$TMP/err" && ok "(r) a range map matching the HEAD blob: no longer counted, the --from run is asked (rc 2)" \
  || fail "(r) a range map report counted (rc $rc)"
# committed + dirty: a range map and a workspace map, both matching: no longer counted
echo "def g(x): return 3 / x if x else 0" > "$C/app.py"; rep "$TMP/r7/ocr-review.json" "$C" "$CH" ws app.py
age -300 "$TMP/r6/ocr-review.json" "$TMP/r7/ocr-review.json"; age 0 "$C/app.py"
: > "$TR"; ocr_run t1 "$TMP/r6/ocr-review.json" --from "$VH" --to HEAD; ocr_run t2 "$TMP/r7/ocr-review.json"; ev edit t3 "$C/app.py"
ev agent t4 principal-code-reviewer
crun r3; rc=$?
[ "$rc" = 2 ] && ok "(r) committed + dirty with both maps matching: no longer counted (rc 2)" || fail "(r) both content maps counted (rc $rc)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
