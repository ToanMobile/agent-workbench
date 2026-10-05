#!/usr/bin/env bash
# Regression (DevKit speed 1d, round 2): the OTHER writers of the tracked checklist files leave them alone in a LINKED
# worktree, like the gate does (tests/worktree_git/test_worktree_checklist.sh). bin/regression_checklist.py
# skip_bookkeeping() is the one switch (in_linked_worktree: git dir != common dir; DEVKIT_WORKTREE_CHECKLIST=1 asks for the write).
# Each case runs the same writer in the MAIN checkout (control: it still writes) and in a linked worktree of the same repo:
#   hooks/session_context.sh        mark_stale / auto_close_reported saved at session start
#   hooks/session_context.sh        no background re-run claimed (its results would go to the checklist)
#   scripts/testing/stale_rerun.py  re-runs STALE suites and records them
#   scripts/governance/nightly.py   runs every suite of a registered project and records them
#   scripts/context/enrich_context.py  a bug prompt -> a REPORTED row; the user's INBOX -> "seen" keys
#   hooks/test_evidence_gate.sh     auto-link of a proven fix to its bug row (the Stop decision stays the same)
#   scripts/testing/red_proof.py    the proof recorded on the bug row
# Rows are still read in the worktree, the printed output and every exit code stay; only the file is not written.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; KIT="$DEVKIT_DIR/bin/agent-kit"
RERUN="$DEVKIT_DIR/scripts/testing/stale_rerun.py"; NIGHTLY="$DEVKIT_DIR/scripts/governance/nightly.py"
PROOF="$DEVKIT_DIR/scripts/testing/red_proof.py"
SESSION_HOOK="$DEVKIT_DIR/hooks/session_context.sh"; PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE AUTO_LINK STALE_RERUN DEVKIT_WORKTREE_CHECKLIST RED_PROOF INBOX_WATCH
export SESSION_FETCH=0 VACUITY_REVERT=0 HOME="$TMP/home"; mkdir -p "$HOME"
export NIGHTLY_NOTIFY_CMD=true NIGHTLY_LAUNCHCTL=true

# sig <checkout>: the checklist bookkeeping files, as one fingerprint
sig() { cat "$1/.agents/regression_status.json" "$1/.agents/CHECKLIST.md" 2>/dev/null | shasum | cut -d' ' -f1; }
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$1')); print(r.effective_status(d, d['items']['$2']))"; }
stale_now() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
p=pathlib.Path('$1'); d=r.load(p); r.mark_stale(d, p); print(r.effective_status(d, d['items']['$2']))"; }

# wait_idle <checkout>: until no DevKit background job (stale_rerun / red_proof) is running for that checkout, at most 40 s: a
# negative check ("nothing ran") made after it looks at a finished world, not after a guessed delay
wait_idle() {
  local i=0
  while pgrep -f "(stale_rerun|red_proof)[.]py $1( |\$)" >/dev/null 2>&1 && [ "$i" -lt 200 ]; do sleep 0.2; i=$((i + 1)); done
  pgrep -f "(stale_rerun|red_proof)[.]py $1( |\$)" >/dev/null 2>&1 && fail "a background job is still running for $1 after 40 s"
  return 0
}

# row <checkout> <id> <key>: one field of a checklist row as the hooks of THAT checkout see it (tracked file + the worktree's own state)
row() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load_view(pathlib.Path('$1')); v=d['items'].get('$2', {}); print(v.get('$3') if '$3' not in ('red_proof_status',) else (v.get('red_proof') or {}).get('status'))" 2>/dev/null; }

# mk_stale <dir>: a repo that tracks its checklist, whose suite REG-A passed once and whose watched file was committed AFTER that
# (so REG-A is STALE); the suite leaves .ran-a behind. The INBOX has one open item.
mk_stale() {
  mkdir -p "$1/src/a" "$1/.agents" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo 1 > src/a/x.py
  printf '.ran-a\n.claude/\n.agents/regression_journal/\n.agents/context/\n' > .gitignore   # .agents/context/ is what the installer git-ignores (context_sync)
  cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"A","watch_files":["src/a/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"echo ran >> .ran-a"}]}]}
JSON
  printf '# Hộp thư\n\n- [ ] Xuất hoá đơn PDF\n' > .agents/INBOX.md
  git add -A && git commit -qm init
  echo 2 >> src/a/x.py
  CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
  rm -f .ran-a
  git add -A && git commit -qm "ran" && sleep 1.1
  echo 3 >> src/a/x.py && git add -A && git commit -qm "code changed after the run"
}
# pair <name>: P = the main checkout, W = a linked worktree of it (plain `git worktree add`)
pair() {
  P="$TMP/$1"; W="$TMP/$1-wt"; mk_stale "$P"
  git -C "$P" worktree add -q --detach "$W" >/dev/null 2>&1 || fail "worktree add $1"
  [ "$(stale_now "$P" REG-A)" = STALE ] && [ "$(stale_now "$W" REG-A)" = STALE ] || fail "setup $1: REG-A is $(stale_now "$P" REG-A) / $(stale_now "$W" REG-A), not STALE"
}
session() { echo '{}' | CLAUDE_PROJECT_DIR="$1" bash "$SESSION_HOOK" 2>&1; }   # + STALE_RERUN from the caller
prompt() {  # prompt <checkout> <text> → the hook's context
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "s1", "transcript_path": sys.argv[2]}))' "$2" "$TMP/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" bash "$PROMPT_HOOK" 2>/dev/null; }

# ── session_context.sh: the STALE flag is saved back in the main checkout only ───────────────────────────────────────
pair c1
s_p="$(sig "$P")"; s_w="$(sig "$W")"
out_p="$(STALE_RERUN=0 session "$P")"; out_w="$(STALE_RERUN=0 session "$W")"
[ "$(sig "$P")" != "$s_p" ] && ok "control: SessionStart in the main checkout saves the STALE flag back" || fail "control did not write: $out_p"
[ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: SessionStart leaves the checklist files alone" || fail "SessionStart wrote the checklist in a linked worktree"
printf '%s' "$out_w" | grep -q "1 STALE" && printf '%s' "$out_p" | grep -q "1 STALE" \
  && ok "linked worktree: the checklist counts are still reported (read, not written)" || fail "STALE count missing: $out_w"
s_w="$(sig "$W")"; DEVKIT_WORKTREE_CHECKLIST=1 STALE_RERUN=0 session "$W" >/dev/null
[ "$(sig "$W")" != "$s_w" ] && ok "DEVKIT_WORKTREE_CHECKLIST=1 asks for the write in a linked worktree" || fail "env opt-in ignored"

# ── session_context.sh: no background re-run is claimed (its results would be written to the checklist) ──────────────
pair c2
out_p="$(session "$P")"; out_w="$(session "$W")"
printf '%s' "$out_p" | grep -q "chạy lại nền" && ok "control: the main checkout's SessionStart starts the background re-run and says so" || fail "control: $out_p"
printf '%s' "$out_w" | grep -q "chạy lại nền" && fail "linked worktree: SessionStart claims a background re-run" || ok "linked worktree: no background re-run claimed"
wait_idle "$W"; wait_idle "$P"
[ ! -e "$W/.ran-a" ] && ok "linked worktree: no suite was started" || fail "a suite ran in the linked worktree"

# ── stale_rerun.py ───────────────────────────────────────────────────────────────────────────────────────────────────
pair c3
s_w="$(sig "$W")"
python3 "$RERUN" "$P" --wait >/dev/null 2>&1; python3 "$RERUN" "$W" --wait >/dev/null 2>&1
[ -e "$P/.ran-a" ] && [ "$(st "$P" REG-A)" = PASS ] && ok "control: stale_rerun in the main checkout re-runs the suite and records PASS" || fail "control: $(st "$P" REG-A)"
[ ! -e "$W/.ran-a" ] && [ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: stale_rerun runs nothing and writes nothing" || fail "stale_rerun ran in a linked worktree"

# ── post-fix-gate.py --full: what a linked worktree's gate proved still counts the next time (per-worktree state) ───
# the tracked checklist is not written there, so without its own record every --full re-ran every STALE suite again
pair c3b
full() { ( cd "$1" && echo "x$RANDOM" >> other.txt && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/.agents/regression_matrix.active.json" --run-tests --full --allow-no-tests --no-cache --lang en 2>&1 ); }
runs() { [ -f "$1/.ran-a" ] && wc -l < "$1/.ran-a" | tr -d ' ' || echo 0; }
full "$P" >/dev/null; full "$P" >/dev/null; full "$W" >/dev/null; r1=$(runs "$W"); full "$W" >/dev/null; full "$W" >/dev/null
[ "$(runs "$P")" = 1 ] && ok "control: in the main checkout the STALE suite is re-run once (the PASS is recorded), not on every --full" || fail "control: REG-A ran $(runs "$P") times in 2 --full runs"
[ "$r1" = 1 ] && [ "$(runs "$W")" = 1 ] && ok "linked worktree: the STALE suite is re-run once; the next --full runs find its PASS (per-worktree state, nothing tracked written)" \
  || fail "linked worktree: REG-A ran $(runs "$W") times in 3 --full runs (1 expected)"
[ -z "$(git -C "$W" status --porcelain -- .agents/regression_status.json .agents/CHECKLIST.md)" ] && ok "  ... and the tracked checklist files stayed untouched" || fail "linked worktree wrote the tracked checklist"
edit_commit() { echo "$1" >> "$W/src/a/x.py"; git -C "$W" commit -qam "edit $1"; }   # committed: only STALE, not 'impacted by the uncommitted change'
edit_commit e1; full "$W" >/dev/null
[ "$(runs "$W")" = 2 ] && ok "  ... a change to the suite's watched files makes it STALE again (the recorded PASS never covers another tree)" || fail "after a watched-file edit REG-A ran $(runs "$W") times (2 expected)"

# the overlay is writable by whoever runs in the worktree: it is believed no further than the gate's own receipt
overlay_file() { echo "$(git -C "$W" rev-parse --absolute-git-dir)/postfix-gate/worktree_checklist.json"; }
forge() {  # forge <how>: a PASS for the CURRENT watched files, with the matrix and local-state hashes the gate would compute
  python3 - "$DEVKIT_DIR" "$W" "$(overlay_file)" "$1" <<'PY'
import importlib.util, json, sys, time
kit, w, path, how = sys.argv[1:5]
sys.argv = ["x"]
spec = importlib.util.spec_from_file_location("pfg", kit + "/bin/post-fix-gate.py"); pfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pfg)
sys.path.insert(0, kit + "/bin")
import regression_checklist as rc
bind = pfg.overlay_bind(w, w + "/.agents/regression_matrix.active.json")
fp = rc.watched_fingerprint(w, ["src/a/*"])
when = {"future": 9e9, "old": time.time() - 7 * 3600, "now": time.time(), "badbind": time.time(), "badfp": time.time()}[how]
head = (rc._git_lines(rc.Path(w), "rev-parse", "--short", "HEAD") or ["x"])[0]
ent = {"last": {"status": "PASS", "ts": when, "at": "forged", "exit_code": 0, "commit": head + "+dirty"}, "history": [], "bind": bind, "watched_fp": fp, "saved_at": when}
if how == "badbind":
    ent["bind"] = {"matrix_sha": "0", "local_sha": "0"}          # another matrix / local state than the gate sees now
if how == "badfp":
    ent["watched_fp"] = "0" * 24                                  # not the content of the suite's watched files now
json.dump({"tests": {"REG-A": ent}, "rows": {}}, open(path, "w"))
PY
}
for how in future old badbind badfp; do
  edit_commit "y$how"; before=$(runs "$W"); forge "$how"; full "$W" >/dev/null
  [ "$(runs "$W")" = $((before + 1)) ] && ok "linked worktree: a forged overlay PASS ($how) is refused, the suite runs" || fail "forged overlay ($how) was believed: REG-A ran $(runs "$W") times, expected $((before + 1))"
done
edit_commit z; before=$(runs "$W"); forge now; full "$W" >/dev/null
[ "$(runs "$W")" = "$before" ] && ok "  ... while an entry that is fresh, bound to this matrix/local state and to the same watched files is believed (no re-run)" || fail "a valid entry was refused: REG-A ran $(runs "$W") times, expected $before"
echo "{not json" > "$(overlay_file)"; edit_commit w; before=$(runs "$W"); full "$W" >/dev/null; rc=$?
[ "$(runs "$W")" = $((before + 1)) ] && [ "$rc" = 0 ] && ok "  ... and an unreadable overlay counts as none (the suite runs, the gate still passes)" || fail "bad overlay: rc=$rc, REG-A ran $(runs "$W") times, expected $((before + 1))"

# an overlay nobody should have written: bad UTF-8, JSON nested too deep, a time stamp that is not a finite number, a FIFO (it
# would hang a reader): each counts as none, nothing raises, nothing hangs (every gate run below is bounded)
bounded() { python3 -c 'import subprocess, sys; sys.exit(subprocess.run(sys.argv[2:], timeout=float(sys.argv[1])).returncode)' "$@"; }
for bad in utf8 deep nan huge fifo; do
  edit_commit "bad-$bad"; before=$(runs "$W"); of="$(overlay_file)"; rm -f "$of"
  case "$bad" in
    utf8) printf '{"tests": {"REG-A": \xff\xfe}}' > "$of" ;;
    deep) python3 -c 'import sys; sys.stdout.write("[" * 300000 + "]" * 300000)' > "$of" ;;
    nan)  printf '{"tests": {"REG-A": {"last": {"status": "PASS", "ts": NaN}, "saved_at": NaN, "watched_fp": "x", "bind": {}}}, "rows": {}}' > "$of" ;;
    huge) printf '{"tests": {"REG-A": {"last": {"status": "PASS", "ts": 1e999}, "saved_at": 10000000000000000000000000000000000000000000, "watched_fp": "x", "bind": {}}}, "rows": {}}' > "$of" ;;
    fifo) mkfifo "$of" ;;
  esac
  ( cd "$W" && echo "x$RANDOM" >> other.txt && CLAUDE_PROJECT_DIR="$W" bounded 120 python3 "$GATE" --matrix "$W/.agents/regression_matrix.active.json" --run-tests --full --allow-no-tests --no-cache --lang en >/dev/null 2>&1 ); rc=$?
  [ "$rc" = 0 ] && [ "$(runs "$W")" = $((before + 1)) ] && ok "linked worktree: a $bad overlay counts as none (no crash, no hang), the STALE suite runs" \
    || fail "$bad overlay: rc=$rc, REG-A ran $(runs "$W") times, expected $((before + 1))"
  rm -f "$of"
done

# the fingerprint of a suite's watched files sees what a blob id does not: the exec bit, a symlink in place of a file, a name with a newline
python3 - "$DEVKIT_DIR/bin" "$TMP" >"$TMP/fp.out" 2>&1 <<'PY'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc
d = os.path.join(sys.argv[2], "fpcase"); os.makedirs(d + "/src")
subprocess.run(["git", "init", "-q", d], check=True)
open(d + "/src/a.txt", "w").write("a\n"); open(d + "/src/b.txt", "w").write("b\n")
fp = lambda pats=("src/*",): rc.watched_fingerprint(d, list(pats))
res = []
base = fp(); res.append(("a fingerprint is taken", bool(base)))
os.chmod(d + "/src/a.txt", 0o755); res.append(("the exec bit changes it", fp() != base)); os.chmod(d + "/src/a.txt", 0o644)
res.append(("restoring the file restores it", fp() == base))
os.remove(d + "/src/b.txt"); os.symlink("a.txt", d + "/src/b.txt"); res.append(("a symlink in place of a file changes it", fp() != base))
os.remove(d + "/src/b.txt"); open(d + "/src/b.txt", "w").write("b\n")
open(d + "/src/we\nird.txt", "w").write("x\n"); res.append(("a name with a newline: not trusted (empty)", fp() == ""))
os.remove(d + "/src/we\nird.txt")
res.append(("a bad watch pattern (reversed range) does not raise: not trusted (empty)", fp(["src/[z-a]*"]) == ""))
ov = rc._overlay_path(d); ov.parent.mkdir(parents=True, exist_ok=True)
ov.write_text("[" * 300000 + "]" * 300000)
res.append(("read_overlay: JSON nested too deep reads as empty (no RecursionError)", rc.read_overlay(d) == {"tests": {}, "rows": {}}))
ov.write_text('{"tests": [1], "rows": "x"}')
res.append(("read_overlay: wrong shapes read as empty", rc.read_overlay(d) == {"tests": {}, "rows": {}}))
for name, good in res:
    print(("PASS " if good else "FAIL ") + "watched_fingerprint: " + name)
sys.exit(0 if all(g for _, g in res) else 1)
PY
fp_rc=$?
while IFS= read -r l; do case "$l" in PASS*) ok "${l#PASS }" ;; FAIL*) fail "${l#FAIL }" ;; *) echo "$l" ;; esac; done < "$TMP/fp.out"
[ "$fp_rc" = 0 ] || fail "the fingerprint / overlay reader checks exited $fp_rc"

# a file edited WHILE its suite runs must not be vouched for by that suite's PASS (the fingerprint is taken before the run)
pair c3c
python3 - "$W/.agents/regression_matrix.active.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "echo ran >> .ran-a; echo m >> src/a/x.py; git -c user.email=t@t -c user.name=t commit -qam selfmod"
json.dump(d, open(sys.argv[1], "w"))
PY
git -C "$W" commit -qam "the suite edits and commits its own watched file"
full "$W" >/dev/null; full "$W" >/dev/null
[ "$(runs "$W")" = 2 ] && ok "linked worktree: a suite that rewrote its own watched files while running is not vouched for (it runs again)" \
  || fail "self-editing suite: REG-A ran $(runs "$W") times in 2 --full runs, expected 2"

# ── nightly.py ───────────────────────────────────────────────────────────────────────────────────────────────────────
pair c4
s_w="$(sig "$W")"
python3 "$NIGHTLY" add "$P" >/dev/null 2>&1; python3 "$NIGHTLY" add "$W" >/dev/null 2>&1
python3 "$NIGHTLY" run > "$TMP/nightly.out" 2>&1
[ -e "$P/.ran-a" ] && [ "$(st "$P" REG-A)" = PASS ] && ok "control: nightly runs the main checkout's suites and records them" || fail "control: $(st "$P" REG-A) $(cat "$TMP/nightly.out")"
[ ! -e "$W/.ran-a" ] && [ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: nightly skips it, nothing run, nothing written" || fail "nightly ran in a linked worktree"

# ── enrich_context.py: a bug prompt -> a REPORTED row ────────────────────────────────────────────────────────────────
pair c5
s_p="$(sig "$P")"; s_w="$(sig "$W")"
b_p="$(prompt "$P" "App bị crash khi cộng hai số" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
b_w="$(prompt "$W" "App bị crash khi cộng hai số" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
[ -n "$b_p" ] && [ "$(sig "$P")" != "$s_p" ] && ok "control: a bug prompt in the main checkout becomes a REPORTED row" || fail "control: no row ($b_p)"
[ "$b_w" = "$b_p" ] && [ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: the same context line, but the row is not written to the tracked checklist" || fail "bug prompt in a linked worktree: id='$b_w' (main '$b_p'), written=$([ "$(sig "$W")" = "$s_w" ] && echo no || echo yes)"
prompt "$W" "App bị crash khi cộng hai số" >/dev/null
nrows="$(python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
print(len([k for k, v in r.load_view(pathlib.Path('$W'))['items'].items() if v.get('kind') == 'bug']))")"
[ "$(row "$W" "$b_w" state)" = reported ] && [ "$nrows" = 1 ] && [ "$(sig "$W")" = "$s_w" ] \
  && ok "linked worktree: the REPORTED row is kept in the worktree's own state (its hooks see it; the same prompt again adds no duplicate)" || fail "REPORTED row not kept: state='$(row "$W" "$b_w" state)' rows=$nrows"

# ── enrich_context.py: the user's INBOX ──────────────────────────────────────────────────────────────────────────────
pair c6
s_p="$(sig "$P")"; s_w="$(sig "$W")"
out_p="$(prompt "$P" "xem giúp tình hình dự án thế nào")"; out_w="$(prompt "$W" "xem giúp tình hình dự án thế nào")"
printf '%s' "$out_p" | grep -q "Xuất hoá đơn PDF" && [ "$(sig "$P")" != "$s_p" ] && ok "control: the main checkout's prompt hook lists the new INBOX item once and remembers it" || fail "control: $out_p"
[ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: the prompt hook does not write the INBOX 'seen' keys" || fail "INBOX keys written in a linked worktree"
printf '%s' "$out_w" | grep -q "Xuất hoá đơn PDF" && fail "linked worktree: the INBOX item is listed (it would repeat on every prompt: nothing remembers it)" \
  || ok "linked worktree: the INBOX is the main checkout's business, not listed (it could not be remembered)"

# ── test_evidence_gate.sh: auto-link (the Stop decision stays the same, the link is not written) ─────────────────────
mk_calc() {  # mk_calc <dir>: calc project + one REPORTED bug row (session s1) tracked in git
  mkdir -p "$1/src" "$1/tests" "$1/.agents" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def add(a, b):\n    return a - b\n' > src/calc.py
  cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Calc","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CALC","name":"calc","command":"python3 -m unittest discover -s tests"}]}]}
JSON
  printf '.claude/\n.agents/regression_journal/\n' > .gitignore
  touch tests/.gitkeep
  git add -A && git commit -qm init
}
transcript() {  # transcript <dir> <steps…>: w:<test file> | r:<test file> (red run naming it) | e:<src file> | g (green run)
  python3 - "$@" <<'PY'
import json, sys
P, steps = sys.argv[1], sys.argv[2:]
lines = []
for i, s in enumerate(steps):
    kind, _, arg = s.partition(":")
    uid = f"t{i}"
    if kind == "w":
        open(f"{P}/{arg}", "w").write("import unittest\n")
        use = {"name": "Write", "input": {"file_path": f"{P}/{arg}", "content": "x"}}; res, err = "ok", False
    elif kind == "e":
        use = {"name": "Edit", "input": {"file_path": f"{P}/{arg}", "old_string": "-", "new_string": "+"}}; res, err = "ok", False
    elif kind == "r":
        use = {"name": "Bash", "input": {"command": "python3 -m unittest discover -s tests"}}
        res, err = f"FAIL: test_add ({arg.rsplit('/', 1)[-1][:-3]}.TestAdd.test_add)\nFAILED (failures=1)", True
    else:
        use = {"name": "Bash", "input": {"command": "python3 -m unittest discover -s tests"}}; res, err = "Ran 1 test\n\nOK", False
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": uid, **use}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": uid, "content": res, "is_error": err}]}}))
open(f"{P}/tr.jsonl", "w").write("\n".join(lines) + "\n")
PY
}
stop() {  # stop <dir> [env…]: the Stop hook for a session that claims a RED->GREEN fix; sets RC
  local d="$1"; shift
  ERR="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "s1", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$d/tr.jsonl" \
         | env CLAUDE_PROJECT_DIR="$d" LESSON_REMINDER=0 "$@" bash "$STOP_GATE" 2>&1 >/dev/null)"; RC=$?
}
P="$TMP/c7"; W="$TMP/c7-wt"; mk_calc "$P"
( cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null 2>&1 && git add -A && git commit -qm "the project tracks its checklist" )
git -C "$P" worktree add -q --detach "$W" >/dev/null 2>&1 || fail "worktree add c7"
s_p="$(sig "$P")"; s_w="$(sig "$W")"
prompt "$P" "App bị crash khi cộng hai số" >/dev/null; prompt "$W" "App bị crash khi cộng hai số" >/dev/null     # the REPORTED row of session s1, each where it lives
transcript "$P" w:tests/test_calc.py r:tests/test_calc.py e:src/calc.py g; stop "$P" RED_PROOF=0; rc_p=$RC
transcript "$W" w:tests/test_calc.py r:tests/test_calc.py e:src/calc.py g; stop "$W"; rc_w=$RC; err_w="$ERR"
grep -q '"linked_by": "auto"' "$P/.agents/regression_status.json" && [ "$(sig "$P")" != "$s_p" ] && ok "control: the main checkout's Stop links the proven fix to its bug row by itself" || fail "control: no auto link (rc=$rc_p)"
[ "$rc_w" = "$rc_p" ] && ok "linked worktree: the Stop decision is the same (exit $rc_w)" || fail "Stop decision differs: worktree $rc_w, main $rc_p: $err_w"
[ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: nothing of it is written to the tracked checklist" || fail "tracked checklist written in a linked worktree"
B7="$(row "$W" "$(python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
print(next(k for k, v in r.load_view(pathlib.Path('$W'))['items'].items() if v.get('kind') == 'bug'))")" id)"
[ "$(row "$W" "$B7" linked_by)" = auto ] && ok "linked worktree: the auto-link is kept in the worktree's own state" || fail "auto-link not kept: linked_by='$(row "$W" "$B7" linked_by)'"
grep -q "red-proof started" "$W/.claude/audit-gate/test_evidence_gate.log" 2>/dev/null \
  && ok "linked worktree: the background RED-proof is started, as in the main checkout (it records into the worktree's own state)" || fail "linked worktree: no background RED-proof was started"
wait_idle "$W"
[ -n "$(row "$W" "$B7" red_proof_status)" ] && [ "$(row "$W" "$B7" red_proof_status)" != None ] && ok "linked worktree: ... and its result is there (red_proof: $(row "$W" "$B7" red_proof_status))" || fail "no RED-proof result in the worktree state: '$(row "$W" "$B7" red_proof_status)'"
[ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: ... still nothing in the tracked checklist" || fail "red_proof wrote the tracked checklist"

# ── red_proof.py: the proof is printed, not recorded ─────────────────────────────────────────────────────────────────
P="$TMP/c8"; W="$TMP/c8-wt"; mk_calc "$P"
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nimport calc\nclass TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 2), 4)\n' > "$P/tests/test_calc.py"
B="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add trừ thay vì cộng" --fixed --test tests/test_calc.py 2>&1 | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
git -C "$P" add .agents && git -C "$P" commit -qm "bug row" && git -C "$P" worktree add -q --detach "$W" >/dev/null 2>&1 || fail "worktree add c8"
cp "$P/tests/test_calc.py" "$W/tests/test_calc.py"                                           # the new test, uncommitted, in both
for d in "$P" "$W"; do printf 'def add(a, b):\n    return a + b\n' > "$d/src/calc.py"; done      # the fix, uncommitted
s_p="$(sig "$P")"; s_w="$(sig "$W")"
out_p="$(python3 "$PROOF" "$P" --bug "$B" --wait 2>/dev/null)"; out_w="$(python3 "$PROOF" "$W" --bug "$B" --wait 2>/dev/null)"
printf '%s' "$out_p" | grep -q "PROVEN" && [ "$(sig "$P")" != "$s_p" ] && ok "control: red_proof in the main checkout records the proof on the bug row" || fail "control: '$out_p'"
printf '%s' "$out_w" | grep -q "PROVEN" && ok "linked worktree: red_proof still runs and prints its verdict" || fail "worktree red_proof output: '$out_w'"
[ "$(sig "$W")" = "$s_w" ] && ok "linked worktree: the proof is not written to the tracked checklist" || fail "red_proof wrote the checklist in a linked worktree"
[ "$(row "$W" "$B" red_proof_status)" = PROVEN ] && ok "linked worktree: ... it is kept in the worktree's own state (PROVEN)" || fail "proof not kept: '$(row "$W" "$B" red_proof_status)'"

# a VACUOUS test of a bug of this session holds the Stop in a linked worktree too (it needs the proof the hook started or you ran)
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nimport calc\nclass TestNothing(unittest.TestCase):\n    def test_nothing(self):\n        self.assertTrue(callable(calc.add))\n' > "$W/tests/test_vacuous.py"
B2="$(cd "$W" && CLAUDE_PROJECT_DIR="$W" bash "$KIT" bugs add "test that catches nothing" --fixed --test tests/test_vacuous.py 2>&1 | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
python3 - "$W" "$B2" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
d["items"][sys.argv[2]]["sessions"] = ["sv"]; json.dump(d, open(p, "w"))
PY
python3 "$PROOF" "$W" --bug "$B2" --wait >/dev/null 2>&1
[ "$(row "$W" "$B2" red_proof_status)" = VACUOUS ] || fail "setup: the vacuous proof is '$(row "$W" "$B2" red_proof_status)'"
python3 - "$W/tr.jsonl" "$W/src/calc.py" <<'PY'
import json, sys
out, src = sys.argv[1], sys.argv[2]
steps = [("Bash", {"command": "python3 -m pytest tests"}, "FAILED tests/test_calc.py::test_add\n1 failed", True),
         ("Edit", {"file_path": src, "old_string": "-", "new_string": "+"}, "ok", False),
         ("Bash", {"command": "python3 -m pytest tests"}, "2 passed in 0.01s", False)]
lines = []
for i, (name, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
err="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "sv", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$W/tr.jsonl" \
       | CLAUDE_PROJECT_DIR="$W" LESSON_REMINDER=0 RED_PROOF=0 bash "$STOP_GATE" 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$err" | grep -q "TEST VÔ HIỆU" && printf '%s' "$err" | grep -q "$B2" \
  && ok "linked worktree: a bug of this session whose test is VACUOUS holds the Stop, as in the main checkout" || fail "linked worktree VACUOUS hold: rc=$rc $err"

# ── advice text: a DETACHED worktree row has no branch to `git merge` (decisions and exit codes unchanged) ───────────
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
T="$TMP/txt"; mkdir -p "$T" && G "$T" init -q -b main . && echo a > "$T/a.txt" && G "$T" add a.txt && G "$T" commit -qm init
G "$T" worktree add -q --detach "$TMP/txt-det" && echo d > "$TMP/txt-det/d.txt"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$T" bash "$SESSION_HOOK" 2>&1)"
printf '%s' "$out" | grep -q "CHƯA về trunk" && printf '%s' "$out" | grep -q 'worktree diff <path> | git apply --3way' && ! printf '%s' "$out" | grep -q 'git merge --no-edit' \
  && ok "SessionStart: a detached worktree row is told to use diff | git apply, not git merge <branch>" || fail "session_context advice for a detached row: $out"
G "$T" worktree add -q -b feat/b "$TMP/txt-br" && echo b > "$TMP/txt-br/b.txt"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$T" bash "$SESSION_HOOK" 2>&1)"
printf '%s' "$out" | grep -q 'git merge --no-edit <branch>' && ok "SessionStart: a row with a branch keeps the git merge advice" || fail "session_context advice for a branch row: $out"

TR="$TMP/mg.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR"
sleep 1.2
M="$TMP/mg"; mkdir -p "$M" && G "$M" init -q -b main . && echo a > "$M/a.txt" && G "$M" add a.txt && G "$M" commit -qm init
mg_stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TR" | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/worktree_merge_gate.sh" >"$TMP/mg.out" 2>"$TMP/mg.err"; }
mg_use() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$1" >> "$TR"; }
mg_use "agent-kit worktree add ../mg-det"; G "$M" worktree add -q --detach "$TMP/mg-det" && echo d > "$TMP/mg-det/d.txt"
mg_stop s1; rc=$?
[ "$rc" = 2 ] && grep -q 'git apply --3way' "$TMP/mg.err" && ! grep -q 'git merge --no-edit' "$TMP/mg.err" \
  && ok "merge gate: only detached worktrees pending -> the bring-back advice is diff | git apply (no branch to merge), still held (exit 2)" \
  || fail "merge gate advice for a detached row (rc=$rc): $(cat "$TMP/mg.err")"
mg_use "agent-kit worktree add ../mg-br feat/mg"; G "$M" worktree add -q -b feat/mg "$TMP/mg-br" && echo b > "$TMP/mg-br/b.txt"
mg_stop s1; rc=$?
[ "$rc" = 2 ] && grep -q 'hoặc: git merge --no-edit <branch>' "$TMP/mg.err" \
  && ok "merge gate: a pending worktree with a branch keeps the git merge advice" || fail "merge gate advice for a branch row (rc=$rc): $(cat "$TMP/mg.err")"

# ── two agent-kit worktrees, each with the session hook, the prompt hook and the gate run in it: no false hold ───────────
# (before: the hooks and the gate rewrote the checklist there, so `status` counted it as work, `remove` refused after the
# bring-back and the merge gate held the Stop for work that was in main)
P="$TMP/c9"; mk_stale "$P"
TR9="$TMP/c9.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR9"
sleep 1.2
for n in 1 2; do
  ( cd "$P" && bash "$KIT" worktree add "../c9-$n" >/dev/null 2>&1 ) || fail "add c9-$n"
  python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "agent-kit worktree add ../c9-$n" >> "$TR9"
done
echo "# agent 1" >> "$TMP/c9-1/src/a/x.py"; echo "Y = 1" > "$TMP/c9-2/src/a/y.py"
for n in 1 2; do
  W9="$TMP/c9-$n"
  echo '{}' | CLAUDE_PROJECT_DIR="$W9" bash "$SESSION_HOOK" >/dev/null 2>&1
  prompt "$W9" "App bị crash khi cộng hai số" >/dev/null; prompt "$W9" "xem giúp tình hình dự án thế nào" >/dev/null
  ( cd "$W9" && CLAUDE_PROJECT_DIR="$W9" python3 "$GATE" --matrix "$W9/.agents/regression_matrix.active.json" --run-tests --full --allow-no-tests --no-cache --lang en >/dev/null 2>&1 )
done
wait_idle "$TMP/c9-1"; wait_idle "$TMP/c9-2"   # a background re-run, if one was started, has finished
st_out="$(cd "$P" && bash "$KIT" worktree status 2>&1)"
for n in 1 2; do
  printf '%s\n' "$st_out" | grep -F "/c9-$n  [" | grep -q "dirty=1 ahead=0" \
    && ok "two worktrees: status counts c9-$n's dirt as exactly its own file (dirty=1), no bookkeeping" || fail "status for c9-$n: $(printf '%s\n' "$st_out" | grep -F "/c9-$n  [") :: $(git -C "$TMP/c9-$n" status --porcelain | tr '\n' ' ')"
done
cd "$P" || exit 1
for n in 1 2; do
  bash "$KIT" worktree diff "../c9-$n" 2>/dev/null | git apply --3way >/dev/null 2>&1 || fail "bring back c9-$n"
done
[ -z "$(git status --porcelain | grep -E '^(UU|AA|DU|UD)')" ] && ok "two worktrees: both brought back into main without a conflict" || fail "conflict: $(git status --porcelain | tr '\n' ' ')"
for n in 1 2; do
  bash "$KIT" worktree remove "../c9-$n" >"$TMP/c9-rm$n.out" 2>&1; rc=$?
  [ "$rc" = 0 ] && [ ! -d "$TMP/c9-$n" ] && ok "two worktrees: c9-$n removed after the bring-back" || { fail "remove c9-$n (rc=$rc)"; cat "$TMP/c9-rm$n.out"; }
done
printf '{"session_id":"s9","hook_event_name":"Stop","transcript_path":"%s"}' "$TR9" | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/worktree_merge_gate.sh" >"$TMP/c9-mg.out" 2>"$TMP/c9-mg.err"
[ $? = 0 ] && ok "two worktrees: the merge gate lets the Stop through (nothing left to hold it on)" || fail "merge gate still holds: $(cat "$TMP/c9-mg.err")"

if [ "$FAILS" -ne 0 ]; then echo "worktree writers: $FAILS FAILED"; exit 1; fi
echo "worktree writers: all checks passed"
