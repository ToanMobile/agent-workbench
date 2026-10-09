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
G=77777777-7777-4777-8777-777777777777
ROOT="$TMP/root"; PROJ="$TMP/projects"; mkdir -p "$ROOT/-proj" "$PROJ/-proj" "$TMP/outside"
age() { python3 -c 'import os,sys,time; t=time.time()-float(sys.argv[2])*3600
for dp, dn, fn in os.walk(sys.argv[1], topdown=False):
    for n in fn + dn: os.utime(os.path.join(dp, n), (t, t), follow_symlinks=False)
os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
mk() { mkdir -p "$ROOT/-proj/$1/scratchpad" && echo x > "$ROOT/-proj/$1/scratchpad/big"; age "$ROOT/-proj/$1" "$2"; }
setup() {
  rm -rf "$ROOT/-proj"/* "$ROOT/$E" "$PROJ/-proj"/*
  mk "$A" 200                                      # dead 200 h (past the 7-day TTL): pruned
  mk "$G" 30                                       # idle 30 h: may be a session left open a day — kept (audit T0023)
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
[ "$rc" = 0 ] && [ ! -e "$ROOT/-proj/$A" ] && ok "prune: a session dir dead for 200 h (past the 7-day TTL) is removed" || fail "prune left the dead dir (rc=$rc): $(cat "$TMP/out")"
[ -d "$ROOT/-proj/$G" ] && ok "  … one idle for 30 h is kept (a session left open a day is not a dead one)" || fail "prune removed a 30 h idle dir"
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

# Audit T0023 (TOCTOU): the project dir is swapped for a symlink AFTER the listing — the removal must not follow it.
setup; mkdir -p "$TMP/swap/$A" && echo keep > "$TMP/swap/$A/precious"
DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" python3 -I - "$DEVKIT_DIR/scripts/governance" "$ROOT" "$TMP/swap" "$G" <<'PY' > "$TMP/out" 2>&1
import os, sys
sys.path.insert(0, sys.argv[1])
import scratch_cleanup as sc
root, swap = sys.argv[2], sys.argv[3]
listed = list(sc.session_dirs(root))
os.rename(os.path.join(root, "-proj"), os.path.join(root, "-proj.real"))     # the swap, between listing and removal
os.symlink(swap, os.path.join(root, "-proj"))
for slug, sid, path in listed:
    if slug == "-proj":
        sc.remove(root, slug, sid, "test")
os.unlink(os.path.join(root, "-proj"))
os.rename(os.path.join(root, "-proj.real"), os.path.join(root, "-proj"))
sc.remove(root, "-proj", sys.argv[4], "control")                              # control: a normal session dir IS removed
PY
rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/swap/$A/precious" ] && [ ! -e "$ROOT/-proj/$G" ] \
  && ok "TOCTOU: a project dir swapped for a symlink after the listing is not followed (a normal one is removed)" \
  || fail "TOCTOU (rc=$rc, swap kept=$([ -f "$TMP/swap/$A/precious" ] && echo y || echo n)): $(tail -3 "$TMP/out")"

# Review 2026-10-09 (P1): a session left open at the prompt for days is alive — Claude Code keeps
# <claude home>/sessions/<pid>.json {pid, sessionId}; a live pid keeps its dir whatever the mtimes say. A stale file of a dead
# pid does not. Also kept: a dir whose task output is fresh, and a dir that cannot be read (never remove what cannot be judged).
H=88888888-8888-4888-8888-888888888888; I=99999999-9999-4999-8999-999999999999; J=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
K=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb; L=cccccccc-cccc-4ccc-8ccc-cccccccccccc
SESS="$TMP/sessions"; mkdir -p "$SESS"; rm -f "$SESS"/*.json
setup; mk "$H" 200; mk "$I" 200; mk "$J" 200; mk "$K" 200
python3 -c 'import json,sys; json.dump({"pid": int(sys.argv[2]), "sessionId": sys.argv[3]}, open(sys.argv[1] + "/%s.json" % sys.argv[2], "w"))' "$SESS" "$$" "$H"
python3 -c 'import json,sys; json.dump({"pid": 999999, "sessionId": sys.argv[2]}, open(sys.argv[1] + "/999999.json", "w"))' "$SESS" "$I"
mkdir -p "$ROOT/-proj/$J/tasks"; age "$ROOT/-proj/$J" 200; echo out > "$ROOT/-proj/$J/tasks/x.output"   # only the task output is fresh
age "$ROOT/-proj/$J/tasks" 200; touch "$ROOT/-proj/$J/tasks/x.output"; age "$ROOT/-proj/$J" 200 2>/dev/null; touch "$ROOT/-proj/$J/tasks/x.output"
python3 -c 'import os,sys,time; t=time.time()-200*3600; [os.utime(p,(t,t)) for p in sys.argv[1:]]' "$ROOT/-proj/$J" "$ROOT/-proj/$J/tasks"
mkdir -p "$ROOT/-proj/$K/tasks"; age "$ROOT/-proj/$K" 200; chmod 000 "$ROOT/-proj/$K/tasks"   # a level it cannot read
M=dddddddd-dddd-4ddd-8ddd-dddddddddddd; mk "$M" 200; echo x > "$ROOT/-proj/$M/gone"; age "$ROOT/-proj/$M" 200
rm -f "$ROOT/-proj/$M/gone"                                                   # an entry removed just now: the dir itself is fresh
DEVKIT_CLAUDE_SESSIONS="$SESS" run --prune --keep "$F"; rc=$?
chmod 755 "$ROOT/-proj/$K/tasks"
[ -f "$ROOT/-proj/$M/scratchpad/big" ] && ok "  … a dir whose own mtime is fresh (an entry just removed) is kept" || fail "prune removed a dir with a fresh own mtime"
[ "$rc" = 0 ] && [ -d "$ROOT/-proj/$H" ] && ok "prune: a 200 h old dir of a session whose Claude process is alive is kept" || fail "prune removed a live process's session dir (rc=$rc)"
[ ! -e "$ROOT/-proj/$I" ] && ok "  … a stale sessions/<pid>.json of a dead pid does not keep it" || fail "a dead pid's session file kept its dir"
[ -f "$ROOT/-proj/$J/tasks/x.output" ] && ok "  … a dir whose task output was just written is kept" || fail "prune removed a dir with fresh task output"
if [ "$(id -u)" = 0 ]; then   # root reads a mode-000 dir: there is no unreadable level to judge (a root container, 2026-10-09)
  ok "  … (skipped as root: chmod 000 does not stop root from reading, the cannot-judge case cannot be built)"
else
  [ -f "$ROOT/-proj/$K/scratchpad/big" ] && ok "  … a dir with a level that cannot be read is kept (cannot judge)" || fail "prune removed a dir it could not judge"
fi
setup; mk "$L" 0
python3 -c 'import json,sys; json.dump({"pid": int(sys.argv[2]), "sessionId": sys.argv[3]}, open(sys.argv[1] + "/%s.json" % sys.argv[2], "w"))' "$SESS" "$$" "$L"
DEVKIT_CLAUDE_SESSIONS="$SESS" run --end "$L" --self-pid 1234567; rc=$?
[ "$rc" = 0 ] && [ -d "$ROOT/-proj/$L" ] && ok "end: kept while ANOTHER live process holds the same session id (--resume elsewhere)" || fail "end removed a session another live process holds"
DEVKIT_CLAUDE_SESSIONS="$SESS" run --end "$L" --self-pid "$$"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$ROOT/-proj/$L" ] && ok "  … and removed when the only holder is the ending process itself" || fail "end kept the session of the ending process"
rm -f "$SESS"/*.json
# SessionEnd with reason clear / resume: the process lives on (a new session id) — its dir is left to the prune.
setup
python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "hook_event_name": "SessionEnd", "reason": "clear", "cwd": sys.argv[2]}))' "$B" "$REPO" \
  | DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" DEVKIT_CLAUDE_SESSIONS="$SESS" CLAUDE_PROJECT_DIR="$REPO" bash "$DEVKIT_DIR/hooks/session_lock.sh" > /dev/null 2>&1
python3 -c 'import time; time.sleep(1.5)'
[ -d "$ROOT/-proj/$B" ] && ok "hook: SessionEnd with reason clear leaves the dir (the prune takes it later)" || fail "SessionEnd reason=clear removed the dir"

# … and a swap landing AFTER the project dir was opened (between open and rmtree): removal goes through the opened fd.
setup; mkdir -p "$TMP/swap2/$A" && echo keep > "$TMP/swap2/$A/precious"
DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" python3 -I - "$DEVKIT_DIR/scripts/governance" "$ROOT" "$TMP/swap2" "$A" <<'PY' > "$TMP/out" 2>&1
import os, sys
sys.path.insert(0, sys.argv[1])
import scratch_cleanup as sc
root, swap, sid = sys.argv[2], sys.argv[3], sys.argv[4]
real_fstat, done = os.fstat, []
def racing_fstat(fd):
    if not done:   # the swap lands right after the opens
        done.append(1)
        os.rename(os.path.join(root, "-proj"), os.path.join(root, "-proj.real"))
        os.symlink(swap, os.path.join(root, "-proj"))
    return real_fstat(fd)
sc.os.fstat = racing_fstat
sc.remove(root, "-proj", sid, "race")
print("removed from the opened dir:", not os.path.exists(os.path.join(root, "-proj.real", sid)))
PY
rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/swap2/$A/precious" ] && grep -q "removed from the opened dir: True" "$TMP/out" \
  && ok "TOCTOU: a swap after the open removes from the opened dir, never through the new symlink" \
  || fail "post-open swap (rc=$rc): $(tail -3 "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_scratch_cleanup: all passed" || { echo "❌ test_scratch_cleanup: $FAILS failed"; exit 1; }
