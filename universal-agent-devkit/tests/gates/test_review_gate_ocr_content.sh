#!/usr/bin/env bash
# hooks/review_gate.sh + bin/ocr-review content map (wave 2 lane D, 03/11): an OCR report counted only when it was newer (mtime)
# than EVERY file the session edited, so any small edit — even one that put a file back exactly as it was — asked for a whole new
# OCR run. bin/ocr-review now writes `content_sha256` {path: sha256 of the content it reviewed} and `content_base` into its own
# JSON report. For a report that carries the map the gate judges by content: a session file whose current sha equals the sha in a
# report of the same scope (workspace: the working tree, base = HEAD; range: the HEAD blob, a run that covers the commits since the
# verified head) is reviewed; any other file is the delta and needs a run whose map has its current sha. The agent review rule
# (REVIEW_AGENTS after the last edit) does not change. A report without the map keeps the old mtime rule.
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

# (a) R1 maps a.py+b.py; b.py edited then put back to the same bytes (sha matches, mtime newer than R1); the agent ran after
reset_ws; rep "$TMP/r1/ocr-review.json" "$P" "$PH" ws a.py b.py
age -300 "$P/a.py"; age -200 "$TMP/r1/ocr-review.json"; age 0 "$P/b.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"; ev agent t5 principal-code-reviewer
stop a1; rc=$?
[ "$rc" = 0 ] && ok "(a) b.py edited back to the reviewed bytes, agent after the edit: the content-mapped OCR report still covers it (rc 0)" \
  || fail "(a) same content after the edit, report with matching map: rc $rc (want 0) $(grep -m1 REVIEW-GATE "$TMP/err")"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"
stop a2; rc=$?
[ "$rc" = 2 ] && ok "(a) … the same without an agent review after the last edit: still blocked, the agent rule is unchanged (rc 2)" \
  || fail "(a) no agent after the last edit passed (rc $rc): the map must not stand in for the agent review"

# (b) R1 maps a.py+b.py; b.py gets new bytes; R2 (another --out) maps b.py only, after that edit; a.py then edited back to R1's bytes
reset_ws; rep "$TMP/r1/ocr-review.json" "$P" "$PH" ws a.py b.py
printf 'def b(x):\n    return 2 / x if x else 0\n' > "$P/b.py"; rep "$TMP/r2/ocr-review.json" "$P" "$PH" ws b.py
age -400 "$TMP/r1/ocr-review.json"; age -300 "$P/b.py"; age -200 "$TMP/r2/ocr-review.json"; age 0 "$P/a.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"
ocr_run t5 "$TMP/r2/ocr-review.json"; ev edit t6 "$P/a.py"; ev agent t7 principal-code-reviewer
stop b1; rc=$?
[ "$rc" = 0 ] && ok "(b) delta run over b.py only (sha matches) + a.py back to R1's bytes: covered without a full re-run (rc 0)" \
  || fail "(b) delta OCR of b.py + a.py unchanged since R1: rc $rc (want 0) $(grep -m1 REVIEW-GATE "$TMP/err")"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r1/ocr-review.json"; ev edit t4 "$P/b.py"
ev agent t5 principal-code-reviewer
stop b2; rc=$?
[ "$rc" = 2 ] && ok "(b) … without the delta run: b.py's new bytes are in no map, blocked (rc 2)" || fail "(b) b.py delta unreviewed passed (rc $rc)"

# (c) what must still block
# c2: the map was edited by hand after the review (its sha is not b.py's content), report mtime fresh, after every edit
reset_ws; rep "$TMP/r3/ocr-review.json" "$P" "$PH" ws a.py "b.py=@$(printf '0%.0s' $(seq 64))"
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r3/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r3/ocr-review.json"
stop c2; rc=$?
[ "$rc" = 2 ] && ok "(c) a map whose sha does not match b.py (hand-edited after the review, fresh mtime): not counted (rc 2)" \
  || fail "(c) mismatched map sha counted (rc $rc)"
# c3: b.py is not in the map at all
reset_ws; rep "$TMP/r3/ocr-review.json" "$P" "$PH" ws a.py
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r3/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r3/ocr-review.json"
stop c3; rc=$?
[ "$rc" = 2 ] && ok "(c) b.py missing from the map of a fresh report: it is delta, blocked (rc 2)" || fail "(c) file absent from the map counted (rc $rc)"
# c4: a map that is not an object, and a workspace map recorded on another base
reset_ws; python3 -c 'import json,sys; json.dump({"status":"complete","comments":[],"content_sha256":"all","content_base":sys.argv[2]}, open(sys.argv[1],"w"))' \
  "$TMP/r3/ocr-review.json" "$PH"
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r3/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r3/ocr-review.json"
stop c4; rc=$?
[ "$rc" = 2 ] && ok "(c) a malformed content_sha256 (not an object): not counted, no fall back to mtime (rc 2)" || fail "(c) malformed map counted (rc $rc)"
reset_ws; rep "$TMP/r3/ocr-review.json" "$P" "0000000000000000000000000000000000000000" ws a.py b.py
age -300 "$P/a.py" "$P/b.py"; age -400 "$TMP/r3/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r3/ocr-review.json"; ev agent t4 principal-code-reviewer
stop c5; rc=$?
[ "$rc" = 2 ] && ok "(c) a workspace map whose base is not the current HEAD: not counted (rc 2)" || fail "(c) workspace map on another base counted (rc $rc)"
# a file OCR's own excludes leave out (x.min.js: default_path) can never be in a map: content_excluded drops it from the files asked
reset_ws; echo "var x = 1" > "$P/x.min.js"; rep "$TMP/r9/ocr-review.json" "$P" "$PH" ws a.py
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["content_excluded"]=["x.min.js"]; json.dump(d,open(sys.argv[1],"w"))' "$TMP/r9/ocr-review.json"
# (G4, review 03/11) content_excluded sits in a report the agent can write, so it alone never exempts a file: the run came after the
# last edit of x.min.js and its report is newer than every edited file (the old rule), so the excluded file is covered
age -300 "$P/a.py" "$P/x.min.js"; age 0 "$TMP/r9/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/x.min.js"; ocr_run t3 "$TMP/r9/ocr-review.json"; ev agent t4 principal-code-reviewer
stop e1; rc=$?
[ "$rc" = 0 ] && ok "a file OCR excludes by itself (content_excluded), run after its last edit: not asked of any map (rc 0)" || fail "OCR-excluded file held the gate (rc $rc)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["content_excluded"]="x.min.js"; json.dump(d,open(sys.argv[1],"w"))' "$TMP/r9/ocr-review.json"
age -300 "$TMP/r9/ocr-review.json"
stop e2; rc=$?
[ "$rc" = 2 ] && ok "  … content_excluded that is not a list: ignored, x.min.js is delta (rc 2)" || fail "malformed content_excluded honoured (rc $rc)"
# G4: x.min.js edited AFTER the run that excludes it (report older than the file): the exclusion does not stand for the new bytes
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["content_excluded"]=["x.min.js"]; json.dump(d,open(sys.argv[1],"w"))' "$TMP/r9/ocr-review.json"
age -300 "$P/a.py" "$TMP/r9/ocr-review.json"; age 0 "$P/x.min.js"
: > "$TR"; ev edit t1 "$P/a.py"; ocr_run t2 "$TMP/r9/ocr-review.json"; ev edit t3 "$P/x.min.js"; ev agent t4 principal-code-reviewer
stop g4a; rc=$?
[ "$rc" = 2 ] && grep -q "x.min.js" "$TMP/err" && ok "G4: an excluded file edited after the run (report older): old rule, blocked and named as delta (rc 2)" \
  || fail "G4: content_excluded exempted a file edited after the run (rc $rc)"
# G4: only the excluded file edited, OCR run after the edit with a fresh report, no agent review: the exclusion is no review mark
age -300 "$P/x.min.js"; age 0 "$TMP/r9/ocr-review.json"
: > "$TR"; ev edit t1 "$P/x.min.js"; ocr_run t2 "$TMP/r9/ocr-review.json"
stop g4e; rc=$?
[ "$rc" = 2 ] && ok "G4: an excluded file covered by the old rule does not stand in for the agent review (rc 2)" \
  || fail "G4: OCR exclusion alone passed without an agent review (rc $rc)"
# G4: a report edited by hand puts the dirty b.py into content_excluded; the map holds a.py; b.py edited after the run
reset_ws; rm -f "$P/x.min.js"; rep "$TMP/r10/ocr-review.json" "$P" "$PH" ws a.py
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["content_excluded"]=["b.py"]; json.dump(d,open(sys.argv[1],"w"))' "$TMP/r10/ocr-review.json"
age -300 "$P/a.py" "$TMP/r10/ocr-review.json"; age 0 "$P/b.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r10/ocr-review.json"; ev edit t4 "$P/b.py"; ev agent t5 principal-code-reviewer
stop g4b; rc=$?
[ "$rc" = 2 ] && grep -q "b.py" "$TMP/err" && ok "G4: b.py added to content_excluded by hand, edited after the run: not exempted (rc 2)" \
  || fail "G4: a hand-added content_excluded entry exempted a dirty session file (rc $rc)"
# … the same report with a fresh mtime but its run before b.py's last edit: the index half of the old rule still blocks
age 0 "$TMP/r10/ocr-review.json"; age -300 "$P/b.py"
stop g4c; rc=$?
[ "$rc" = 2 ] && ok "G4: … report mtime fresh, run before the last edit: still blocked (rc 2)" || fail "G4: excluded file credited by mtime alone (rc $rc)"
# … a run after the last edit, report older than b.py: the mtime half still blocks
age -300 "$TMP/r10/ocr-review.json"; age 0 "$P/b.py"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ocr_run t3 "$TMP/r10/ocr-review.json"; ev agent t4 principal-code-reviewer
stop g4d; rc=$?
[ "$rc" = 2 ] && ok "G4: … run after the last edit, report older than b.py: still blocked (rc 2)" || fail "G4: excluded file credited by index alone (rc $rc)"
# G6 (review 03/11): a report nested too deep for json (RecursionError), newer than every edit: not counted and the hook does not
# crash (the wrapper turns a crash into exit 0: the Stop went through unreviewed)
reset_ws; mkdir -p "$TMP/r11"; python3 -c 'import sys; open(sys.argv[1],"w").write("["*200000 + "]"*200000)' "$TMP/r11/ocr-review.json"
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r11/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r11/ocr-review.json"
stop g6; rc=$?
[ "$rc" = 2 ] && ! grep -q "RecursionError\|Traceback" "$TMP/err" && ok "G6: a deeply nested report: not counted, no crash, blocked (rc 2)" \
  || fail "G6: deeply nested report crashed or passed (rc $rc) $(grep -m1 'RecursionError' "$TMP/err")"

# control: an old report (no map) keeps the mtime rule: fresh after every edit passes, older than an edit blocks
reset_ws; rep "$TMP/r4/ocr-review.json" "$P" - ws
age -300 "$P/a.py" "$P/b.py"; age 0 "$TMP/r4/ocr-review.json"
: > "$TR"; ev edit t1 "$P/a.py"; ev edit t2 "$P/b.py"; ev agent t3 principal-code-reviewer; ocr_run t4 "$TMP/r4/ocr-review.json"
stop d1; rc=$?
[ "$rc" = 0 ] && ok "control: a report without the map, newer than every edit: old rule, counted (rc 0)" || fail "control: map-less fresh report rc $rc"
age -400 "$TMP/r4/ocr-review.json"
stop d2; rc=$?
[ "$rc" = 2 ] && ok "control: … the same report older than the edited files: old rule, not counted (rc 2)" || fail "control: map-less stale report rc $rc"

# ── range scope: repo C, app.py committed after the verified head ──
C="$TMP/c"; mkdir -p "$C/.claude/audit-gate"; (cd "$C" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo "def g(x): return x" > app.py && git add app.py && git commit -qm i)
VH="$(git -C "$C" rev-parse HEAD)"
printf '{"verified_head": "%s"}\n' "$VH" > "$C/.claude/audit-gate/regression_gate.state.json"
echo "def g(x): return 2 / x" > "$C/app.py" && git -C "$C" commit -qam "committed before any review"
CH="$(git -C "$C" rev-parse HEAD)"
crun() { printf '{"session_id":"s-%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$TR" "$C" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$C" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
# c1: the committed hunk was never reviewed over a range; a workspace report (base = HEAD) whose map has app.py's exact sha
rep "$TMP/r5/ocr-review.json" "$C" "$CH" HEAD app.py; age -300 "$C/app.py"; age 0 "$TMP/r5/ocr-review.json"
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer; ocr_run t3 "$TMP/r5/ocr-review.json"
crun c1; rc=$?
[ "$rc" = 2 ] && grep -q -- "--from" "$TMP/err" && ok "(c) committed hunk + a workspace map with app.py's sha (base = HEAD): still asks for the range run (rc 2)" \
  || fail "(c) workspace map counted for the committed range (rc $rc)"
# range map over the committed code (blob at HEAD), report older than app.py: content decides, passes
rep "$TMP/r6/ocr-review.json" "$C" "$VH" HEAD app.py; age 0 "$C/app.py"; age -300 "$TMP/r6/ocr-review.json"
: > "$TR"; ocr_run t1 "$TMP/r6/ocr-review.json" --from "$VH" --to HEAD; ev edit t2 "$C/app.py"; ev agent t3 principal-code-reviewer
crun r1; rc=$?
[ "$rc" = 0 ] && ok "range map whose sha is app.py's blob at HEAD (report older than the file): covered (rc 0)" \
  || fail "range map matching the HEAD blob not counted (rc $rc) $(grep -m1 REVIEW-GATE "$TMP/err")"
: > "$TR"; ocr_run t1 "$TMP/r6/ocr-review.json" --from "$CH" --to HEAD; ev edit t2 "$C/app.py"; ev agent t3 principal-code-reviewer
crun r2; rc=$?
[ "$rc" = 2 ] && ok "  … the same map from a run whose --from is past the verified head: covers part of it only (rc 2)" || fail "partial range counted (rc $rc)"
# committed, then edited again (dirty): range map = HEAD blob, workspace map = working tree; both old: covered
rep "$TMP/r6/ocr-review.json" "$C" "$VH" HEAD app.py
echo "def g(x): return 3 / x if x else 0" > "$C/app.py"; rep "$TMP/r7/ocr-review.json" "$C" "$CH" ws app.py
age -300 "$TMP/r6/ocr-review.json" "$TMP/r7/ocr-review.json"; age 0 "$C/app.py"
: > "$TR"; ocr_run t1 "$TMP/r6/ocr-review.json" --from "$VH" --to HEAD; ocr_run t2 "$TMP/r7/ocr-review.json"; ev edit t3 "$C/app.py"
ev agent t4 principal-code-reviewer
crun r3; rc=$?
[ "$rc" = 0 ] && ok "committed + dirty: the range map is checked against the HEAD blob, the workspace map against the file (rc 0)" \
  || fail "committed + dirty with both maps matching: rc $rc $(grep -m1 REVIEW-GATE "$TMP/err")"
rep "$TMP/r8/ocr-review.json" "$C" "$VH" ws app.py; age -300 "$TMP/r8/ocr-review.json"
: > "$TR"; ocr_run t1 "$TMP/r8/ocr-review.json" --from "$VH" --to HEAD; ocr_run t2 "$TMP/r7/ocr-review.json"; ev edit t3 "$C/app.py"
ev agent t4 principal-code-reviewer
crun r4; rc=$?
[ "$rc" = 2 ] && ok "  … a ranged run whose map holds the working-tree sha (not the HEAD blob): not counted for the range (rc 2)" \
  || fail "range map with the working-tree sha counted (rc $rc)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
