#!/usr/bin/env bash
# W1 R1/R2 v6 (docs/workflow-improvements.md I.0; user 14/10: "mọi phiên sử dụng phải tạo worktree riêng ko giữ main để merge"): in trunk
# mode (`git config devkit.trunkMode true`) the main checkout is merge-only. bin/session_lock.py refuses every write into main ITSELF -
# whoever the session is, from main or from a worktree - and never takes main's lock, so no session ever holds main and a finished
# worktree is merged whenever its session stops. Still allowed in main: the integrator (agent-kit worktree …, worktree.py …), syncing with
# origin (fetch, push, pull --ff-only), builds, and local state git ignores (memory, .claude/audit-gate). A worktree nested under main
# (.claude/worktrees/<name>, where EnterWorktree puts it) is NOT main. `--status` on main says so with exit 5 (Antigravity reads it).
# WORKTREE_TRUNK_MODE=0 (R7) and trunk mode off: the old one-session-per-checkout lock, unchanged.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SL="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"; W2="$TMP/main-w2"
mkdir -p "$M/src" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '.agents/local/memory/\n.claude/audit-gate/\n/.claude/worktrees/\nnode_modules/\n' > "$M/.gitignore"
echo a > "$M/src/a.py" && echo r > "$M/README.md" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD && git -C "$M" worktree add -q --detach "$W2" HEAD
mkdir -p "$M/.agents/local/memory/claude-auto" "$M/.claude/audit-gate"
git -C "$M" config devkit.trunkMode true

# 1 unit: trunk_write - what is a write into main itself
python3 - "$DEVKIT_DIR" "$M" "$W" "$W2" > "$TMP/unit" 2>&1 <<'PY'
import sys
dk, m, w, w2 = sys.argv[1:5]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
E = lambda p: ("Edit", {"file_path": p}, "")
B = lambda c: ("Bash", {"command": c}, c)
cases = [   # (want, label, cwd, (tool, input, command))
    (True, "Edit a tracked file of main", m, E(f"{m}/src/a.py")),
    (True, "Write a new (not ignored) file in main", m, E(f"{m}/new.md")),
    (True, "a redirect in main", m, B("echo x > a.txt")),
    (True, "a git commit in main", m, B("git commit -qm x")),
    (True, "the gate run in main (it writes the tracked checklist)", m, B("python3 .agents/devkit/bin/post-fix-gate.py --run-tests")),
    (True, "a pull that merges in main", m, B("git pull --no-rebase origin main")),
    (True, "a redirect to $VAR run in main", m, B('echo x > "$OUT"')),
    (True, "an allowed segment does not excuse the next", m, B(f"agent-kit worktree finish {w} && echo x > a.txt")),
    (True, "cp into main from a worktree", w, B(f"cp /tmp/a {m}/b.txt")),
    (True, "cd to main from a worktree, then rm", w, B(f"cd {m} && rm -f README.md")),
    (True, "git -C main commit from a worktree", w, B(f"git -C {m} commit -qm x")),
    (True, "an allowed fetch with its own redirect into main", m, B("git fetch origin > src/a.py")),
    (True, "an allowed agent-kit worktree list redirected into main", m, B("agent-kit worktree list > README.md")),
    (True, "an allowed push appending its stderr into main", m, B("git push 2>> notes.md")),
    (False, "Edit in the nested session worktree", m, E(f"{w}/src/a.py")),
    (False, "Edit in a sibling worktree", m, E(f"{w2}/README.md")),
    (False, "Edit agent memory (ignored)", m, E(f"{m}/.agents/local/memory/claude-auto/n.md")),
    (False, "append to .claude/audit-gate (ignored)", m, B(f"echo x >> {m}/.claude/audit-gate/log")),
    (False, "a redirect in the worktree", w, B("echo x > a.txt")),
    (False, "a git commit in the worktree", w, B("git commit -qm x")),
    (False, "cd from main into the nested worktree, then write", m, B(f"cd {w} && echo y > f.txt")),
    (False, "agent-kit worktree finish (the integrator)", m, B(f"agent-kit worktree finish {w}")),
    (False, "worktree.py automerge (the integrator)", m, B(f"python3 -I {dk}/scripts/git/worktree.py automerge {w}")),
    (False, "fetch + push", m, B("git fetch origin && git push origin main")),
    (False, "pull --ff-only", m, B("git pull --ff-only")),
    (False, "a build run in main", m, B("npm test")),
    (False, "a redirect outside", m, B("grep -rn x . > /tmp/out.txt 2>/dev/null")),
    (False, "a read", m, B("git status --short && git log --oneline -3")),
]
bad = 0
for want, label, cwd, (tool, ti, cmd) in cases:
    got = sl.trunk_write(tool, ti, cmd, cwd, main, sw, "s")
    if got != want:
        bad += 1
        print(f"✖ {label}: want {want}, got {got}")
print(f"unit-bad={bad} of {len(cases)}")
PY
grep -q "unit-bad=0 " "$TMP/unit" && ok "trunk_write: $(grep -o 'of [0-9]*' "$TMP/unit") cases (main itself vs nested/sibling worktrees, ignored state, integrator, sync)" \
  || { fail "trunk_write cases"; grep "✖\|Error\|assert" "$TMP/unit" | head -12; }

# 2 the hook: a write into main is refused with what to do, and no lock is taken; a read and the integrator pass, also no lock
hook() {   # hook <event> <cwd> <tool> <json tool_input> [env...]: exit code; stderr in $TMP/err
  local ev="$1" cwd="$2" tool="$3" ti="$4"; shift 4
  python3 -c 'import json,sys; ev,cwd,tool,ti=sys.argv[1:5]; print(json.dumps({"hook_event_name":ev,"session_id":"sess-a","cwd":cwd,"tool_name":tool,"tool_input":json.loads(ti)}))' "$ev" "$cwd" "$tool" "$ti" \
    | env "$@" python3 -I "$SL" 2> "$TMP/err"
}
lockof() { [ -f "$(git -C "$1" rev-parse --absolute-git-dir)/devkit-session.lock" ]; }
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}"; rc=$?
[ "$rc" = 2 ] && grep -q "Trunk mode" "$TMP/err" && grep -q "EnterWorktree" "$TMP/err" && ! lockof "$M" && ok "Edit in main: refused (exit 2) with EnterWorktree as the way, main's lock not taken" \
  || fail "Edit in main (rc $rc, lock $(lockof "$M" && echo taken || echo none)): $(head -c 200 "$TMP/err")"
hook PreToolUse "$M" Bash '{"command": "git status --short"}'; r1=$?
hook PreToolUse "$M" Bash "{\"command\": \"agent-kit worktree finish $W\"}"; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && ! lockof "$M" && ok "  … a read and the integrator in main: allowed, still no lock on main" || fail "read/integrator in main: $r1 $r2 lock $(lockof "$M" && echo taken)"
hook PreToolUse "$W" Bash '{"command": "echo x > w.txt"}'; rc=$?
[ "$rc" = 0 ] && lockof "$W" && ! lockof "$M" && ok "a write in the session's worktree: allowed, the WORKTREE's lock taken (one session per worktree, as before)" \
  || fail "write in worktree (rc $rc): $(head -c 200 "$TMP/err")"
hook SessionStart "$M" "" '{}'; ! lockof "$M" && ok "SessionStart in main: no lock taken" || fail "SessionStart took main's lock in trunk mode"

# 3 a lock on main left from before trunk mode (a live other session) changes nothing: writes refused by the trunk rule, the integrator passes
python3 -c 'import json,os,sys,time; json.dump({"session_id":"old-holder","started":time.time(),"heartbeat":time.time(),"cwd":sys.argv[1],"pid":os.getppid()}, open(sys.argv[2],"w"))' \
  "$M" "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"
hook PreToolUse "$M" Bash "{\"command\": \"agent-kit worktree finish $W\"}"; r1=$?
hook PreToolUse "$M" Bash '{"command": "touch src/new.py"}'; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 2 ] && grep -q "Trunk mode" "$TMP/err" && ok "an old holder's lock on main: the integrator still passes, a write is refused by the trunk rule" || fail "old holder: $r1 $r2"
rm -f "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"

# 4 --status (R2): main says merge-only with exit 5; a worktree is judged as before
(cd / && python3 -I "$SL" --status "$M" >"$TMP/st" 2>&1); s1=$?
(cd / && python3 -I "$SL" --status "$W2" >/dev/null 2>&1); s2=$?
[ "$s1" = 5 ] && grep -q "trunk mode" "$TMP/st" && [ "$s2" = 0 ] && ok "--status: main exit 5 (merge-only, says how), a worktree exit 0" || fail "--status: main $s1, worktree $s2"

# 4b /clear or /resume: SessionStart under a new id, still in the worktree - the dead id's record follows the session (no gate checks main)
RD="$M/.claude/audit-gate/session_worktree"; mkdir -p "$RD" && printf '%s\n' "$W" > "$RD/sess-old"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-new","cwd":sys.argv[1]}))' "$W" | python3 -I "$SL" >/dev/null 2>&1
[ "$(cat "$RD/sess-new" 2>/dev/null)" = "$W" ] && [ ! -e "$RD/sess-old" ] && ok "SessionStart after /clear in the worktree: the record moves to the new session id" \
  || fail "reown at SessionStart: $(ls "$RD")"
python3 -I "$SL" --register --session sess-live --pid $$ "$M" >/dev/null 2>&1; printf '%s\n' "$W2" > "$RD/sess-live"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-x","cwd":sys.argv[1]}))' "$W2" | python3 -I "$SL" >/dev/null 2>&1
[ -e "$RD/sess-live" ] && [ ! -e "$RD/sess-x" ] && ok "  … a LIVE session's record is never taken over" || fail "a live session's record moved: $(ls "$RD")"

# 5 R7 and trunk mode off: the old rules, unchanged (main's lock taken by the first write)
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}" WORKTREE_TRUNK_MODE=0; rc=$?
[ "$rc" = 0 ] && lockof "$M" && ok "WORKTREE_TRUNK_MODE=0: a write in main is allowed and takes main's lock (as before)" || fail "R7 switch (rc $rc)"
rm -f "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"; git -C "$M" config devkit.trunkMode false
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}"; rc=$?
(cd / && python3 -I "$SL" --status --session sess-a "$M" >/dev/null 2>&1); s1=$?; (cd / && python3 -I "$SL" --status "$M" >/dev/null 2>&1); s2=$?
[ "$rc" = 0 ] && lockof "$M" && [ "$s1" = 0 ] && [ "$s2" = 3 ] && ok "trunk mode off: the old lock - --status 0 for its holder, 3 for anyone else" || fail "trunk mode off (rc $rc, status holder $s1 / other $s2)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_session_lock_trunk: PASS"; exit 0; } || { echo "test_session_lock_trunk: FAIL ($FAILS)"; exit 1; }
