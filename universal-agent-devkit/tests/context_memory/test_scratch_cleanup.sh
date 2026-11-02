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
REAL_DK_OLD=""; SLASH_TMP_BOX=""; DK_PAR=""
trap 'rm -rf "$TMP" ${REAL_DK_OLD:+"$REAL_DK_OLD"} ${DK_PAR:+"$DK_PAR"} ${SLASH_TMP_BOX:+"$SLASH_TMP_BOX"}' EXIT INT TERM HUP
export DEVKIT_TEST_TMP_ROOT="$TMP/no-test-tmp"   # --prune also sweeps test temp dirs: never the real TMPDIR here
# Host state (#573): live_sessions() reads <CLAUDE_CONFIG_DIR or ~/.claude>/sessions/*.json. Pin CLAUDE_CONFIG_DIR (and HOME, git config) to
# test-owned places for EVERY call; claude_home()/sessions stays the path under test, the other live-session cases set DEVKIT_CLAUDE_SESSIONS per call.
unset DEVKIT_CLAUDE_SESSIONS DEVKIT_DK_TMP_ROOT DEVKIT_CLEAN_PROJECT DEVKIT_SCRATCH_CLEANUP   # runner/host state: each call below sets what it needs
mkdir -p "$TMP/home" "$TMP/claude-home/sessions"
export CLAUDE_CONFIG_DIR="$TMP/claude-home" HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null
# lsof of the test's own processes only (this shell and its direct children: the HOLD cwd holder, the socket server): never a
# machine-wide snapshot, whose size and time depend on the host. Its exit status is lsof's own.
cat > "$TMP/lsof-own" <<LSOF
#!/bin/sh
P=$$
for c in \$(pgrep -P $$ 2>/dev/null); do P="\$P,\$c"; done
exec "\$(command -v lsof || echo /usr/sbin/lsof)" -nPw -p "\$P" -Fn
LSOF
chmod +x "$TMP/lsof-own"
export DEVKIT_LSOF="$TMP/lsof-own"
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
SESS="$TMP/claude-home/sessions"; mkdir -p "$SESS"   # the real claude_home()/sessions path: the first live-session case passes no DEVKIT_CLAUDE_SESSIONS; rm -f "$SESS"/*.json
setup; mk "$H" 200; mk "$I" 200; mk "$J" 200; mk "$K" 200
python3 -c 'import json,sys; json.dump({"pid": int(sys.argv[2]), "sessionId": sys.argv[3]}, open(sys.argv[1] + "/%s.json" % sys.argv[2], "w"))' "$SESS" "$$" "$H"
python3 -c 'import json,sys; json.dump({"pid": 999999, "sessionId": sys.argv[2]}, open(sys.argv[1] + "/999999.json", "w"))' "$SESS" "$I"
mkdir -p "$ROOT/-proj/$J/tasks"; age "$ROOT/-proj/$J" 200; echo out > "$ROOT/-proj/$J/tasks/x.output"   # only the task output is fresh
age "$ROOT/-proj/$J/tasks" 200; touch "$ROOT/-proj/$J/tasks/x.output"; age "$ROOT/-proj/$J" 200 2>/dev/null; touch "$ROOT/-proj/$J/tasks/x.output"
python3 -c 'import os,sys,time; t=time.time()-200*3600; [os.utime(p,(t,t)) for p in sys.argv[1:]]' "$ROOT/-proj/$J" "$ROOT/-proj/$J/tasks"
mkdir -p "$ROOT/-proj/$K/tasks"; age "$ROOT/-proj/$K" 200; chmod 000 "$ROOT/-proj/$K/tasks"   # a level it cannot read
M=dddddddd-dddd-4ddd-8ddd-dddddddddddd; mk "$M" 200; echo x > "$ROOT/-proj/$M/gone"; age "$ROOT/-proj/$M" 200
rm -f "$ROOT/-proj/$M/gone"                                                   # an entry removed just now: the dir itself is fresh
run --prune --keep "$F"; rc=$?
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

# ── Test temp sweep (2026-10-19: suites killed before their EXIT trap left ~8 GiB of fixture dirs in TMPDIR, disk 99 %).
# Only a TEST_TMP_PREFIXES name, a real dir, nothing in its tree newer than the TTL, no process holding it; a worktree inside
# whose admin repo lives elsewhere is pruned there. Never an anonymous mktemp name, a production prefix, a symlink, a file.
TR="$TMP/troot"
tmk() { mkdir -p "$TR/$1/sub" && echo x > "$TR/$1/sub/f"; age "$TR/$1" "$2"; }
sweep() { DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" DEVKIT_TEST_TMP_ROOT="$TR" python3 -I "$SC" "$@" > "$TMP/out" 2>&1; }
tsetup() {
  [ -d "$TR" ] && { chflags -R nouchg "$TR" 2>/dev/null; chmod -R u+rwX "$TR" 2>/dev/null; }
  rm -rf "$TR" "$TMP/admin" "$TMP/outside2"; mkdir -p "$TR"
  tmk hookctx.OLD1 10                                                   # stale test dir: removed
  tmk hookctx.NEW1 0                                                    # fresh: kept
  tmk hookgr.DEEP 10; echo y > "$TR/hookgr.DEEP/sub/new"                # old top, a file deep inside written now: kept
  tmk tmp.ANON 10                                                       # anonymous mktemp name: cannot be proven, kept
  tmk agpm-run-PROD 10                                                  # antigravity-pm production prefix: kept
  tmk devkit-idem-XXXXXX.RO 10; chflags uchg "$TR/devkit-idem-XXXXXX.RO/sub/f" 2>/dev/null; chmod 555 "$TR/devkit-idem-XXXXXX.RO/sub"
  mkdir -p "$TMP/outside2" && echo keep > "$TMP/outside2/precious"; ln -s "$TMP/outside2" "$TR/hookte.LINK"
  echo f > "$TR/hookwg.FILE"; age "$TR/hookwg.FILE" 10                  # a file, not a dir: kept
  tmk hookrestore.HELD 10                                               # a process has its cwd in it: kept
  git init -q "$TMP/admin" && git -C "$TMP/admin" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$TMP/admin" worktree add -q --detach "$TR/sb-ghread-test.WT" 2>/dev/null; age "$TR/sb-ghread-test.WT" 10
  [ -f "$TR/sb-ghread-test.WT/.git" ] || fail "fixture: the worktree was not created (the prune case would pass vacuously)"
  git -C "$TMP/admin" worktree add -q --detach "$TMP/admin-other-wt" 2>/dev/null
  rm -rf "$TMP/admin-other-wt"                                          # admin's OTHER worktree, folder missing: not ours
}
kept_all() {
  [ -d "$TR/hookctx.NEW1" ] && [ -d "$TR/hookgr.DEEP" ] && [ -d "$TR/tmp.ANON" ] && [ -d "$TR/agpm-run-PROD" ] \
    && [ -L "$TR/hookte.LINK" ] && [ -f "$TMP/outside2/precious" ] && [ -f "$TR/hookwg.FILE" ] && [ -d "$TR/hookrestore.HELD" ]
}
if ! command -v lsof >/dev/null 2>&1 && [ ! -x /usr/sbin/lsof ]; then
  ok "sweep: (skipped: no lsof on this host; only the no-lsof case below applies)"
else
tsetup
(cd "$TR/hookrestore.HELD" && exec sleep 60) & HOLD=$!
LSOF_BIN="$(command -v lsof || echo /usr/sbin/lsof)"
for _ in $(seq 1 100); do   # wait until lsof itself sees the cwd (a loaded host starts the subshell late)
  "$LSOF_BIN" -nPw -p "$HOLD" -Fn 2>/dev/null | grep -q 'hookrestore.HELD' && break; python3 -c 'import time; time.sleep(0.1)'
done
sweep --sweep-tmp; rc=$?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null
[ "$rc" = 0 ] && [ ! -e "$TR/hookctx.OLD1" ] && ok "sweep: a stale test temp dir (known prefix, older than 6 h, not held) is removed" \
  || fail "sweep left a stale test dir (rc=$rc): $(tail -3 "$TMP/out")"
[ ! -e "$TR/devkit-idem-XXXXXX.RO" ] && ok "  … one with a read-only subdir and an immutable file is removed too" || fail "sweep could not remove a read-only / uchg leftover"
[ ! -e "$TR/sb-ghread-test.WT" ] && ! git -C "$TMP/admin" worktree list --porcelain | grep -q 'sb-ghread-test.WT' \
  && git -C "$TMP/admin" worktree list --porcelain | grep -q 'admin-other-wt' \
  && ok "  … a fixture worktree whose admin repo is elsewhere is removed and only ITS registration is dropped there" \
  || fail "worktree leftover: dir=$([ -e "$TR/sb-ghread-test.WT" ] && echo kept || echo gone) $(git -C "$TMP/admin" worktree list | tr '\n' ';')"
kept_all && ok "  … fresh, deep-fresh, anonymous, production-prefix, symlink, plain-file and process-held entries are kept" \
  || fail "sweep removed something it cannot prove: $(ls -a "$TR" | tr '\n' ' ')"
rm -f "$ROOT/.devkit-test-tmp-sweep"   # a clean hourly slot for the rate-limit pair below
tsetup; sweep --prune --keep "$F"; [ ! -e "$TR/hookctx.OLD1" ] && ok "prune (SessionStart) runs the sweep too" || fail "prune did not sweep: $(tail -2 "$TMP/out")"
tsetup; sweep --prune --keep "$F"; [ -d "$TR/hookctx.OLD1" ] && ok "  … at most once an hour (many sessions start: one lsof, not one per session)" || fail "prune swept twice within the hour"
sweep --sweep-tmp; [ ! -e "$TR/hookctx.OLD1" ] && ok "  … while --sweep-tmp always sweeps" || fail "--sweep-tmp was rate-limited"
# A burst of SessionStarts (super-board workers) while lsof is slow: the hour is claimed BEFORE lsof, so one lsof runs.
tsetup; rm -f "$ROOT/.devkit-test-tmp-sweep" "$TMP/lsof.calls"
printf '#!/bin/sh\necho call >> "%s"\nsleep 2\nexec "%s" "$@"\n' "$TMP/lsof.calls" "$TMP/lsof-own" > "$TMP/slowlsof"
chmod +x "$TMP/slowlsof"
for i in 1 2 3; do DEVKIT_LSOF="$TMP/slowlsof" sweep --prune --keep "$F" & done; wait
calls=$(wc -l < "$TMP/lsof.calls" 2>/dev/null | tr -d ' ')
[ "$calls" = 1 ] && [ ! -e "$TR/hookctx.OLD1" ] && ok "  … three concurrent prunes with a slow lsof: one lsof run, one sweep" \
  || fail "concurrent prunes ran lsof ${calls:-0} times (want 1)"
# A stamp that cannot be written (full disk, read-only scratch root) loses the throttle, never the sweep.
if [ "$(id -u)" != 0 ]; then
  tsetup; rm -f "$ROOT/.devkit-test-tmp-sweep"; chmod 500 "$ROOT"
  sweep --prune --keep "$F"; chmod 700 "$ROOT"
  [ ! -e "$TR/hookctx.OLD1" ] && ok "  … a stamp it cannot write still lets the prune sweep" || fail "an unwritable stamp skipped the sweep"
fi
fi
tsetup; DEVKIT_LSOF=/nonexistent/lsof sweep --sweep-tmp; rc=$?
[ "$rc" = 0 ] && [ -d "$TR/hookctx.OLD1" ] && ok "sweep: no lsof answer → nothing removed (cannot tell what is held)" || fail "sweep removed without an lsof answer"
accepted=""
for bad in nan -1 inf; do sweep --sweep-tmp --tmp-ttl-hours "$bad"; [ "$?" = 2 ] || accepted="$accepted $bad"; done
[ -z "$accepted" ] && ok "--tmp-ttl-hours nan / negative / inf is refused (exit 2)" || fail "--tmp-ttl-hours accepted:$accepted"
missing="$(python3 -I - "$DEVKIT_DIR/scripts/governance" "$(git -C "$DEVKIT_DIR" rev-parse --show-toplevel)" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import scratch_cleanup as sc
for p in sc.TEST_TMP_PREFIXES:
    hits = subprocess.run(["git", "-C", sys.argv[2], "grep", "-lF", "--", p], capture_output=True, text=True).stdout.split()
    if not [h for h in hits if not h.endswith(("scratch_cleanup.py", "test_scratch_cleanup.sh")) and "test" in h]:
        print(p)
PY
)"
[ -z "$missing" ] && ok "every TEST_TMP_PREFIXES name is a template some test of this repo uses" || fail "prefixes no test uses: $missing"
# #546 P2 & audit 10-agent: sweep_test_tmp quét /private/tmp, xử lý thư mục con ngay dưới /tmp (macOS symlink /tmp -> private/tmp),
# bắt giữ AF_UNIX socket bind qua đường dẫn /tmp/..., không treo ở .git dạng FIFO, và không ghi/cắt qua symlink ở log_root / stamp.
if command -v lsof >/dev/null 2>&1 || [ -x /usr/sbin/lsof ]; then
  DK_SIM="$TMP/dk_slash_tmp"
  mkdir -p "$DK_SIM/dk-oldsim" "$DK_SIM/dk-freshsim" "$DK_SIM/tmp.keepother" "$DK_SIM/dk-fifogit"
  mkfifo "$DK_SIM/dk-fifogit/.git"
  touch -t 202001010000 "$DK_SIM/dk-oldsim" "$DK_SIM/tmp.keepother" "$DK_SIM/dk-fifogit/.git" "$DK_SIM/dk-fifogit"
  DEVKIT_SCRATCH_ROOT="$TMP/no-sr" DEVKIT_DK_TMP_ROOT="$DK_SIM" python3 -I -c '
import os, subprocess, sys
r = subprocess.run([sys.executable, "-I", sys.argv[1], "--sweep-tmp"], timeout=3, capture_output=True, text=True)
sys.exit(r.returncode)
' "$SC" >/dev/null 2>&1
  [ ! -e "$DK_SIM/dk-oldsim" ] && [ ! -e "$DK_SIM/dk-fifogit" ] && [ -d "$DK_SIM/dk-freshsim" ] && [ -d "$DK_SIM/tmp.keepother" ] \
    && ok "sweep_test_tmp sweeps stale dk-* (including FIFO .git without hanging) while keeping fresh dk-* and non-dk-* entries" \
    || fail "secondary dk-* sweep wrong: old=$([ -e "$DK_SIM/dk-oldsim" ] && echo y || echo n) fifo=$([ -e "$DK_SIM/dk-fifogit" ] && echo y || echo n) fresh=$([ -d "$DK_SIM/dk-freshsim" ] && echo y || echo n) other=$([ -d "$DK_SIM/tmp.keepother" ] && echo y || echo n)"

  SLASH_TMP_BOX="$(mktemp -d /tmp/dk-scbox-XXXXXX)"
  mkdir -p "$SLASH_TMP_BOX/dk-subold" "$TMP/victim_dir"
  echo precious > "$TMP/victim_dir/data.txt"
  ln -s "$TMP/victim_dir/data.txt" "$SLASH_TMP_BOX/.devkit-test-tmp-sweep"
  ln -s "$TMP/victim_dir/data.txt" "$SLASH_TMP_BOX/devkit-scratch-cleanup.log"
  touch -t 202001010000 "$SLASH_TMP_BOX/dk-subold"
  CLAUDE_CONFIG_DIR="$TMP/no-claude-home" DEVKIT_SCRATCH_ROOT="$TMP/no-sr" DEVKIT_CLAUDE_PROJECTS="$PROJ" \
    DEVKIT_TEST_TMP_ROOT="$TMP/no-tr" DEVKIT_DK_TMP_ROOT="$SLASH_TMP_BOX" \
    python3 -I "$SC" --prune --keep "$F" >/dev/null 2>&1
  if [ ! -e "$SLASH_TMP_BOX/dk-subold" ] && [ "$(cat "$TMP/victim_dir/data.txt" 2>/dev/null)" = "precious" ]; then
    ok "sweep_test_tmp cleans scan_root 1-level under /tmp without ENOTDIR and never clobbers symlinks in dk_root"
  else
    fail "1-level /tmp scan_root or symlink protection failed: subold_exists=$([ -e "$SLASH_TMP_BOX/dk-subold" ] && echo y || echo n) victim='$(cat "$TMP/victim_dir/data.txt" 2>/dev/null)'"
  fi
  rm -rf "$SLASH_TMP_BOX"; SLASH_TMP_BOX=""

  # Own scan root under /tmp (a /private/tmp alias, as lsof prints a socket's bind string): never the shared /private/tmp of the host.
  REAL_DK_OLD="$(mktemp -d /tmp/dk-scpar-XXXXXX)"; DK_PAR="$REAL_DK_OLD"
  REAL_DK_OLD="$(mktemp -d "$DK_PAR/dk-sctst-XXXXXX")"
  REAL_DK_SOCK="$(mktemp -d "$DK_PAR/dk-scsock-XXXXXX")"
  python3 -I - "$REAL_DK_SOCK/s.sock" "$TMP/sock.ready" <<'PY' &
import os, socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
open(sys.argv[2], "w").write("1")
time.sleep(30)
PY
  SOCK_PID=$!
  for _ in $(seq 1 50); do [ -f "$TMP/sock.ready" ] && break; python3 -c 'import time; time.sleep(0.05)'; done
  touch -t 202001010000 "$REAL_DK_OLD" "$REAL_DK_SOCK/s.sock" "$REAL_DK_SOCK"
  TMPDIR="$TR" env -u DEVKIT_TEST_TMP_ROOT DEVKIT_DK_TMP_ROOT="$(cd "$DK_PAR" && pwd -P)" DEVKIT_SCRATCH_ROOT="$ROOT" DEVKIT_CLAUDE_PROJECTS="$PROJ" python3 -I "$SC" --sweep-tmp >/dev/null 2>&1
  kill "$SOCK_PID" 2>/dev/null; wait "$SOCK_PID" 2>/dev/null
  if [ ! -e "$REAL_DK_OLD" ] && [ -d "$REAL_DK_SOCK" ]; then
    ok "sweep_test_tmp removes stale /private/tmp/dk-* while keeping /tmp/dk-* held only by an AF_UNIX socket"
  else
    fail "/private/tmp dk-* or AF_UNIX socket check failed: old_exists=$([ -e "$REAL_DK_OLD" ] && echo y || echo n) sock_dir_exists=$([ -d "$REAL_DK_SOCK" ] && echo y || echo n)"
  fi
  rm -rf "$DK_PAR" 2>/dev/null || true; REAL_DK_OLD=""; DK_PAR=""
fi
[ -d "$TR" ] && { chflags -R nouchg "$TR" 2>/dev/null; chmod -R u+rwX "$TR" 2>/dev/null; }

[ "$FAILS" -eq 0 ] && echo "✅ test_scratch_cleanup: all passed" || { echo "❌ test_scratch_cleanup: $FAILS failed"; exit 1; }
