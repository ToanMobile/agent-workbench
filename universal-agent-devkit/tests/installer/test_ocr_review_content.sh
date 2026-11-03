#!/usr/bin/env bash
# bin/ocr-review content map (wave 2 lane D, 03/11): the report it keeps carries `content_sha256` {path: sha256} of the files the report
# says it reviewed (manifest.coverage completed + reused), hashed BEFORE `ocr review` starts (working tree; the blob at --to / --commit
# for a ranged run), and `content_base` (HEAD; --from; the commit's parent). hooks/review_gate.sh credits a file whose bytes still hash
# the same. A report with no coverage gets no map (the gate keeps its mtime rule). Last case: the helper's own report through the gate.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DEVKIT_DIR/bin/ocr-review"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/sub" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def a(x):\n    return x\n' > a.py; printf 'def b(x):\n    return x\n' > b.py; printf 'def d(x):\n    return x\n' > sub/d.py
git add -A && git commit -qm init; BASE0="$(git rev-parse HEAD)"
printf 'def a(x):\n    return 1 / x\n' > a.py && git commit -qam "a: divide"; C1="$(git rev-parse HEAD)"
printf 'def a(x):\n    return 2 / x\n' > a.py; printf 'def b(x):\n    return 3 / x\n' > b.py; printf 'def c(x):\n    return x\n' > c.py
printf 'def d(x):\n    return 4 / x\n' > sub/d.py

# fake ocr review: OCR_COV = the coverage paths it reports (completed), OCR_REUSED = reused; OCR_NOMANIFEST=1: an old report shape.
# It appends to a.py while it "reviews": the map must hold the bytes from before the review.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*)
    out=""; prev=""
    for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
    [ -n "${OCR_TOUCH:-}" ] && echo "# changed during the review" >> "$OCR_TOUCH"
    if [ -n "${OCR_NOMANIFEST:-}" ]; then printf '{"comments":[]}\n' > "$out"; exit 0; fi
    cov=""; for p in $OCR_COV; do cov="$cov${cov:+,}{\"path\":\"$p\"}"; done
    reu=""; for p in ${OCR_REUSED:-}; do reu="$reu${reu:+,}{\"path\":\"$p\"}"; done
    printf '{"status":"complete","summary":{"files_reviewed":1},"comments":[],"manifest":{"coverage":{"selected":[],"completed":[%s],"reused":[%s],"failed":[]}}}\n' "$cov" "$reu" > "$out"
    exit 0 ;;
  "delegate preview")
    ex=""; for p in ${OCR_EXCL:-}; do ex="$ex${ex:+,}{\"path\":\"$p\",\"exclude_reason\":\"default_path\"}"; done
    printf '{"schema_version":"1","reviewable_files":[],"excluded_files":[%s]}\n' "$ex"; exit 0 ;;
esac
echo "fake ocr: unexpected $*" >&2; exit 9
SH
chmod +x "$TMP/bin/ocr"
sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'; }
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); k=sys.argv[2:]
v=d
for x in k: v=v.get(x) if isinstance(v,dict) else None
print("<absent>" if v is None else v)' "$@"; }

# 1. workspace run: map = coverage only, pre-review bytes, base = HEAD
A_BEFORE="$(sha < a.py)"; C_SHA="$(sha < c.py)"
PATH="$TMP/bin:$PATH" OCR_COV="a.py" OCR_REUSED="c.py" OCR_TOUCH="$R/a.py" python3 "$HELPER" --out "$TMP/o1" > "$TMP/out" 2> "$TMP/err"; rc=$?
REP="$TMP/o1/ocr-review.json"
[ "$rc" = 0 ] && grep -q '^mode: review' "$TMP/out" && ok "workspace run: report kept (rc 0)" || fail "workspace run rc $rc: $(cat "$TMP/err")"
[ "$(field "$REP" content_sha256 a.py)" = "$A_BEFORE" ] && [ "$A_BEFORE" != "$(sha < a.py)" ] \
  && ok "a.py: the sha of the bytes BEFORE the review (the file changed during it)" || fail "a.py sha $(field "$REP" content_sha256 a.py), want $A_BEFORE"
[ "$(field "$REP" content_sha256 c.py)" = "$C_SHA" ] && ok "c.py (untracked, reused by OCR): in the map" || fail "c.py sha $(field "$REP" content_sha256 c.py)"
[ "$(field "$REP" content_sha256 b.py)" = "<absent>" ] && ok "b.py (changed, but not in the report's coverage): not in the map" \
  || fail "b.py in the map although OCR did not review it"
[ "$(field "$REP" content_base)" = "$C1" ] && ok "content_base = HEAD of the run" || fail "content_base $(field "$REP" content_base), want $C1"
[ "$(field "$REP" comments)" = "[]" ] && ok "the OCR report itself is kept (comments)" || fail "report body lost"
printf 'def a(x):\n    return 2 / x\n' > a.py

# 2. from a sub-folder: paths relative to the repo top, as review_gate's
(cd sub && PATH="$TMP/bin:$PATH" OCR_COV="sub/d.py" python3 "$HELPER" --out "$TMP/o2" > "$TMP/out" 2> "$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "$(field "$TMP/o2/ocr-review.json" content_sha256 sub/d.py)" = "$(sha < sub/d.py)" ] \
  && ok "run from a sub-folder: the map key is the top-relative path sub/d.py" || fail "sub-folder run: $(cat "$TMP/o2/ocr-review.json") $(cat "$TMP/err")"

# 3. --commit: the blob at the commit, not the working tree; base = its parent
PATH="$TMP/bin:$PATH" OCR_COV="a.py" python3 "$HELPER" --commit "$C1" --out "$TMP/o3" > "$TMP/out" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(field "$TMP/o3/ocr-review.json" content_sha256 a.py)" = "$(git show "$C1:a.py" | sha)" ] \
  && [ "$(git show "$C1:a.py" | sha)" != "$(sha < a.py)" ] && ok "--commit: a.py hashed from the blob at the commit (working tree differs)" \
  || fail "--commit map: $(cat "$TMP/o3/ocr-review.json") $(cat "$TMP/err")"
[ "$(field "$TMP/o3/ocr-review.json" content_base)" = "$BASE0" ] && ok "--commit: content_base = the commit's parent" || fail "--commit base $(field "$TMP/o3/ocr-review.json" content_base)"

# 4. --from alone (to HEAD): base = the --from commit, blobs at HEAD; a file the range did not touch is not hashed
PATH="$TMP/bin:$PATH" OCR_COV="a.py b.py" python3 "$HELPER" --from "$BASE0" --out "$TMP/o4" > "$TMP/out" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(field "$TMP/o4/ocr-review.json" content_base)" = "$BASE0" ] \
  && [ "$(field "$TMP/o4/ocr-review.json" content_sha256 a.py)" = "$(git show "HEAD:a.py" | sha)" ] \
  && [ "$(field "$TMP/o4/ocr-review.json" content_sha256 b.py)" = "<absent>" ] \
  && ok "--from: base = --from, a.py from the HEAD blob, b.py (not in the range) absent though OCR named it" \
  || fail "--from map: $(cat "$TMP/o4/ocr-review.json") $(cat "$TMP/err")"

# 5. a report with no coverage (older OCR, another shape): no map, the gate keeps its mtime rule
PATH="$TMP/bin:$PATH" OCR_NOMANIFEST=1 python3 "$HELPER" --out "$TMP/o5" > "$TMP/out" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(field "$TMP/o5/ocr-review.json" content_sha256)" = "<absent>" ] && ok "no coverage in the report: no content map (rc 0)" \
  || fail "map written without coverage: $(cat "$TMP/o5/ocr-review.json")"

# 5b. what OCR's own excludes leave out (from `ocr delegate preview`): content_excluded, minus anything the report did review
PATH="$TMP/bin:$PATH" OCR_COV="a.py" OCR_EXCL="dist/x.js a.py" python3 "$HELPER" --out "$TMP/o7" > "$TMP/out" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(field "$TMP/o7/ocr-review.json" content_excluded)" = "['dist/x.js']" ] \
  && ok "content_excluded = OCR's excluded files (dist/x.js), not one the report reviewed" || fail "content_excluded: $(cat "$TMP/o7/ocr-review.json")"

# 6. end to end: the helper's report, then b.py edited and put back to the same bytes, an agent review after it: the gate passes
cat > "$TMP/tr.py" <<'PY'
import json, sys
tr, repo, rep = sys.argv[1:4]
def use(i, name, inp): return {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": i, "name": name, "input": inp}]}}
def res(i, txt): return {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": i, "is_error": False, "content": txt}]}}
ev = [use("t1", "Write", {"file_path": repo + "/b.py", "content": "x"}),
      use("t2", "Bash", {"command": ".agents/devkit/bin/ocr-review --out x"}), res("t2", "mode: review\nreport: " + rep),
      use("t3", "Write", {"file_path": repo + "/b.py", "content": "x"}),
      use("t4", "Agent", {"subagent_type": "principal-code-reviewer", "prompt": "review"})]
open(tr, "w").write("".join(json.dumps(e) + "\n" for e in ev))
PY
git checkout -q -- a.py sub/d.py && rm -f c.py
PATH="$TMP/bin:$PATH" OCR_COV="b.py" python3 "$HELPER" --out "$TMP/o6" > "$TMP/out" 2> "$TMP/err"
python3 -c 'import os,sys,time; t=time.time(); os.utime(sys.argv[1],(t-300,)*2); os.utime(sys.argv[2],(t,)*2)' "$TMP/o6/ocr-review.json" "$R/b.py"
python3 "$TMP/tr.py" "$TMP/t.jsonl" "$R" "$TMP/o6/ocr-review.json"
printf '{"session_id":"s-e2e","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$TMP/t.jsonl" "$R" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" REVIEW_GATE_OCR=1 bash "$DEVKIT_DIR/hooks/review_gate.sh" > /dev/null 2> "$TMP/gerr"; rc=$?
[ "$rc" = 0 ] && ok "end to end: the helper's map + an agent review after b.py went back to the reviewed bytes: gate passes (rc 0)" \
  || fail "end to end: gate rc $rc $(head -3 "$TMP/gerr")"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
