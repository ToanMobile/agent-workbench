#!/usr/bin/env bash
# W1 R1 v6 (docs/workflow-improvements.md I.0): trunk mode gives every session its own worktree through Claude Code's WorktreeCreate hook.
# Configuring that hook REPLACES Claude's own `git worktree add` (code.claude.com hooks docs) for EnterWorktree, `claude --worktree` and
# every isolated subagent, so the hook must always hand back a path (last stdout line) unless there is truly no room, and its removal
# twin must never delete work. Cases:
#   1 hook-create: <main>/.claude/worktrees/<name>, detached, the owning session in its state, the path alone on stdout (real path)
#   2 trunk mode: a session's worktree takes no slot of WORKTREE_MAX (the 4th session would have nowhere to write); trunk mode off: the cap
#   3 the disk floor still refuses (exit 4, no path)   4 the same name again: the same worktree back   5 a name that is a path: refused
#   6 the DevKit set-up fails after git registered the worktree: a plain worktree is still handed back, its state final (not provisional)
#   7 hook-remove: a clean worktree goes; one with a commit main lacks stays (exit non-zero); main or a non-worktree: refused
#   8 `trunk on|off|status`: settings.local.json gets / loses exactly the two hooks, everything else kept, a broken file is never rewritten
#   9 automerge waits while `add` is still setting a worktree up (provisional state), and adopts one whose set-up died long ago
#  10 session_worktree.sh with no kit next to it: still a worktree for worktree-create, never a removal it cannot judge
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_TRUNK_MODE WORKTREE_MAX WORKTREE_DISK_MIN_GIB WORKTREE_DISK_WARN_GIB
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() { local p="$TMP/$1"; mkdir -p "$p" && G "$p" init -q -b main . && echo a > "$p/a.txt" && G "$p" add -A && G "$p" commit -qm i; }
create() {   # create <repo> <name> [session] [env...]: the hook's exit code; its stdout in $TMP/out, stderr in $TMP/err
  local r="$TMP/$1" name="$2" sid="${3:-sess-1}"; shift 3 2>/dev/null || shift $#
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"WorktreeCreate","name":sys.argv[1],"session_id":sys.argv[2],"cwd":sys.argv[3]}))' "$name" "$sid" "$r" \
    | (cd / && env "$@" python3 -I "$WT" hook-create) > "$TMP/out" 2> "$TMP/err"
}
state() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2]))' "$(G "$1" rev-parse --absolute-git-dir)/devkit-worktree.json" "$2" 2>/dev/null; }

# 1
repo a; G "$TMP/a" config devkit.trunkMode true
create a s1 sess-1; rc=$?; w="$TMP/a/.claude/worktrees/s1"
if [ "$rc" = 0 ] && [ "$(grep -v '^$' "$TMP/out" | tail -1)" = "$w" ] && [ "$(wc -l < "$TMP/out" | tr -d ' ')" = 1 ] \
    && [ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$w")" = "$w" ] \
    && [ -z "$(G "$w" symbolic-ref -q HEAD)" ] && [ "$(state "$w" session)" = sess-1 ] && [ "$(state "$w" provisional)" = None ]; then
  ok "hook-create: <main>/.claude/worktrees/<name>, detached, owner in the state, only the real path on stdout"
else
  fail "hook-create (rc $rc): out=$(tr '\n' '|' < "$TMP/out") session=$(state "$w" session) err=$(tail -2 "$TMP/err" | tr '\n' ' ')"
fi

# 2
repo b; G "$TMP/b" config devkit.trunkMode true; G "$TMP/b" worktree add -q --detach "$TMP/b-x" HEAD
create b s2 sess-2 WORKTREE_MAX=1; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/b/.claude/worktrees/s2" ] && ok "trunk mode: a session's worktree takes no slot of WORKTREE_MAX" || fail "trunk mode cap (rc $rc): $(tail -2 "$TMP/err")"
G "$TMP/b" config devkit.trunkMode false
create b s3 sess-3 WORKTREE_MAX=1; rc=$?
[ "$rc" = 4 ] && [ ! -e "$TMP/b/.claude/worktrees/s3" ] && [ ! -s "$TMP/out" ] && ok "  … trunk mode off: the cap holds (exit 4, no path)" || fail "cap without trunk mode (rc $rc): $(tail -2 "$TMP/err")"
G "$TMP/b" config devkit.trunkMode true
create b s4 sess-4 WORKTREE_MAX=1 WORKTREE_TRUNK_MODE=0; rc=$?
[ "$rc" = 4 ] && ok "  … WORKTREE_TRUNK_MODE=0: the cap holds again (R7)" || fail "R7 switch ignored by the cap (rc $rc)"

# 3
create a s5 sess-5 WORKTREE_DISK_MIN_GIB=99999999; rc=$?
[ "$rc" = 4 ] && [ ! -e "$TMP/a/.claude/worktrees/s5" ] && [ ! -s "$TMP/out" ] && grep -q "GiB" "$TMP/err" && ok "the disk floor refuses: exit 4, no path, it says why" || fail "disk floor (rc $rc): $(tail -2 "$TMP/err")"

# 4 the same name again BY THE SAME SESSION: the same worktree back, untouched. By ANOTHER session (R3 review 14/10: it used to get the first
#   session's tree, whose state still named the first as owner - the second merged it and could remove it): a worktree of its own
create a s1 sess-1; rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$TMP/a/.claude/worktrees/s1" ] && [ "$(state "$TMP/a/.claude/worktrees/s1" session)" = sess-1 ] \
  && ok "the same name again by the same session: the same worktree back, untouched" || fail "re-create (rc $rc): $(cat "$TMP/out")"
create a s1 sess-9; rc=$?; w4="$TMP/a/.claude/worktrees/s1-sess9"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w4" ] && [ "$(state "$w4" session)" = sess-9 ] && [ "$(state "$TMP/a/.claude/worktrees/s1" session)" = sess-1 ] \
  && G "$TMP/a" worktree list --porcelain | grep -q "^worktree $w4$" \
  && ok "  … by ANOTHER session: a worktree of its own (s1-sess9), the first one's owner and tree untouched" || fail "another session got (rc $rc): out=$(cat "$TMP/out") err=$(tail -2 "$TMP/err" | tr '\n' ' ')"
create a s1 sess-9; rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w4" ] && ok "  … and again: its own one back" || fail "second create of the other session (rc $rc): $(cat "$TMP/out")"
# OCR2 1: two ids that reduce to one folder suffix (sess-9, sess9 -> sess9): the third create finds the worktree of its own name taken by the
#   other session, `add` fails on the existing folder, and the fallback used to hand that tree back - never another session's tree: exit 1, no path
create a s1 sess9; rc=$?
[ "$rc" != 0 ] && [ ! -s "$TMP/out" ] && [ "$(state "$w4" session)" = sess-9 ] && grep -q "another session" "$TMP/err" \
  && ok "  … an id that maps to the SAME suffix as another session's: refused (no path), the owner's tree untouched" \
  || fail "suffix collision handed out a tree (rc $rc): out=$(cat "$TMP/out") err=$(tail -2 "$TMP/err" | tr '\n' ' ')"

# 4b two creates of ONE name at the same moment, by two sessions: one tree each, never the same path (the loser used to print the winner's);
#    they take turns on <common dir>/devkit-hook-create.lock, which a waiting create honours
mkcreate() {   # mkcreate <repo> <name> <session> <outfile>: hook-create in a process of its own (the race below runs two at once)
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"WorktreeCreate","name":sys.argv[1],"session_id":sys.argv[2],"cwd":sys.argv[3]}))' "$2" "$3" "$TMP/$1"     | (cd / && python3 -I "$WT" hook-create) > "$4" 2>/dev/null
}
f0=$FAILS
for n in 1 2 3; do
  mkcreate a race$n sess-ra$n "$TMP/ra$n" & p1=$!; mkcreate a race$n sess-rb$n "$TMP/rb$n" & p2=$!; wait $p1 $p2
  pa="$(tail -1 "$TMP/ra$n")"; pb="$(tail -1 "$TMP/rb$n")"
  { [ -n "$pa" ] && [ -n "$pb" ] && [ "$pa" != "$pb" ] && [ "$(state "$pa" session)" = sess-ra$n ] && [ "$(state "$pb" session)" = sess-rb$n ]; }     || fail "race $n: A got '$pa' (owner $(state "$pa" session)), B got '$pb' (owner $(state "$pb" session))"
done
[ "$FAILS" = "$f0" ] && ok "two sessions creating one name at the same moment: each gets a tree of its own, never the same path"
python3 -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT,0o600); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(3)' \
  "$(G "$TMP/a" rev-parse --path-format=absolute --git-common-dir)/devkit-hook-create.lock" "$TMP/held" & HOLDER=$!
for _ in $(seq 1 50); do [ -e "$TMP/held" ] && break; sleep 0.1; done
t0=$(date +%s); create a locked1 sess-1; rc=$?; t1=$(date +%s); wait "$HOLDER" 2>/dev/null
[ "$rc" = 0 ] && [ "$(( t1 - t0 ))" -ge 2 ] && [ -d "$TMP/a/.claude/worktrees/locked1" ] && ok "  … a create waits for the one that holds the lock (waited $(( t1 - t0 )) s), then goes ahead" || fail "create did not wait for the lock (rc $rc, $(( t1 - t0 )) s)"

# 5
for bad in "../x" ".hidden" "" "a//b" "a/" "/a" "a/../b" "a/.b"; do   # (R3 review P3a: "a/b" is no longer here, it is a legal EnterWorktree name - see 5b)
  create a "$bad" sess-1; rc=$?
  { [ "$rc" = 2 ] && [ ! -s "$TMP/out" ]; } || fail "name '$bad': rc $rc, out $(cat "$TMP/out")"
done
[ ! -e "$TMP/x" ] && [ ! -e "$TMP/a/.claude/x" ] && ok "a name that is a path (../x, a/../b, a//b, /a), hidden or empty: refused, nothing made" || fail "a bad name made something"

# 5b R3 review P3a: EnterWorktree takes "/"-separated names (fix/login: each segment letters, digits, dots, underscores, dashes); the hook used to refuse
#    them and so failed the EnterWorktree. The "/" becomes "-" in the folder name (one level under .claude/worktrees/, never a nested folder).
create a fix/login sess-5b; rc=$?; w5="$TMP/a/.claude/worktrees/fix-login"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w5" ] && [ -d "$w5" ] && [ ! -e "$TMP/a/.claude/worktrees/fix" ] && [ "$(state "$w5" session)" = sess-5b ] \
  && G "$TMP/a" worktree list --porcelain | grep -q "^worktree $w5$" && ok "a name with a slash (fix/login): the worktree is .claude/worktrees/fix-login, registered, owned" \
  || fail "name fix/login (rc $rc): out=$(cat "$TMP/out") err=$(tail -2 "$TMP/err" | tr '\n' ' ')"
create a fix/login sess-5b; rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w5" ] && [ "$(state "$w5" session)" = sess-5b ] && ok "  … the same slash name again by the same session: the same worktree back" || fail "fix/login again (rc $rc): $(cat "$TMP/out")"
create a fix/login sess-9; rc=$?; w5b="$TMP/a/.claude/worktrees/fix-login-sess9"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w5b" ] && [ "$(state "$w5b" session)" = sess-9 ] && [ "$(state "$w5" session)" = sess-5b ] \
  && ok "  … by another session: fix-login-sess9, the first one's tree and owner untouched" || fail "fix/login by another session (rc $rc): $(cat "$TMP/out")"
create a fix-login sess-8; rc=$?; w5c="$TMP/a/.claude/worktrees/fix-login-sess8"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w5c" ] && [ "$(state "$w5c" session)" = sess-8 ] && [ "$(state "$w5" session)" = sess-5b ] \
  && ok "  … fix-login (the same folder as fix/login) by a third session: its own one too" || fail "fix-login against fix/login (rc $rc): $(cat "$TMP/out")"

# 6 the set-up dies after registration (a kit whose installer fails, a main checkout with a DevKit profile): still a usable worktree
FK="$TMP/kit"; mkdir -p "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts" && ln -s "$DEVKIT_DIR/hooks" "$FK/hooks"
printf '#!/usr/bin/env bash\necho "installer broke" >&2\nexit 1\n' > "$FK/bin/install.sh"
repo c; G "$TMP/c" config devkit.trunkMode true; mkdir -p "$TMP/c/.agents" && echo '{"profile":"backend"}' > "$TMP/c/.agents/active-profile.json"
python3 -c 'import json,sys; print(json.dumps({"name":"s6","session_id":"sess-6","cwd":sys.argv[1]}))' "$TMP/c" \
  | (cd / && python3 -I "$FK/scripts/git/worktree.py" hook-create) > "$TMP/out" 2> "$TMP/err"; rc=$?
w6="$TMP/c/.claude/worktrees/s6"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$w6" ] && [ "$(state "$w6" session)" = sess-6 ] && [ "$(state "$w6" provisional)" = None ] \
  && grep -q "plain worktree" "$TMP/err" && ok "set-up failed after registration: the worktree is handed back, state final, owner kept" \
  || fail "set-up failure (rc $rc): out=$(cat "$TMP/out") provisional=$(state "$w6" provisional) err=$(tail -3 "$TMP/err" | tr '\n' ' ')"

# 6b R3 review P3b: the set-up raises something that is not a SystemExit (a full disk while copying, a bug of the kit): still a worktree handed back
boom() {   # boom <repo> <name> <session> <early|late>: hook-create with cmd_add raising; early = before git knows the worktree, late = after
  python3 -c 'import json,sys; print(json.dumps({"name":sys.argv[2],"session_id":sys.argv[3],"cwd":sys.argv[1]}))' "$TMP/$1" "$2" "$3" \
    | (cd / && python3 -I -c '
import subprocess, sys
sys.path.insert(0, sys.argv[1] + "/scripts/git")
import worktree
def early(main, args):
    raise OSError(28, "No space left on device")
def late(main, args):
    subprocess.run(["git", "-C", main, "worktree", "add", "-q", "--detach", args[0], "HEAD"], check=True)
    raise ValueError("late")
worktree.cmd_add = early if sys.argv[2] == "early" else late
sys.exit(worktree.main(["worktree.py", "hook-create"]))' "$DEVKIT_DIR" "$4") > "$TMP/out" 2> "$TMP/err"
}
repo g; G "$TMP/g" config devkit.trunkMode true
boom g e1 sess-e1 early; rc=$?; we="$TMP/g/.claude/worktrees/e1"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$we" ] && G "$TMP/g" worktree list --porcelain | grep -q "^worktree $we$" && [ "$(state "$we" session)" = sess-e1 ] \
  && ok "the set-up raises an OSError before git knows the worktree: a plain worktree is made and handed back, owned" \
  || fail "early exception (rc $rc): out=$(cat "$TMP/out") err=$(tail -3 "$TMP/err" | tr '\n' ' ')"
boom g e2 sess-e2 late; rc=$?; we="$TMP/g/.claude/worktrees/e2"
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$we" ] && [ "$(state "$we" session)" = sess-e2 ] && [ "$(state "$we" provisional)" = None ] \
  && ok "  … a ValueError after git registered it: handed back, its state final, owner kept" \
  || fail "late exception (rc $rc): out=$(cat "$TMP/out") provisional=$(state "$we" provisional) err=$(tail -3 "$TMP/err" | tr '\n' ' ')"

# 7 hook-remove
remove() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"WorktreeRemove","worktree_path":sys.argv[1]}))' "$1" \
  | (cd / && python3 -I "$WT" hook-remove) > "$TMP/out" 2> "$TMP/err"; }
create a s7 sess-7; remove "$TMP/a/.claude/worktrees/s7"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/a/.claude/worktrees/s7" ] && ok "hook-remove: a clean worktree is removed" || fail "clean removal (rc $rc): $(tail -2 "$TMP/err")"
create a s8 sess-8; echo work > "$TMP/a/.claude/worktrees/s8/w.txt" && G "$TMP/a/.claude/worktrees/s8" add w.txt && G "$TMP/a/.claude/worktrees/s8" commit -qm work
remove "$TMP/a/.claude/worktrees/s8"; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/a/.claude/worktrees/s8/w.txt" ] && ok "  … one with a commit main lacks: refused, the folder and the work stay" || fail "work lost on removal (rc $rc)"
remove "$TMP/a"; r1=$?; mkdir -p "$TMP/plain"; remove "$TMP/plain"; r2=$?; remove "relative/x"; r3=$?
[ "$r1" = 1 ] && [ "$r2" = 1 ] && [ "$r3" = 1 ] && [ -f "$TMP/a/a.txt" ] && [ -d "$TMP/plain" ] && ok "  … main itself, a plain folder, a relative path: refused, nothing removed" || fail "bad removals: $r1 $r2 $r3"

# 8 trunk on / off / status
repo d; mkdir -p "$TMP/d/.claude" && printf '{\n  "enableAllProjectMcpServers": true,\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}\n}\n' > "$TMP/d/.claude/settings.local.json"
(cd "$TMP/d" && python3 -I "$WT" trunk on >/dev/null 2>&1 && python3 -I "$WT" trunk on >/dev/null 2>&1); rc=$?
python3 - "$TMP/d/.claude/settings.local.json" <<'PY' && on_ok=1 || on_ok=0
import json, sys
d = json.load(open(sys.argv[1]))
h = d["hooks"]
cmds = {ev: [x["command"] for m in h.get(ev, []) for x in m["hooks"]] for ev in ("WorktreeCreate", "WorktreeRemove", "Stop")}
assert d.get("enableAllProjectMcpServers") is True, d
assert cmds["Stop"] == ["echo mine"], cmds
assert len(cmds["WorktreeCreate"]) == 1 and cmds["WorktreeCreate"][0].endswith("session_worktree.sh\" worktree-create"), cmds
assert len(cmds["WorktreeRemove"]) == 1 and cmds["WorktreeRemove"][0].endswith("session_worktree.sh\" worktree-remove"), cmds
PY
[ "$rc" = 0 ] && [ "$on_ok" = 1 ] && [ "$(G "$TMP/d" config --bool devkit.trunkMode)" = true ] && [ -L "$TMP/d/.claude/hooks/session_worktree.sh" ] \
  && G "$TMP/d" check-ignore -q .claude/worktrees/s1/ && [ -z "$(G "$TMP/d" status --porcelain -- .claude/worktrees)" ] \
  && ok "trunk on (twice): one WorktreeCreate + one WorktreeRemove hook, the user's keys and hooks kept, git config set, worktrees ignored" \
  || fail "trunk on (rc $rc, settings ok $on_ok): $(cat "$TMP/d/.claude/settings.local.json" | tr '\n' ' ' | cut -c1-300)"
(cd "$TMP/d" && python3 -I "$WT" trunk status) | grep -qE "trunk mode: on; .* hooks wired in " && ok "  … status: on, wired" || fail "status after on"   # (anchored: "hooks not wired in" must not pass)
(cd "$TMP/d" && python3 -I "$WT" trunk off >/dev/null 2>&1); rc=$?
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); h=d.get("hooks",{}); sys.exit(0 if "WorktreeCreate" not in h and "WorktreeRemove" not in h and h.get("Stop") and d.get("enableAllProjectMcpServers") else 1)' "$TMP/d/.claude/settings.local.json" \
  && [ "$rc" = 0 ] && [ -z "$(G "$TMP/d" config devkit.trunkMode)" ] && ok "  … trunk off: both hooks and the git config gone, the rest kept" || fail "trunk off (rc $rc)"
(cd "$TMP/d" && python3 -I "$WT" trunk status) | grep -qE "trunk mode: off; .* hooks not wired in " && ok "  … status: off, not wired" || fail "status after off"
printf '{ "broken": ' > "$TMP/d/.claude/settings.local.json"; cp "$TMP/d/.claude/settings.local.json" "$TMP/broken.bak"
(cd "$TMP/d" && python3 -I "$WT" trunk on >/dev/null 2>&1); rc=$?
[ "$rc" != 0 ] && cmp -s "$TMP/d/.claude/settings.local.json" "$TMP/broken.bak" && [ -z "$(G "$TMP/d" config devkit.trunkMode)" ] \
  && ok "  … a settings.local.json that is not JSON: refused, not rewritten, trunk mode stays off" || fail "broken settings rewritten or trunk mode set (rc $rc)"

# 9 automerge and a provisional state
repo e; G "$TMP/e" worktree add -q --detach "$TMP/e-w" HEAD; echo w > "$TMP/e-w/w.txt" && G "$TMP/e-w" add w.txt && G "$TMP/e-w" commit -qm w
prov() { python3 -c 'import json,sys,time; json.dump({"base":sys.argv[2],"baseline":{},"branch":None,"fp":2,"main":sys.argv[3],"session":"x","provisional":True,"at":time.time()-float(sys.argv[4])}, open(sys.argv[1],"w"))' \
  "$(G "$TMP/e-w" rev-parse --absolute-git-dir)/devkit-worktree.json" "$(G "$TMP/e" rev-parse HEAD)" "$TMP/e" "$1"; }
prov 5; out="$(cd "$TMP/e" && python3 -I "$WT" automerge "$TMP/e-w" 2>/dev/null | tail -1)"; rc=$?
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d["status"]=="blocked" and d.get("running") is True else 1)' "$out" && [ ! -f "$TMP/e/w.txt" ] \
  && ok "automerge waits while worktree add is still setting up (provisional state): nothing merged" || fail "provisional merged: $out"
prov 99999; (cd "$TMP/e" && python3 -I "$WT" automerge "$TMP/e-w" >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/e/w.txt" ] && ok "  … a set-up that died long ago: adopted and merged" || fail "stale provisional not adopted (rc $rc)"

# 10 the wrapper with no kit beside it
mkdir -p "$TMP/lone" && cp "$DEVKIT_DIR/hooks/session_worktree.sh" "$TMP/lone/"
repo f
python3 -c 'import json,sys; print(json.dumps({"name":"s10","session_id":"x","cwd":sys.argv[1]}))' "$TMP/f" | (cd "$TMP/f" && bash "$TMP/lone/session_worktree.sh" worktree-create) > "$TMP/out" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$TMP/f/.claude/worktrees/s10" ] && [ -d "$TMP/f/.claude/worktrees/s10" ] && ok "wrapper without a kit: worktree-create still makes and names a plain worktree" \
  || fail "wrapper fallback create (rc $rc): $(cat "$TMP/out") $(tail -2 "$TMP/err")"
python3 -c 'import json,sys; print(json.dumps({"name":"fix/login","session_id":"x","cwd":sys.argv[1]}))' "$TMP/f" | (cd "$TMP/f" && bash "$TMP/lone/session_worktree.sh" worktree-create) > "$TMP/out" 2> "$TMP/err"; rc=$?
python3 -c 'import json,sys; print(json.dumps({"name":"a//b","session_id":"x","cwd":sys.argv[1]}))' "$TMP/f" | (cd "$TMP/f" && bash "$TMP/lone/session_worktree.sh" worktree-create) > "$TMP/out2" 2> "$TMP/err2"; rc2=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$TMP/out")" = "$TMP/f/.claude/worktrees/fix-login" ] && [ -d "$TMP/f/.claude/worktrees/fix-login" ] && [ "$rc2" = 2 ] && [ ! -s "$TMP/out2" ] \
  && ok "  … a slash name there too (fix/login -> fix-login); an empty segment (a//b) refused" || fail "wrapper fallback slash name (rc $rc / $rc2): $(cat "$TMP/out") $(tail -2 "$TMP/err")"
python3 -c 'import json,sys; print(json.dumps({"worktree_path":sys.argv[1]}))' "$TMP/f/.claude/worktrees/s10" | bash "$TMP/lone/session_worktree.sh" worktree-remove >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/f/.claude/worktrees/s10" ] && ok "  … worktree-remove it cannot judge: exit 1, the worktree kept" || fail "wrapper fallback remove (rc $rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_trunk_hooks: PASS"; exit 0; } || { echo "test_worktree_trunk_hooks: FAIL ($FAILS)"; exit 1; }
