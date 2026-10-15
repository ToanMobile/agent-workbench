#!/usr/bin/env bash
# W1 R1 default (user, 2026-10-15: "mặc định là bật cho tất cả các repo cũng như devkit init"): trunk mode is ON unless a repo says otherwise.
# Before this, a repo without `devkit.trunkMode` ran the one-checkout-one-session mode, nothing ever turned the switch on, and a live session
# kept main from every other one. Cases:
#   1 trunk_mode(): no key = ON; `false` = off; `true` = on; WORKTREE_TRUNK_MODE=0 = off; a config git cannot read = off (the old behaviour)
#   2 session_lock --status on a repo with no key says merge-only (exit 5)
#   3 `trunk off` writes `false` (an unset key now means ON) and `trunk on` turns it back; status says which
#   4 `trunk wire` wires the two hooks + the symlink and leaves the key alone; twice = the same bytes; a repo that said `false` is left alone;
#     a settings.local.json that does not parse is never rewritten
#   5 `heal` (run by every SessionStart) wires a default repo and leaves a `false` repo alone
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_TRUNK_MODE WORKTREE_MAX WORKTREE_DISK_MIN_GIB WORKTREE_DISK_WARN_GIB
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
LOCK="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"; trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() { local p="$TMP/$1"; mkdir -p "$p" && G "$p" init -q -b main . && echo a > "$p/a.txt" && G "$p" add -A && G "$p" commit -qm i; }
mode() {   # mode <repo> [env-json]: what trunk_mode() answers for that repo
  local envjson="${2-}"; [ -n "$envjson" ] || envjson='{}'
  python3 -I -c 'import json, sys
sys.path.insert(0, sys.argv[1])
import session_worktree as sw
print(sw.trunk_mode(sys.argv[2], json.loads(sys.argv[3])))' "$DEVKIT_DIR/hooks" "$TMP/$1" "$envjson"
}
wired() {  # wired <repo>: both trunk hooks are in settings.local.json
  python3 -I -c 'import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print("no"); sys.exit()
h = d.get("hooks") or {}
print("yes" if h.get("WorktreeCreate") and h.get("WorktreeRemove") else "no")' "$TMP/$1/.claude/settings.local.json"
}
sum_of() { python3 -I -c 'import hashlib, sys
try: print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
except OSError: pass' "$TMP/$1/.claude/settings.local.json"; }   # no shasum/sha256sum: a minimal image has one or the other

# 1 the reader
repo a
[ "$(mode a)" = "True" ] && ok "trunk_mode: a repo with no devkit.trunkMode is ON by default" || fail "trunk_mode: no key answers $(mode a), want True"
G "$TMP/a" config devkit.trunkMode false
[ "$(mode a)" = "False" ] && ok "  … false = off" || fail "  … false answers $(mode a)"
G "$TMP/a" config devkit.trunkMode true
[ "$(mode a)" = "True" ] && ok "  … true = on" || fail "  … true answers $(mode a)"
G "$TMP/a" config --unset devkit.trunkMode
[ "$(mode a '{"WORKTREE_TRUNK_MODE":"0"}')" = "False" ] && ok "  … WORKTREE_TRUNK_MODE=0 = off everywhere (the user's switch)" || fail "  … env 0 answers $(mode a '{"WORKTREE_TRUNK_MODE":"0"}')"
repo u; chmod 000 "$TMP/u/.git/config"
if [ -r "$TMP/u/.git/config" ]; then
  echo "⚠ SKIP  a config this user can still read (root): the unreadable case cannot be built"
else
  [ "$(mode u)" = "False" ] && ok "  … a config git cannot read = off (the old behaviour, never a guess)" || fail "  … unreadable config answers $(mode u)"
fi
chmod 600 "$TMP/u/.git/config"

# 2 session_lock
repo b
(cd "$TMP/b" && CLAUDE_PROJECT_DIR="$TMP/b" python3 -I "$LOCK" --status >/dev/null 2>&1); rc=$?
[ "$rc" = 5 ] && ok "session_lock --status on a default repo: merge-only (exit 5)" || fail "session_lock --status on a default repo exits $rc, want 5"

# 3 on / off / status
repo c
(cd "$TMP/c" && python3 -I "$WT" trunk off >/dev/null 2>&1)
[ "$(G "$TMP/c" config --get devkit.trunkMode)" = "false" ] && ok "trunk off writes false (an unset key now means ON)" || fail "trunk off left devkit.trunkMode=$(G "$TMP/c" config --get devkit.trunkMode)"
(cd "$TMP/c" && python3 -I "$WT" trunk status 2>&1) | grep -q "trunk mode: off" && ok "  … status says off" || fail "  … status after trunk off: $(cd "$TMP/c" && python3 -I "$WT" trunk status 2>&1 | head -1)"
(cd "$TMP/c" && python3 -I "$WT" trunk on >/dev/null 2>&1)
[ "$(G "$TMP/c" config --get devkit.trunkMode)" = "true" ] && [ "$(wired c)" = "yes" ] && ok "trunk on turns it back on and wires the hooks" || fail "trunk on: key=$(G "$TMP/c" config --get devkit.trunkMode) wired=$(wired c)"
(cd "$TMP/c" && python3 -I "$WT" trunk status 2>&1) | grep -q "trunk mode: on" && ok "  … status says on" || fail "  … status after trunk on: $(cd "$TMP/c" && python3 -I "$WT" trunk status 2>&1 | head -1)"

# 4 wire
repo d
(cd "$TMP/d" && python3 -I "$WT" trunk wire >/dev/null 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(wired d)" = "yes" ] && [ -L "$TMP/d/.claude/hooks/session_worktree.sh" ] && ! G "$TMP/d" config --get devkit.trunkMode >/dev/null 2>&1; then
  ok "trunk wire: both hooks + the symlink, the devkit.trunkMode key left alone"
else
  fail "trunk wire (rc $rc): wired=$(wired d) link=$([ -L "$TMP/d/.claude/hooks/session_worktree.sh" ] && echo yes || echo no) key=$(G "$TMP/d" config --get devkit.trunkMode 2>&1)"
fi
before="$(sum_of d)"; (cd "$TMP/d" && python3 -I "$WT" trunk wire >/dev/null 2>&1)
[ -n "$before" ] && [ "$before" = "$(sum_of d)" ] && ok "  … run again: the same bytes (idempotent)" || fail "  … the second wire changed settings.local.json"
repo e; G "$TMP/e" config devkit.trunkMode false
(cd "$TMP/e" && python3 -I "$WT" trunk wire >/dev/null 2>&1)
[ ! -e "$TMP/e/.claude/settings.local.json" ] && ok "  … a repo that said false is left alone" || fail "  … trunk wire wired a repo that said false"
repo f; mkdir -p "$TMP/f/.claude"; printf '{ not json' > "$TMP/f/.claude/settings.local.json"; before="$(sum_of f)"
(cd "$TMP/f" && python3 -I "$WT" trunk wire >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ -n "$before" ] && [ "$before" = "$(sum_of f)" ] && ok "  … a settings.local.json that does not parse is never rewritten (exit 0)" || fail "  … broken settings.local.json: rc=$rc changed=$([ "$before" = "$(sum_of f)" ] && echo no || echo YES)"

# 5 heal (every SessionStart)
repo h
out="$(cd "$TMP/h" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" 2>&1)"   # the run that does the wiring
[ "$(wired h)" = "yes" ] && ok "heal wires a default repo at session start" || fail "heal left a default repo without the trunk hooks"
# the SessionStart text must not change (a resume says what a startup said), and nothing heal makes may show up in `git status`
[ -z "$out" ] && ok "  … heal says nothing about the wiring (the SessionStart text is the same every time)" || fail "  … heal printed: $out"
repo k; (cd "$TMP/k" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" >/dev/null 2>&1)
[ -z "$(G "$TMP/k" status --porcelain)" ] && ok "  … what heal wires is ignored by git (a clean status, nothing to commit by mistake)" || fail "  … heal left untracked files: $(G "$TMP/k" status --porcelain | tr '\n' ' ')"
repo g; mkdir -p "$TMP/g/.claude"; printf '{ not json' > "$TMP/g/.claude/settings.local.json"   # trunk is ON, the hooks cannot be wired: say so, once per SessionStart
out="$(cd "$TMP/g" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" 2>/dev/null)"
case "$out" in *"trunk wire"*) ok "  … heal says so when settings.local.json does not parse (the hooks stay unwired)" ;; *) fail "  … heal on a broken settings.local.json printed '$out'" ;; esac
[ "$(cat "$TMP/g/.claude/settings.local.json")" = '{ not json' ] && ok "  … and still leaves that file as it was" || fail "  … heal rewrote the broken settings.local.json"
repo i; G "$TMP/i" config devkit.trunkMode false
(cd "$TMP/i" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" >/dev/null 2>&1)
[ "$(wired i)" = "no" ] && ok "  … heal leaves a false repo alone" || fail "  … heal wired a repo that said false"

# 6 outside a repo, and a bare repo (review of the plan, 15/10): wire is silent there, and the default never turns a bare repo on
mkdir -p "$TMP/nogit"
(cd "$TMP/nogit" && python3 -I "$WT" trunk wire >"$TMP/nogit.out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$(ls -A "$TMP/nogit")" ] && [ ! -s "$TMP/nogit.out" ] && ok "trunk wire outside a repo: exit 0, silent, nothing written" || fail "trunk wire outside a repo: rc=$rc out=$(head -c 120 "$TMP/nogit.out") files=$(ls -A "$TMP/nogit" | tr '\n' ' ')"
mkdir -p "$TMP/bare.git" && G "$TMP/bare.git" init -q --bare
[ "$(mode bare.git)" = "False" ] && ok "trunk_mode: a bare repo is not ON by default (no checkout to merge into)" || fail "trunk_mode on a bare repo answers $(mode bare.git)"
(cd "$TMP/bare.git" && python3 -I "$WT" trunk wire >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/bare.git/.claude" ] && ok "  … trunk wire exits 0 and writes nothing into a bare repo" || fail "  … trunk wire on a bare repo: rc=$rc, .claude=$([ -e "$TMP/bare.git/.claude" ] && echo WRITTEN || echo none)"

# 6b "bare + worktrees" layout (`git clone --bare URL proj/.git`): the folder `proj` is no checkout, though its git dir is called `.git`
mkdir -p "$TMP/hub/.git" && G "$TMP/hub/.git" init -q --bare
[ "$(mode hub)" = "False" ] && ok "trunk_mode: a bare repo whose git dir is named .git is not ON by default either" || fail "trunk_mode on proj/.git (bare) answers $(mode hub)"
(cd "$TMP/hub/.git" && python3 -I "$WT" trunk wire >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/hub/.claude" ] && ok "  … trunk wire from inside proj/.git writes nothing into proj" || fail "  … trunk wire from proj/.git: rc=$rc, proj/.claude=$([ -e "$TMP/hub/.claude" ] && echo WRITTEN || echo none)"

# 7 a link that went dangling (the DevKit moved or was reinstalled) is made again at the next session start
repo j; (cd "$TMP/j" && python3 -I "$WT" trunk wire >/dev/null 2>&1)
rm -f "$TMP/j/.claude/hooks/session_worktree.sh"; ln -s "$TMP/nowhere/session_worktree.sh" "$TMP/j/.claude/hooks/session_worktree.sh"
(cd "$TMP/j" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" >/dev/null 2>&1)
[ -e "$TMP/j/.claude/hooks/session_worktree.sh" ] && ok "heal makes a dangling session_worktree.sh link again" || fail "heal left the dangling session_worktree.sh link"

# 8 a repo that TRACKS the settings file: `git check-ignore` without --no-index never calls a tracked path ignored, so every `trunk on` appended the line again
repo t; mkdir -p "$TMP/t/.claude"; printf '{}' > "$TMP/t/.claude/settings.local.json"
G "$TMP/t" add -f .claude/settings.local.json; G "$TMP/t" commit -qm tracked
(cd "$TMP/t" && python3 -I "$WT" trunk on >/dev/null 2>&1; python3 -I "$WT" trunk on >/dev/null 2>&1)
n="$(grep -c -x '/.claude/settings.local.json' "$(G "$TMP/t" rev-parse --path-format=absolute --git-common-dir)/info/exclude" 2>/dev/null)"
[ "$n" = 1 ] && ok "trunk on twice in a repo that tracks settings.local.json: the exclude line is there once" || fail "the exclude line for a tracked settings.local.json is there ${n:-0} times, want 1"

# 9 a config that holds the key twice (hand-edited, or two writers): `git config key value` refuses it (exit 5), --replace-all collapses it
repo w; printf '[devkit]\n\ttrunkMode = true\n[devkit]\n\ttrunkMode = true\n' >> "$TMP/w/.git/config"
(cd "$TMP/w" && python3 -I "$WT" trunk off >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(G "$TMP/w" config --get-all devkit.trunkMode | tr '\n' ' ')" = "false " ] && [ "$(mode w)" = "False" ] && ok "trunk off in a config that holds the key twice: one false, mode off" || fail "trunk off with a duplicated key: rc=$rc values=$(G "$TMP/w" config --get-all devkit.trunkMode | tr '\n' ' ')mode=$(mode w)"
(cd "$TMP/w" && python3 -I "$WT" trunk on >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(G "$TMP/w" config --get-all devkit.trunkMode | tr '\n' ' ')" = "true " ] && ok "  … and trunk on writes one true" || fail "  … trunk on after trunk off: rc=$rc values=$(G "$TMP/w" config --get-all devkit.trunkMode | tr '\n' ' ')"

# 10 agent-kit init (bin/install.sh -> setup_claude.sh) wires a new repo, and only the repo it was run on
INSTALL="$DEVKIT_DIR/bin/install.sh"
repo n; bash "$INSTALL" -t "$TMP/n" -a claude -p backend -y --no-githooks >/dev/null 2>&1
[ "$(wired n)" = "yes" ] && [ -L "$TMP/n/.claude/hooks/session_worktree.sh" ] && ok "init on a new repo wires WorktreeCreate/WorktreeRemove and the link" || fail "init on a new repo: wired=$(wired n)"
repo o; G "$TMP/o" config devkit.trunkMode false; bash "$INSTALL" -t "$TMP/o" -a claude -p backend -y --no-githooks >/dev/null 2>&1
[ "$(wired o)" = "no" ] && ok "  … init on a repo that said false wires nothing" || fail "  … init wired a repo that said false"
repo m; mkdir -p "$TMP/m/app"; bash "$INSTALL" -t "$TMP/m/app" -a claude -p backend -y --no-githooks >/dev/null 2>&1
[ "$(wired m)" = "no" ] && [ ! -e "$TMP/m/.claude/hooks/session_worktree.sh" ] && ok "  … init in a subfolder of a repo does not wire the repo above it" || fail "  … init in m/app wired the parent repo: wired=$(wired m)"

repo p; G "$TMP/p" worktree add -q --detach "$TMP/p-wt" >/dev/null 2>&1; bash "$INSTALL" -t "$TMP/p-wt" -a claude -p backend -y --no-githooks >/dev/null 2>&1
[ -d "$TMP/p-wt" ] && [ "$(wired p)" = "no" ] && [ ! -e "$TMP/p/.claude/hooks/session_worktree.sh" ] && ok "  … init in a linked worktree does not write into the main checkout" || fail "  … init in a linked worktree: worktree=$([ -d "$TMP/p-wt" ] && echo made || echo NOT-MADE) main wired=$(wired p)"

mkdir -p "$TMP/plain"; bash "$INSTALL" -t "$TMP/plain" -a claude -p backend -y --no-githooks >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(wired plain)" = "no" ] && ok "  … init in a folder that is not a git repo still succeeds (set -e must not trip on git rev-parse)" || fail "  … init in a non-git folder: exit $rc, wired=$(wired plain)"

# 10b the link cannot be made (`.claude/hooks` is a file): the hooks must NOT be written (they would call a script that is not there, and a
#     WorktreeCreate hook REPLACES Claude's own `git worktree add`), and heal must say the wiring failed
repo y; mkdir -p "$TMP/y/.claude"; : > "$TMP/y/.claude/hooks"
out="$(cd "$TMP/y" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" 2>/dev/null)"
[ "$(wired y)" = "no" ] && ok "a link that cannot be made leaves the hooks unwritten (no hook pointing at a missing script)" || fail "hooks were written although the link could not be made"
case "$out" in *"trunk wire"*) ok "  … and heal says the hooks could not be wired" ;; *) fail "  … heal on a failed link printed '$out'" ;; esac

repo y2; mkdir -p "$TMP/y2/.claude"; : > "$TMP/y2/.claude/hooks"   # `trunk on` is the same: the link first, the hooks only when it worked
(cd "$TMP/y2" && python3 -I "$WT" trunk on >/dev/null 2>&1); rc=$?
[ "$(wired y2)" = "no" ] && [ "$rc" != 0 ] && ok "trunk on with a link that cannot be made: exits non-zero, no hook written" || fail "trunk on with a link that cannot be made: rc=$rc wired=$(wired y2)"

# 11 `trunk off` is the user's way out: it must work whatever settings.local.json looks like (the key goes first)
repo x; mkdir -p "$TMP/x/.claude"; printf '{ not json' > "$TMP/x/.claude/settings.local.json"
(cd "$TMP/x" && python3 -I "$WT" trunk off >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(G "$TMP/x" config --get devkit.trunkMode)" = "false" ] && [ "$(mode x)" = "False" ] && ok "trunk off with a settings.local.json that does not parse: exit 0, key false, mode off" || fail "trunk off with a broken settings.local.json: rc=$rc key=$(G "$TMP/x" config --get devkit.trunkMode 2>&1) mode=$(mode x)"
[ "$(cat "$TMP/x/.claude/settings.local.json")" = '{ not json' ] && ok "  … and that file is still as it was" || fail "  … trunk off rewrote the broken settings.local.json"

repo z; (cd "$TMP/z" && python3 -I "$WT" trunk wire >/dev/null 2>&1); chmod 555 "$TMP/z/.claude"   # the settings cannot be rewritten: the key is still written, exit 0
if touch "$TMP/z/.claude/.probe" 2>/dev/null; then
  rm -f "$TMP/z/.claude/.probe"; echo "⚠ SKIP  a .claude this user can still write (root): the unwritable case cannot be built"
else
  (cd "$TMP/z" && python3 -I "$WT" trunk off >/dev/null 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(G "$TMP/z" config --get devkit.trunkMode)" = "false" ] && ok "trunk off with settings.local.json unwritable: exit 0, key false" || fail "trunk off with an unwritable .claude: rc=$rc key=$(G "$TMP/z" config --get devkit.trunkMode 2>&1)"
fi
chmod 755 "$TMP/z/.claude"

repo u2; (cd "$TMP/u2" && python3 -I "$WT" trunk off >/dev/null 2>&1)   # a repo that was never wired: opting out leaves nothing behind
[ ! -e "$TMP/u2/.claude" ] && [ -z "$(G "$TMP/u2" status --porcelain)" ] && ok "trunk off in a repo that was never wired writes no settings.local.json (a clean git status)" || fail "trunk off in an unwired repo left: $(G "$TMP/u2" status --porcelain | tr '\n' ' ')"
repo v2; mkdir -p "$TMP/v2/.claude/hooks"; chmod 555 "$TMP/v2/.claude"   # `trunk on` with settings.local.json unwritable: one message, no traceback, the key is written first
if touch "$TMP/v2/.claude/.probe" 2>/dev/null; then
  rm -f "$TMP/v2/.claude/.probe"; echo "⚠ SKIP  a .claude this user can still write (root): the unwritable case cannot be built"
else
  out="$(cd "$TMP/v2" && python3 -I "$WT" trunk on 2>&1)"; rc=$?
  case "$out" in *Traceback*) fail "trunk on with an unwritable .claude: a raw traceback: $(echo "$out" | tail -1)" ;; *) [ "$rc" != 0 ] && ok "trunk on with settings.local.json unwritable: a message and a non-zero exit, no traceback" || fail "trunk on with an unwritable .claude exited 0: $out" ;; esac
fi
chmod 755 "$TMP/v2/.claude"

# 12 a repo wired by the earlier `trunk on` (hooks and link there, only /.claude/worktrees/ excluded): heal still hides what it made from git status
repo q; (cd "$TMP/q" && python3 -I "$WT" trunk wire >/dev/null 2>&1); printf '/.claude/worktrees/\n' > "$TMP/q/.git/info/exclude"
before="$(G "$TMP/q" status --porcelain | tr '\n' ' ')"
(cd "$TMP/q" && python3 -I "$WT" heal "--devkit=$DEVKIT_DIR" >/dev/null 2>&1)
[ -n "$before" ] && [ -z "$(G "$TMP/q" status --porcelain)" ] && ok "heal on a repo that is already wired restores the excludes (a clean git status)" || fail "heal on an already-wired repo: status before='$before' after='$(G "$TMP/q" status --porcelain | tr '\n' ' ')'"

echo "failures: $FAILS"
[ "$FAILS" -eq 0 ]
