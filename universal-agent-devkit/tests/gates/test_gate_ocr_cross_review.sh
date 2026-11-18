#!/usr/bin/env bash
# #1258: OpenCodeReview (`ocr`) is a second independent cross-reviewer of an edited existing test, next to Antigravity (additive: one of
# the two is enough). push_gate.ocr_review() / approved() accept `Test-approved-by: ocr <session-id>` only for a session the `ocr` CLI
# itself reports (fake `ocr` below emits the real `ocr session show|comments --json` structure) that is an LLM range review of exactly
# the head, completed, covering every edited file, with no critical/high finding, made after the head commit. Every other case: refused.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1   # test-only switch: fake pm record + fake ocr binary under $TMP
export FAKE_OCR_DIR="$TMP/store"; mkdir -p "$FAKE_OCR_DIR" "$TMP/bin"
unset DEVKIT_OCR_CROSS_REVIEW DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID CLAUDECODE
cat > "$TMP/bin/ocr" <<'PY'
#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]                               # session show --json <id> | session comments --json --repo <dir> <id>
f = os.path.join(os.environ["FAKE_OCR_DIR"], f"{a[1]}-{a[-1]}.json") if len(a) > 2 and a[0] == "session" else ""
if not os.path.exists(f):
    sys.stderr.write("session not found\n")
    sys.exit(1)
sys.stdout.write(open(f).read())
PY
chmod +x "$TMP/bin/ocr"
export DEVKIT_OCR_BIN="$TMP/bin/ocr"

R="$TMP/repo"; mkdir -p "$R/tests" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo a > code.txt
git add -A && git commit -qm init && git update-ref refs/remotes/origin/main HEAD
git checkout -q -b pr
printf '#!/bin/sh\nexit 0\n' > tests/test_old.sh
git add -A && git commit -qm "edit test"
HEAD_SHA="$(git rev-parse HEAD)"; BASE_SHA="$(git rev-parse origin/main)"
git commit -q --allow-empty -m "ocr trailer" -m "Test-approved-by: ocr 11111111-1111-4111-8111-111111111111"
TRAILER_SHA="$(git rev-parse HEAD)"

mk() {   # mk <id> [key=value ...]: write the fake store entry; keys: mode term failed to from model sev covered start nocomments
  python3 - "$FAKE_OCR_DIR" "$R" "$HEAD_SHA" "$BASE_SHA" "$@" <<'PY'
import json, os, sys, time
d, repo, head, base, sid, *kv = sys.argv[1:]
o = dict(repo=repo, mode="range", term="complete", failed=0, to=head, frm=base, model="m-1", sev="medium", covered="tests/test_old.sh",
         start=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 300)))
o.update(x.split("=", 1) for x in kv)
cov = [{"path": p, "item_id": p, "fingerprint": "f"} for p in o["covered"].split(",") if p]
n = 0 if o["sev"] == "none" else 1
man = {"run_id": sid, "terminal_state": o["term"], "input": {"mode": o["mode"], "resolved_base": o["frm"], "resolved_head": o["to"]},
       "coverage": {"selected": cov, "completed": cov, "reused": [], "failed": [], "waived": [], "excluded": []}}
summ = {"session_id": sid, "repo_dir": o["repo"], "review_mode": o["mode"], "model": o["model"], "start_time": o["start"], "legacy": False,
        "aborted": False, "completed_files": len(cov), "failed_files": int(o["failed"]), "llm_failures": 0, "total_comments": n,
        "run_manifest": man}
com = [] if not n else [{"path": "tests/test_old.sh", "content": "x", "category": "bug", "severity": o["sev"]}]
json.dump({"summary": summ, "items": []}, open(os.path.join(d, f"show-{sid}.json"), "w"))
json.dump(com, open(os.path.join(d, f"comments-{sid}.json"), "w"))
PY
}
chk() {   # chk <name> <want True|False> <id> [head]: ocr_review verdict
  local got
  got="$(env ${XENV:-} python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(*p.ocr_review(sys.argv[2], sys.argv[3], sys.argv[4]))' \
    "$DEVKIT_DIR/bin" "$R" "$3" "${4:-$HEAD_SHA}" 2>&1 | tail -1)"
  if [ "${got%% *}" = "$2" ]; then echo "✔ $1 -> $got"; else echo "✖ $1: want $2, got $got"; FAILS=$((FAILS + 1)); fi
}
FAILS=0
A=11111111-1111-4111-8111-111111111111
mk $A;                                chk "accept: valid range session of the head" True $A
mk $A to=$BASE_SHA;                   chk "reject: head mismatch" False $A
mk $A mode=delegate;                  chk "reject: delegate mode (host agent is the author)" False $A
mk $A mode=workspace;                 chk "reject: workspace mode" False $A
mk $A term=failed failed=1;           chk "reject: session not completed" False $A
mk $A sev=high;                       chk "reject: blocking finding (high)" False $A
mk $A sev=critical;                   chk "reject: blocking finding (critical)" False $A
mk $A sev=weird;                      chk "reject: unknown severity" False $A
mk $A sev=none;                       chk "accept: no findings at all" True $A
mk $A covered=code.txt;               chk "reject: edited test not covered" False $A
mk $A frm=$HEAD_SHA;                  chk "reject: from is not the merge-base" False $A
mk $A start=2001-01-01T00:00:00Z;     chk "reject: session older than the head commit" False $A
mk $A model=;                         chk "reject: no model recorded" False $A
chk "reject: head is not 40 hex" False $A origin/main
chk "reject: session unknown to ocr" False 22222222-2222-4222-8222-222222222222
# evidence the author writes into the repo or a scratch dir is never read: only the (fake) ocr store counts
rm -f "$FAKE_OCR_DIR"/*; mkdir -p "$R/.ocr"; cp /dev/null "$R/.ocr/$A.json"; printf '{"summary":{}}' > "$R/.ocr/show-$A.json"
chk "reject: evidence file written in the repo, not stored by ocr" False $A
mk $A
XENV="DEVKIT_OCR_CROSS_REVIEW=0" chk "reject: kill switch DEVKIT_OCR_CROSS_REVIEW=0" False $A
XENV="DEVKIT_OCR_BIN=$TMP/bin/nope" chk "reject: ocr binary missing" False $A
# R4: both env switches are author-settable, so the binary override also needs the repo itself under a temp dir (_seal_fixture):
# same env, but the repo no longer counts as a throw-away one -> the fake ocr is ignored (no real ocr in the fixed paths -> refused)
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; p._seal_lib().fixture_repo = lambda top: False; print(*p.ocr_review(sys.argv[2], sys.argv[3], sys.argv[4]))' "$DEVKIT_DIR/bin" "$R" "$A" "$HEAD_SHA" 2>&1 | tail -1)"
[ "${got%% *}" = "False" ] && echo "✔ reject: DEVKIT_OCR_BIN ignored for a repo not under a temp dir -> $got" || { echo "✖ real repo honoured DEVKIT_OCR_BIN: $got"; FAILS=$((FAILS + 1)); }
# R6: test-file detection covers FooTest.kt and androidTest/ as post-fix-gate does
for f in src/FooTest.kt app/androidTest/Bar.kt src/foo.spec.ts; do
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; sys.exit(0 if p.OCR_TEST_PATH.search(sys.argv[2]) else 1)' "$DEVKIT_DIR/bin" "$f" && echo "✔ test path: $f" || { echo "✖ not seen as test path: $f"; FAILS=$((FAILS + 1)); }
done
XENV="-u DEVKIT_PM_HOME_TEST" chk "reject: DEVKIT_OCR_BIN ignored without the test switch" False $A
XENV="-u DEVKIT_PM_HOME_TEST -u DEVKIT_OCR_BIN PATH=$TMP/bin:$PATH" chk "reject: fake ocr first on PATH is not used" False $A
# marker: trailer commit on top of the reviewed head, through approved() (the push gate / post-fix-gate trailer path)
appr() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.approved(sys.argv[2], sys.argv[3]))' "$DEVKIT_DIR/bin" "$R" "$1" 2>&1 | tail -1; }
got="$(appr "$TRAILER_SHA^!")"; case "$got" in "(True, 'Test-approved-by: ocr $A (ocr review)')") echo "✔ approved(): ocr trailer accepted";; *) echo "✖ approved(): $got"; FAILS=$((FAILS + 1));; esac
mk $A to=$BASE_SHA
got="$(appr "$TRAILER_SHA^!")"; case "$got" in "(False,"*) echo "✔ approved(): ocr trailer refused when the session head differs";; *) echo "✖ approved() accepted a wrong head: $got"; FAILS=$((FAILS + 1));; esac
rm -f "$FAKE_OCR_DIR"/*
got="$(appr "$TRAILER_SHA^!")"; case "$got" in "(False,"*) echo "✔ approved(): trailer naming no ocr session refused";; *) echo "✖ approved() accepted a forged trailer: $got"; FAILS=$((FAILS + 1));; esac
# R5: the trailer commit must not carry a change (tree differs from the reviewed head), nor may later commits change the tip tree
mk $A
git checkout -q -f "$HEAD_SHA"; echo x > code.txt; git commit -qam "trailer with change" -m "Test-approved-by: ocr $A"; CHG_SHA="$(git rev-parse HEAD)"
got="$(appr "$CHG_SHA^!")"; case "$got" in "(False,"*) echo "✔ approved(): trailer commit that changes the tree refused";; *) echo "✖ non-empty trailer commit accepted: $got"; FAILS=$((FAILS + 1));; esac
git checkout -q -f "$TRAILER_SHA"; echo y > code.txt; git commit -qam "later change"
got="$(appr "$BASE_SHA..HEAD")"; case "$got" in "(False,"*) echo "✔ approved(): later change after the trailer refused (tip tree differs)";; *) echo "✖ stale approval accepted: $got"; FAILS=$((FAILS + 1));; esac
git checkout -q -f "$TRAILER_SHA"
# post-fix-gate reads the reviewed head of an accepted trailer through trailer_head(): the parent of the ocr trailer commit
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.trailer_head(sys.argv[2], "ocr", sys.argv[4], sys.argv[3]))' "$DEVKIT_DIR/bin" "$R" "$TRAILER_SHA" "$A" 2>&1 | tail -1)"
[ "$got" = "$HEAD_SHA" ] && echo "✔ trailer_head(ocr) = parent of the trailer commit" || { echo "✖ trailer_head(ocr): $got"; FAILS=$((FAILS + 1)); }
# Antigravity path unchanged: same trailer shape accepted with a PM audit pass for the head, refused without a record
git checkout -q -f "$HEAD_SHA" && git commit -q --allow-empty -m "agy trailer" -m "Test-approved-by: antigravity T0001-x"; AGY_SHA="$(git rev-parse HEAD)"
got="$(appr "$AGY_SHA^!")"; case "$got" in "(False,"*) echo "✔ antigravity: no PM record -> refused as before";; *) echo "✖ antigravity: $got"; FAILS=$((FAILS + 1));; esac
mkdir -p "$TMP/pm/projects/p-T0001-x/tasks/T0001-x"
printf '{"id":"T0001-x","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"pm","notes":"ok\\nauditedHead: %s"}},"dispatches":[{"kind":"audit","agent":"antigravity"}]}\n' \
  "$R" "$HEAD_SHA" > "$TMP/pm/projects/p-T0001-x/tasks/T0001-x/task.json"
got="$(appr "$AGY_SHA^!")"; case "$got" in "(True, 'Test-approved-by: antigravity T0001-x (antigravity-pm audit pass)')") echo "✔ antigravity: PM audit pass -> accepted as before";; *) echo "✖ antigravity: $got"; FAILS=$((FAILS + 1));; esac
# R7: a linked worktree (or the merge gate's scratch tree) is the same repo; an unrelated repo is not
git -C "$R" worktree add -q --detach "$TMP/wt" "$HEAD_SHA"
git init -q "$TMP/other"
mk $A repo="$TMP/wt"; chk "accept: session made in a linked worktree of this repo" True $A
mk $A repo="$TMP/other"; chk "reject: session from an unrelated repo" False $A
git -C "$R" worktree remove --force "$TMP/wt"
# R8: renaming a test to a non-test path must not hide it from the coverage check
git checkout -q -f "$BASE_SHA"; mkdir -p lib; git mv tests/test_old.sh lib/old.sh; git commit -qm "rename test"; RN_SHA="$(git rev-parse HEAD)"
mk $A to=$RN_SHA covered=lib/old.sh;  chk "reject: test renamed to a non-test path is still an edited test" False $A $RN_SHA
mk $A to=$RN_SHA covered=lib/old.sh,tests/test_old.sh; chk "accept: rename with the old test path covered" True $A $RN_SHA
# R9: start_time keeps its timezone (same instant written with an offset); a naive time is refused
OFF="$(python3 -c 'import time,datetime as d; t=d.datetime.fromtimestamp(time.time()+300,d.timezone(d.timedelta(hours=-5))); print(t.strftime("%Y-%m-%dT%H:%M:%S-05:00"))')"
NAIVE="$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(time.time()+300)))')"
mk $A start="$OFF";   chk "accept: start_time with a UTC offset (same instant)" True $A
mk $A start="$NAIVE"; chk "reject: start_time without timezone" False $A
# R10/R11: post-fix-gate trailer source (_trailer_cross_review)
cat > "$TMP/pfg.py" <<'PY'
import importlib.util, os, sys
sys.path.insert(0, sys.argv[1] + "/bin")
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1] + "/bin/post-fix-gate.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.chdir(sys.argv[2]); r = m._trailer_cross_review(["tests/test_old.sh"], sys.argv[2]); print(sorted(v[0] for v in r.values()), m.PM_APPROVAL_USED)
PY
pfg() { env CLAUDE_PROJECT_DIR="$R" python3 "$TMP/pfg.py" "$DEVKIT_DIR" "$R" 2>&1 | tail -1; }
mk $A; git checkout -q -f "$TRAILER_SHA"
got="$(pfg)"; [ "$got" = "['ocr'] []" ] && echo "✔ post-fix-gate: ocr trailer covers the test, PM_APPROVAL_USED untouched" || { echo "✖ post-fix-gate ocr: $got"; FAILS=$((FAILS + 1)); }
# R11: a newer reviewed head (H2) replaces the test; the older trailer (H1) must not cover a revert to H1's content
B=22222222-2222-4222-8222-222222222222
printf '#!/bin/sh\nexit 0 # v2\n' > tests/test_old.sh; git commit -qam "test v2"; H2="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "ocr trailer 2" -m "Test-approved-by: ocr $B"
mk $B to=$H2
got="$(pfg)"; [ "$got" = "['ocr'] []" ] && echo "✔ post-fix-gate: newest ocr head covers the current test" || { echo "✖ post-fix-gate H2: $got"; FAILS=$((FAILS + 1)); }
git checkout -q "$HEAD_SHA" -- tests/test_old.sh; git commit -qm "revert test to v1 (replay)"
got="$(pfg)"; [ "$got" = "[] []" ] && echo "✔ post-fix-gate: replay of the superseded ocr head refused" || { echo "✖ replay accepted: $got"; FAILS=$((FAILS + 1)); }
# R10: an ocr trailer in the --since path must not mark a PM-record approval as used (pm_relaxed() would refuse it wrongly)
cat > "$TMP/since.py" <<'PY'
import importlib.util, os, sys
sys.path.insert(0, sys.argv[1] + "/bin")
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1] + "/bin/post-fix-gate.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.chdir(sys.argv[2]); m.since_test_weakened(sys.argv[3], "tests/test_old.sh"); print(m.PM_APPROVAL_USED)
PY
git checkout -q -f "$TRAILER_SHA"; mk $A
got="$(env CLAUDE_PROJECT_DIR="$R" python3 "$TMP/since.py" "$DEVKIT_DIR" "$R" "$BASE_SHA" 2>&1 | tail -1)"
[ "$got" = "[]" ] && echo "✔ since path: ocr trailer does not set PM_APPROVAL_USED" || { echo "✖ since path PM_APPROVAL_USED: $got"; FAILS=$((FAILS + 1)); }
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
