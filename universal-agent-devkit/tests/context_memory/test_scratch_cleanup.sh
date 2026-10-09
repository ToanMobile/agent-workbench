#!/usr/bin/env bash
# Regression test (user 2026-10-09: "thư mục tạm của Claude Code chiếm tới 33 GB … mày phải có cơ chế dùng xong xoá đi"):
# Claude Code keeps one temp dir per session under /tmp/claude-<uid>/<project-slug>/<session-uuid>/ (scratchpad, task
# outputs) and never removes it; one session's two CoW repo copies (29 GB) filled the boot disk to 99 %.
# scripts/governance/scratch_cleanup.py: --end <sid> removes that session's dir (SessionEnd), --prune removes the dirs of
# sessions dead for more than the TTL (newest file AND the session's transcript older than it; SessionStart). It only ever
# touches <root>/<slug>/<uuid>/ real directories: never a symlink, a non-UUID name, another depth, or a root that is not a
# real directory of this user. bin/session_lock.py starts both from the SessionStart / SessionEnd hooks it already owns.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SC="$DEVKIT_DIR/scripts/governance/scratch_cleanup.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
A=11111111-1111-4111-8111-111111111111; B=22222222-2222-4222-8222-222222222222; C=33333333-3333-4333-8333-333333333333
D=44444444-4444-4444-8444-444444444444; E=55555555-5555-4555-8555-555555555555; F=66666666-6666-4666-8666-666666666666
ROOT="$TMP/root"; PROJ="$TMP/projects"; mkdir -p "$ROOT/-proj" "$PROJ/-proj" "$TMP/outside"
age() { python3 -c 'import os,sys,time; t=time.time()-float(sys.argv[2])*3600
for dp, dn, fn in os.walk(sys.argv[1], topdown=False):
    for n in fn + dn: os.utime(os.path.join(dp, n), (t, t), follow_symlinks=False)
os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
mk() { mkdir -p "$ROOT/-proj/$1/scratchpad" && echo x > "$ROOT/-proj/$1/scratchpad/big"; age "$ROOT/-proj/$1" "$2"; }
setup() {
  rm -rf "$ROOT/-proj"/* "$ROOT/$E" "$PROJ/-proj"/*
  mk "$A" 30                                       # dead 30 h: pruned
  mk "$B" 0                                        # fresh: kept
  mk "$C" 30; echo '{}' > "$PROJ/-proj/$C.jsonl"   # temp files old, transcript written now: a live session, kept
  mkdir -p "$ROOT/-proj/notauuid" && echo x > "$ROOT/-proj/notauuid/f"; age "$ROOT/-proj/notauuid" 30
  echo keep > "$TMP/outside/precious"; age "$TMP/outside" 30; ln -s "$TMP/outside" "$ROOT/-proj/$D"
  mkdir -p "$ROOT/$E" && echo x > "$ROOT/$E/f"; age "$ROOT/$E" 30       # wrong depth
  mk "$F" 30                                       # dead, but the session asking to keep it
  rm -rf "$TMP/elsewhere" "$ROOT/-linked"; mkdir -p "$TMP/elsewhere/$A" && echo keep > "$TMP/elsewhere/$A/precious"
  age "$TMP/elsewhere" 30; ln -s "$TMP/elsewhere" "$ROOT/-linked"   # a project slug that is a symlink: never followed
}
run() { DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" python3 -I "$SC" "$@" > "$TMP/out" 2>&1; }

[ -f "$SC" ] || fail "scripts/governance/scratch_cleanup.py missing"
setup; run --prune --keep "$F"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$ROOT/-proj/$A" ] && ok "prune: a session dir dead for 30 h is removed" || fail "prune left the dead dir (rc=$rc): $(cat "$TMP/out")"
[ -d "$ROOT/-proj/$B" ] && ok "  … a fresh session dir is kept" || fail "prune removed a fresh dir"
[ -d "$ROOT/-proj/$C" ] && ok "  … an old dir whose transcript is being written (live session) is kept" || fail "prune removed a live session's dir"
[ -d "$ROOT/-proj/$F" ] && ok "  … --keep (the session running the prune) is kept" || fail "prune removed the --keep session"
[ -d "$ROOT/-proj/notauuid" ] && [ -d "$ROOT/$E" ] && ok "  … a non-UUID name and a dir at another depth are never touched" || fail "prune touched a non-session dir"
[ -L "$ROOT/-proj/$D" ] && [ -f "$TMP/outside/precious" ] && ok "  … a symlink is never followed or removed" || fail "prune followed or removed a symlink"
[ -f "$TMP/elsewhere/$A/precious" ] && ok "  … a project slug that is a symlink is never followed" || fail "prune followed a symlinked project slug"

setup; run --end "$B"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$ROOT/-proj/$B" ] && [ -d "$ROOT/-proj/$A" ] && ok "end: the ending session's dir is removed, nothing else" || fail "end (rc=$rc): $(cat "$TMP/out")"
run --end "not-a-uuid"; [ "$?" = 2 ] && ok "end: a session id that is not a UUID is refused (exit 2)" || fail "end accepted a non-UUID id"

setup; mv "$ROOT" "$TMP/realroot"; ln -s "$TMP/realroot" "$ROOT"
run --prune; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/realroot/-proj/$A" ] && ok "a root that is a symlink is refused: nothing removed" || fail "symlinked root was pruned (rc=$rc)"
rm "$ROOT"; mv "$TMP/realroot" "$ROOT"

# The hooks start it: SessionEnd removes the session's own dir (detached; give it a moment).
REPO="$TMP/repo"; mkdir -p "$REPO" && git -C "$REPO" init -q .
setup
python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "hook_event_name": "SessionEnd", "cwd": sys.argv[2]}))' "$B" "$REPO" \
  | DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" CLAUDE_PROJECT_DIR="$REPO" bash "$DEVKIT_DIR/hooks/session_lock.sh" > /dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$ROOT/-proj/$B" ] || break; python3 -c 'import time; time.sleep(0.2)'; done
[ ! -e "$ROOT/-proj/$B" ] && [ -d "$ROOT/-proj/$A" ] && ok "hook: SessionEnd removes the ending session's temp dir" || fail "SessionEnd did not remove its temp dir"
python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "hook_event_name": "SessionStart", "cwd": sys.argv[2]}))' "$F" "$REPO" \
  | DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" CLAUDE_PROJECT_DIR="$REPO" bash "$DEVKIT_DIR/hooks/session_lock.sh" > /dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$ROOT/-proj/$A" ] || break; python3 -c 'import time; time.sleep(0.2)'; done
[ ! -e "$ROOT/-proj/$A" ] && [ -d "$ROOT/-proj/$F" ] && [ -d "$ROOT/-proj/$C" ] && ok "hook: SessionStart prunes dead sessions, keeps itself and live ones" || fail "SessionStart prune wrong"

[ "$FAILS" -eq 0 ] && echo "✅ test_scratch_cleanup: all passed" || { echo "❌ test_scratch_cleanup: $FAILS failed"; exit 1; }
