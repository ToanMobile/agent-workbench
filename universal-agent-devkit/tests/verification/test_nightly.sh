#!/usr/bin/env bash
# Regression test: scripts/nightly.py — the local nightly job (launchd), never in the cloud.
#  - run: for each registered project with a matrix the gate trusts, every suite for real
#    (heavy ones too), a FAIL re-run once (green → FLAKY), evidence logs; then the pending
#    RED-proofs with --heavy; the result lands in the checklist
#  - a notification only when a row TURNS red (FAIL/TIMEOUT/FLAKY/VACUOUS) — silence when all
#    stays green, no repeat while it stays red; the weekly one-line report every 7 days
#  - untrusted matrix → the project is skipped and said so
#  - install/uninstall write/remove the LaunchAgent plist (launchctl injectable for tests);
#    add/remove keep the project list
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NIGHTLY="$DEVKIT_DIR/scripts/governance/nightly.py"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export HOME="$TMP/home"; mkdir -p "$HOME"
export NIGHTLY_NOTIFY_CMD="$TMP/notify.sh"; NOTES="$TMP/notes.txt"; : > "$NOTES"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s\n' "$NOTES" > "$NIGHTLY_NOTIFY_CMD"; chmod +x "$NIGHTLY_NOTIFY_CMD"
export NIGHTLY_LAUNCHCTL="true"

mk() {  # mk <dir> <command-A> <command-B>
  local P="$1"; mkdir -p "$P/src" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t && git config devkit.trunkMode false
    echo 1 > src/a.txt; echo 1 > src/b.txt
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [
      {"component": "A", "watch_files": ["src/a.txt"], "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": sys.argv[1]}]},
      {"component": "B", "watch_files": ["src/b.txt"], "mandatory_regression_tests": [{"id": "REG-B", "name": "b", "command": sys.argv[2]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$2" "$3"
    git add -A && git commit -qm init
    echo 2 > src/a.txt; echo 2 > src/b.txt
    CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
    git add -A && git commit -qm ran )
}
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$1')); print(r.effective_status(d, d['items']['$2']))"; }

GOOD="$TMP/good"; mk "$GOOD" "true" "true || ./gradlew test"
BAD="$TMP/bad"; mk "$BAD" "true" 'grep -q 2 src/b.txt'
FLK="$TMP/flaky"; mk "$FLK" 'if [ -f .ran ]; then true; else touch .ran; echo "1 failed"; exit 1; fi' "true"
rm -f "$FLK/.ran"
[ "$(st "$GOOD" REG-A)" = PASS ] && [ "$(st "$BAD" REG-B)" = PASS ] && ok "setup: suites PASS" || fail "setup"

python3 "$NIGHTLY" add "$GOOD" >/dev/null && python3 "$NIGHTLY" add "$BAD" >/dev/null && python3 "$NIGHTLY" add "$FLK" >/dev/null
python3 "$NIGHTLY" add "$GOOD" >/dev/null
[ "$(grep -c . "$HOME/.config/agent-kit/nightly-projects")" = 3 ] && ok "add: project list without duplicates" || fail "list: $(cat "$HOME/.config/agent-kit/nightly-projects")"

echo 3 > "$BAD/src/b.txt"                       # breaks REG-B
python3 "$NIGHTLY" run > "$TMP/run1" 2>&1
[ "$(st "$BAD" REG-B)" = FAIL ] && ok "a suite broken since its PASS → FAIL recorded by the nightly run" || fail "bad: $(st "$BAD" REG-B) $(cat "$TMP/run1")"
[ "$(st "$GOOD" REG-B)" = PASS ] && ok "heavy suite (Gradle) runs at night" || fail "heavy: $(st "$GOOD" REG-B)"
ls "$BAD"/.agents/evidence/REG-B/*.log >/dev/null 2>&1 && ok "nightly runs keep evidence logs" || fail "no evidence"
grep -q "REG-B" "$NOTES" && grep -q "bad" "$NOTES" && ok "notification when a row turns red (project + suite)" || fail "notes: $(cat "$NOTES")"
grep "chuyển sang đỏ" "$NOTES" | grep -q "good" && fail "notified for an all-green project" || ok "all green → no red notification"
[ "$(st "$FLK" REG-A)" = FLAKY ] && grep -q "FLAKY" "$NOTES" && ok "red then green on re-run → FLAKY + notified" || fail "flaky: $(st "$FLK" REG-A)"
grep -q "tuần" "$NOTES" && ls "$GOOD/.agents/evidence/weekly.log" >/dev/null 2>&1 && ok "first run writes the weekly one-line report" || fail "weekly: $(cat "$NOTES")"

: > "$NOTES"; python3 "$NIGHTLY" run >/dev/null 2>&1
grep -q "REG-B" "$NOTES" && fail "notified again while still red" || ok "still red next night → no repeat"
grep -q "tuần" "$NOTES" && fail "weekly report repeated within 7 days" || ok "weekly report once per 7 days"

python3 - "$BAD" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "echo changed"; json.dump(d, open(p, "w"))
PY
out="$(python3 "$NIGHTLY" run 2>&1)"
printf '%s' "$out" | grep -q "bad.*không được gate tin" && ok "untrusted matrix → project skipped, said so" || fail "untrusted: $out"

python3 "$NIGHTLY" install --hour 2 --minute 17 >/dev/null 2>&1
PL="$HOME/Library/LaunchAgents/com.universal-agent-devkit.nightly.plist"
[ -f "$PL" ] && grep -q "nightly.py" "$PL" && grep -q "<integer>2</integer>" "$PL" && grep -q "<integer>17</integer>" "$PL" \
  && ok "install writes the LaunchAgent (daily 02:17)" || fail "plist: $(cat "$PL" 2>/dev/null | head -20)"
python3 "$NIGHTLY" status 2>&1 | grep -q "02:17" && ok "status shows the schedule and projects" || fail "status"
python3 "$NIGHTLY" uninstall >/dev/null 2>&1; [ ! -f "$PL" ] && ok "uninstall removes it" || fail "uninstall"
python3 "$NIGHTLY" remove "$FLK" >/dev/null; [ "$(grep -c . "$HOME/.config/agent-kit/nightly-projects")" = 2 ] && ok "remove drops a project" || fail "remove"

# W4b: `run <project>…` runs exactly the named projects (the daily /devkit-audit calls it once per repo whose checkout is free):
# not the registry, no registry change, and no weekly report (its 7-day slot would go to whichever repo came first).
ONE="$TMP/one"; mk "$ONE" "true" 'grep -q 2 src/b.txt'; echo 3 > "$ONE/src/b.txt"        # breaks REG-B
REG_BEFORE="$(cat "$HOME/.config/agent-kit/nightly-projects")"
rm -f "$HOME/.config/agent-kit/nightly-state.json"; : > "$NOTES"
out="$(python3 "$NIGHTLY" run "$ONE" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(st "$ONE" REG-B)" = FAIL ] && ok "run <path>: runs that project although it is not registered" || fail "run <path>: rc=$rc $(st "$ONE" REG-B) $out"
printf '%s\n' "$out" | grep -q '^one: ' && ! printf '%s\n' "$out" | grep -q '^good: ' && ok "run <path>: only the named project runs, the registered ones do not" || fail "run <path> output: $out"
[ "$(cat "$HOME/.config/agent-kit/nightly-projects")" = "$REG_BEFORE" ] && ok "run <path>: the project list is untouched" || fail "run <path> changed the list"
[ ! -f "$HOME/.config/agent-kit/nightly-state.json" ] && ! grep -q "tuần" "$NOTES" && ok "run <path>: no weekly report, its 7-day slot stays free" || fail "run <path> weekly: $(cat "$NOTES")"
python3 "$NIGHTLY" run "$TMP/no-such-dir" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "run <path>: a path that is not a directory is refused (exit 2)" || fail "run <bad path>: exit $rc"

# H1 (review of lane A13): a NAMED run leaves a checkout alone while a session holds it, idle at its prompt too: `session_lock.py
# --status` calls an idle holder free, but that session takes the lock back at the next prompt and edits the tree the run is testing.
# The lock is judged with the strictness of worktree_merge_gate (idle_frees=False, live_pid_holds=True); a dead pid is free.
setlock() {  # setlock <repo> <idle|active|old|dead|none>
  python3 - "$1" "$2" <<'PY'
import json, os, sys, time
repo, kind = sys.argv[1], sys.argv[2]; gdir = os.path.realpath(os.path.join(repo, ".git")); lock = os.path.join(gdir, "devkit-session.lock")
if kind == "none":
    sys.exit(os.path.exists(lock) and os.unlink(lock) or 0)
now = time.time(); pid = 2147483646 if kind == "dead" else os.getppid()   # the parent of this helper (the test shell) is alive
d = {"session_id": "other-session", "started": now - 3600, "heartbeat": now - (2400 if kind == "old" else 5), "cwd": repo, "pid": pid, "gitdir": gdir}
if kind == "idle":
    d["idle_since"] = now - 300
json.dump(d, open(lock, "w"))
PY
}
HELD="$TMP/held"; mk "$HELD" "true" 'grep -q 2 src/b.txt'; echo 3 > "$HELD/src/b.txt"        # breaks REG-B: it turns FAIL only if the run happens
for kind in idle active old; do
  setlock "$HELD" "$kind"
  out="$(python3 "$NIGHTLY" run "$HELD" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^held: skip: ' && [ "$(st "$HELD" REG-B)" = PASS ] \
    && ok "run <path>: a $kind holder with a live pid keeps the checkout - skipped with 'skip: <reason>', nothing ran" || fail "run <path> held by a $kind session: rc=$rc $(st "$HELD" REG-B) $out"
done
setlock "$HELD" dead
out="$(python3 "$NIGHTLY" run "$HELD" 2>&1)"
[ "$(st "$HELD" REG-B)" = FAIL ] && ok "run <path>: a lock whose pid is dead is free - the run goes ahead" || fail "run <path> with a dead holder: $(st "$HELD" REG-B) $out"
# a session that opens BETWEEN two suites: the run stops before the next suite (REG-A, the first, writes the lock when .arm exists)
MID="$TMP/mid"; mk "$MID" "if [ -f .arm ]; then cp .lockfixture .git/devkit-session.lock; fi; true" 'grep -q 2 src/b.txt'; echo 3 > "$MID/src/b.txt"
setlock "$MID" active; cp "$MID/.git/devkit-session.lock" "$MID/.lockfixture"; setlock "$MID" none; : > "$MID/.arm"
out="$(python3 "$NIGHTLY" run "$MID" 2>&1)"
[ -f "$MID/.git/devkit-session.lock" ] && [ "$(st "$MID" REG-B)" != FAIL ] && printf '%s\n' "$out" | grep -q 'skip: .*dừng trước REG-B' \
  && ok "run <path>: a session that took the checkout after the first suite stops the run before the next one" || fail "run <path> lock taken mid-run: $(st "$MID" REG-B) $out"
setlock "$HELD" none
# ... and one that opens during the LAST suite: there is no next suite to stop before, but red_proof (git worktree add/remove in that repo's
# .git) still follows. run_project is driven in-process with subprocess.run recording the red_proof call (a control with no session: it runs once).
LAST="$TMP/last"; mk "$LAST" "true" "if [ -f .arm ]; then cp .lockfixture .git/devkit-session.lock; fi; true"
setlock "$LAST" active; cp "$LAST/.git/devkit-session.lock" "$LAST/.lockfixture"; setlock "$LAST" none
CTRL="$TMP/ctrl"; mk "$CTRL" "true" "true"
rp_calls() {  # rp_calls <project>: how many times red_proof.py was started by a named run_project, and its message
  python3 -I - "$DEVKIT_DIR" "$1" <<'PY'
import subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1] + "/scripts/governance")
import nightly
calls, real = [], subprocess.run
def fake(argv, *a, **k):
    if any("red_proof.py" in str(x) for x in argv):
        calls.append(argv)
        return subprocess.CompletedProcess(argv, 0, "", "")
    return real(argv, *a, **k)
subprocess.run = fake
_turned, msg = nightly.run_project(Path(sys.argv[2]), named=True)
print(len(calls), msg)
PY
}
out="$(rp_calls "$CTRL")"
[ "${out%% *}" = 1 ] && ok "control: a free project's run starts red_proof once" || fail "control red_proof count: $out"
: > "$LAST/.arm"
out="$(rp_calls "$LAST")"
[ "${out%% *}" = 0 ] && printf '%s' "$out" | grep -q 'skip: ' && ok "a session that opens during the last suite: red_proof is not started, said so" || fail "lock armed by the last suite: $out"

# M1 (review of lane A13): the paths a named run is given are checked before anything runs.
#  - "" (Path("") is the cwd: the audit's own workbench) and blank paths are refused (exit 2); the cwd here is an empty scratch dir, so a run
#    that wrongly accepted "" would only say "bỏ qua" and exit 0
#  - one repo never runs twice (a trailing slash, a symlink, the same path twice)
#  - a directory that is no DevKit project (no .agents/, or not a git root: the 12/10 OfficeReader outer-folder mistake) given EXPLICITLY is
#    exit 2 with the reason, nothing runs; a bare `run` keeps skipping such a registered project with exit 0 (the LaunchAgent passes only `run`)
CWD0="$TMP/cwd0"; mkdir -p "$CWD0"
for blank in "" "   "; do
  out="$(cd "$CWD0" && python3 "$NIGHTLY" run "$blank" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qi 'empty' && ok "run '$blank': an empty or blank path is refused (exit 2) and said so" || fail "run '$blank': rc=$rc $out"
done
out="$(cd "$CWD0" && python3 "$NIGHTLY" run "$ONE" "" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ! printf '%s\n' "$out" | grep -q '^one: ' && ok "run <good> '': one bad path refuses the whole run, the good one does not run first" || fail "run <good> '': rc=$rc $out"
DUP="$TMP/dup"; mk "$DUP" "true" "true"; ln -s "$DUP" "$TMP/dup-link"
out="$(python3 "$NIGHTLY" run "$DUP" "$DUP/" "$TMP/dup-link" "$TMP/../$(basename "$TMP")/dup" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^dup: ')" = 1 ] && ok "run <p> <p>/ <symlink to p>: one repo runs once" || fail "run duplicates: rc=$rc $out"
PLAIN="$TMP/plain"; mkdir -p "$PLAIN"                                    # no .agents/, no git
NOAG="$TMP/noag"; mkdir -p "$NOAG" && git init -q "$NOAG"                # a git root without .agents/
OUTER="$TMP/outer"; mkdir -p "$OUTER/.agents" "$OUTER/inner"; git init -q "$OUTER/inner"   # .agents/ but not a git root
for bad in "$PLAIN" "$NOAG" "$OUTER"; do
  out="$(python3 "$NIGHTLY" run "$ONE" "$bad" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q "$(basename "$bad")" && ! printf '%s\n' "$out" | grep -q '^one: ' \
    && ok "run <good> $(basename "$bad"): an explicit path that is no DevKit git root is exit 2 with its name, nothing runs" || fail "run <good> $bad: rc=$rc $out"
done
HOME2="$TMP/home2"; mkdir -p "$HOME2"; HOME="$HOME2" python3 "$NIGHTLY" add "$PLAIN" >/dev/null
out="$(HOME="$HOME2" python3 "$NIGHTLY" run 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^plain: .*bỏ qua' && ok "bare run: a registered project that is no DevKit project is still skipped with exit 0 (the LaunchAgent's call is unchanged)" || fail "bare run with a plain registered dir: rc=$rc $out"

# The bare run is the LaunchAgent's call and ignores sessions (nobody works at night): a registered project whose checkout an idle session holds
# is still RUN. (A bare run made `named` would skip it: this is the pin that turns red.)
LOCKED="$TMP/locked"; mk "$LOCKED" "true" 'grep -q 2 src/b.txt'; echo 3 > "$LOCKED/src/b.txt"     # breaks REG-B: it turns FAIL only if the run happens
setlock "$LOCKED" idle
HOME3="$TMP/home3"; mkdir -p "$HOME3"; HOME="$HOME3" python3 "$NIGHTLY" add "$LOCKED" >/dev/null
out="$(HOME="$HOME3" python3 "$NIGHTLY" run 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(st "$LOCKED" REG-B)" = FAIL ] && ! printf '%s\n' "$out" | grep -q 'skip:' && ok "bare run: a registered project an idle session holds is still run (the LaunchAgent path ignores sessions)" || fail "bare run on a locked project: rc=$rc $(st "$LOCKED" REG-B) $out"

# Review round 2: what a NAMED run must also refuse or skip
# (a) a .git that is a file pointing at a git dir that is gone: git_dir gives nothing, and the run used to go ahead
BROKEN="$TMP/brokengit"; mkdir -p "$BROKEN/.agents"; printf 'gitdir: %s/no-such-gitdir\n' "$TMP" > "$BROKEN/.git"
out="$(python3 "$NIGHTLY" run "$BROKEN" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^brokengit: skip: .*git dir' && ok "run <path>: a .git that points at a missing git dir is skipped with a reason, not run" || fail "broken .git pointer: rc=$rc $out"
# (b) a trunk-mode main checkout holds no lock, yet it takes merges only: the suites run in a worktree of their own, finished afterwards;
# the run never writes into main (a skip here deadlocked the night, a run here wrote main's checklist)
TRK="$TMP/trunk"; mk "$TRK" "true" 'grep -q 2 src/b.txt'; echo 3 > "$TRK/src/b.txt"; git -C "$TRK" commit -qam break; git -C "$TRK" config devkit.trunkMode true
head_before="$(git -C "$TRK" rev-parse HEAD)"; : > "$NOTES"
out="$(python3 "$NIGHTLY" run "$TRK" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^trunk: REG-A: PASS.*REG-B: FAIL' && ! printf '%s\n' "$out" | grep -q 'skip: ' \
  && grep -q 'trunk REG-B FAIL' "$NOTES" && [ -z "$(git -C "$TRK" status --porcelain)" ] && [ "$(git -C "$TRK" rev-parse HEAD)" = "$head_before" ] \
  && [ "$(git -C "$TRK" worktree list | wc -l | tr -d ' ')" = 1 ] \
  && ok "run <path>: a trunk-mode main runs in its own worktree: suites ran, the red row is notified, main stays clean and unmoved, the worktree is gone" \
  || fail "trunk-mode main: rc=$rc status=[$(git -C "$TRK" status --porcelain)] wts=$(git -C "$TRK" worktree list | wc -l) notes=[$(cat "$NOTES")] $out"
# (b2) main trunk mode mà có phiên sống đang giữ lock vẫn bị bỏ qua: trunk chỉ bỏ lý do "merge-only", không bỏ kiểm tra lock
TRKH="$TMP/trunkheld"; mk "$TRKH" "true" 'grep -q 2 src/b.txt'; echo 3 > "$TRKH/src/b.txt"; git -C "$TRKH" config devkit.trunkMode true
setlock "$TRKH" active
out="$(python3 "$NIGHTLY" run "$TRKH" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^trunkheld: skip: ' && [ "$(st "$TRKH" REG-B)" = PASS ] && ok "run <path>: a trunk-mode main a live session holds is still skipped - trunk mode never bypasses the lock check" || fail "trunk-mode main held by a live session: rc=$rc $(st "$TRKH" REG-B) $out"
setlock "$TRKH" none
# (c) one repo spelled two ways by a case-insensitive filesystem (APFS) runs once: identity is (device, inode), not the resolved string
CI="$TMP/CaseRepo"; mk "$CI" "true" "true"
if [ -d "$TMP/caserepo" ]; then
  out="$(python3 "$NIGHTLY" run "$CI" "$TMP/caserepo" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -ci '^caserepo: ')" = 1 ] && ok "run <p> <P>: one repo spelled in two letter cases runs once (identity by inode)" || fail "case-spelled duplicate: rc=$rc $out"
else
  echo "- skipped: this filesystem is case-sensitive, the case-spelled duplicate cannot arise here"
fi
# (d) ~user of a user that does not exist: Path.expanduser raises RuntimeError; that is exit 2 with the path named, not a traceback
out="$(python3 "$NIGHTLY" run '~nosuchuser_zz9/x' 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q 'nosuchuser_zz9' && ! printf '%s\n' "$out" | grep -q 'Traceback' && ok "run ~nosuchuser/x: exit 2 naming the path, no traceback" || fail "unknown ~user: rc=$rc $out"

[ "$FAILS" -eq 0 ] && echo "✅ test_nightly: all passed" || { echo "❌ test_nightly: $FAILS failed"; exit 1; }
