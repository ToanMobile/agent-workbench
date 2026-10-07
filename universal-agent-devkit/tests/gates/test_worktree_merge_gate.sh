#!/usr/bin/env bash
# Regression test (OfficeReader / GeelyEx2, 2026-10-01): agents created worktrees, finished, and the
# session ended without bringing the work back — trunk silently lacked code and tasks were redone.
# hooks/worktree_merge_gate.sh: a Stop is held while a worktree THIS session is responsible for
# (created after the session started, or named in its transcript as a subagent worktreePath) still
# holds commits or files that are not in the main checkout. Older unreferenced worktrees, worktrees
# another live session holds, and a session that itself runs in a linked worktree are not its business.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && echo a > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
# A worktree older than the session, with work nobody brought back: not this session's business.
G "$P" worktree add -q -b old "$TMP/wt-old" && echo o > "$TMP/wt-old/o.txt" && G "$TMP/wt-old" add o.txt && G "$TMP/wt-old" commit -qm old
P3="$TMP/proj3"; mkdir -p "$P3" && G "$P3" init -q -b main . && echo a > "$P3/a.txt" && G "$P3" add a.txt && G "$P3" commit -qm init
G "$P3" worktree add -q -b old3 "$TMP/wt-old3" && echo o > "$TMP/wt-old3/o.txt"    # older than the session, never named: nothing to protect
sleep 1.2
TR="$TMP/tr.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR"
sleep 1.2
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "${3:-$TR}" \
  | CLAUDE_PROJECT_DIR="${2:-$P}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

stop s1; [ $? = 0 ] && ok "a worktree created before the session and never named: not its business" || fail "old worktree blocked: $(cat "$TMP/err")"

G "$P" worktree add -q -b foreign "$TMP/wt-foreign" && echo f > "$TMP/wt-foreign/f.txt"
stop s1; [ $? = 0 ] && ok "a worktree created during the session that the session never touched (user, other agent) is not its business" \
  || fail "someone else's new worktree blocked: $(cat "$TMP/err")"
tooluse() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$1" >> "$TR"; }
printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s  abc [foreign]\\n"}]},"toolUseResult":{"stdout":"git worktree list"}}\n' "$TMP/wt-foreign" >> "$TR"
stop s1; [ $? = 0 ] && ok "  … even when a worktree listing in the transcript shows its path" || fail "listing output made someone else's worktree ours: $(cat "$TMP/err")"
G "$P" worktree add -q -b ne "$TMP/wt-ne" && echo e > "$TMP/wt-ne/e.txt"
tooluse "git worktree add -b feat $TMP/wt-new"
G "$P" worktree add -q -b feat "$TMP/wt-new" && echo n > "$TMP/wt-new/n.txt" && G "$TMP/wt-new" add n.txt && G "$TMP/wt-new" commit -qm new
stop s1; rc=$?
[ "$rc" = 2 ] && grep -q "wt-new" "$TMP/err" && grep -q "git apply --3way" "$TMP/err" && ! grep -q "wt-old" "$TMP/err" \
  && ok "a worktree created this session with a commit not in main holds the Stop, with the bring-back command" \
  || fail "unmerged session worktree passed (rc=$rc): $(cat "$TMP/err")"

echo dirty > "$TMP/wt-new/d.txt"
stop s1; [ $? = 2 ] && grep -q "dirty=1" "$TMP/err" && ok "uncommitted files in a session worktree hold the Stop" || fail "dirty worktree passed"
rm "$TMP/wt-new/d.txt"

grep -q "wt-ne " "$TMP/err" && fail "'wt-ne' matched inside the mention of 'wt-new'" || ok "a path is matched whole ('wt-ne' is not 'wt-new')"
G "$P" merge -q --no-edit feat
stop s1; rc=$?
[ "$rc" = 2 ] && grep -q "wt-new" "$TMP/err" && grep -q "worktree remove" "$TMP/err" \
  && ok "merged but the worktree is still there: the Stop holds until it is removed" || fail "leftover merged worktree passed (rc=$rc): $(cat "$TMP/err")"

TR2="$TMP/tr2.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"next"}}))' > "$TR2"
stop s7 "$P" "$TR2"; [ $? = 2 ] && grep -q "wt-new" "$TMP/err" \
  && ok "a worktree a session was held on is owed: the NEXT session is held on it too" || fail "debt not carried to the next session: $(cat "$TMP/err")"

G "$P" worktree remove "$TMP/wt-new"
stop s7 "$P" "$TR2"; [ $? = 0 ] && ok "  … merged AND removed: the debt is cleared and the Stop passes" || fail "removed worktree still blocks: $(cat "$TMP/err")"

printf '{"type":"user","message":{"content":"<worktree><worktreePath>%s</worktreePath></worktree>"}}\n' "$TMP/wt-old" >> "$TR"
stop s1; [ $? = 2 ] && grep -q "wt-old" "$TMP/err" && ok "an older worktree named as this session's subagent worktreePath holds the Stop" \
  || fail "transcript worktreePath ignored: $(cat "$TMP/err")"

tooluse "cd $P && agent-kit worktree add ../wt-rel fix/rel"
G "$P" worktree add -q -b fix/rel "$TMP/wt-rel" && echo r > "$TMP/wt-rel/r.txt"
python3 -c 'import json,sys
print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"e1","name":"EnterWorktree","input":{}}]}}))
print(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"e1","content":"Created worktree at "+sys.argv[1]+" on branch worktree-rnd"}]}}))' "$P/.claude/worktrees/rnd" >> "$TR"
G "$P" worktree add -q -b worktree-rnd "$P/.claude/worktrees/rnd" && echo q > "$P/.claude/worktrees/rnd/q.txt"
stop s1; [ $? = 2 ] && grep -q "wt-rel" "$TMP/err" && ok "a worktree made with a RELATIVE path (agent-kit worktree add ../x) is this session's" \
  || fail "relative worktree add missed: $(cat "$TMP/err")"
grep -q "worktrees/rnd" "$TMP/err" && ok "an unnamed EnterWorktree is resolved from its own tool result" || fail "unnamed EnterWorktree missed"
printf '{"session_id":"s1","hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$TR" "$TMP/wt-rel" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null 2>"$TMP/err"
grep -q "wt-rel" "$TMP/err" && fail "the worktree the session is working in right now was demanded" || ok "the worktree the session is currently in (cwd) is not demanded yet"
tooluse "git worktree add ../wt-cd"
G "$P" worktree add -q -b cdwt "$TMP/wt-cd" && echo c > "$TMP/wt-cd/c.txt"
printf '{"session_id":"s9","hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$TR" "$TMP/wt-cd" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null 2>&1
stop s10 "$P" "$TR2"; [ $? = 2 ] && grep -q "wt-cd" "$TMP/err" && ok "  … but it is recorded as owed: once the session leaves it, the next Stop is held" \
  || fail "worktree skipped for cwd was lost: $(cat "$TMP/err")"
G "$P" worktree remove --force "$TMP/wt-cd"
G "$P" worktree remove --force "$TMP/wt-rel"; G "$P" worktree remove --force "$P/.claude/worktrees/rnd"

GD="$(git -C "$TMP/wt-old" rev-parse --absolute-git-dir)"
python3 -c 'import json,sys,time,os;json.dump({"session_id":"other","started":time.time(),"heartbeat":time.time(),"pid":int(sys.argv[2])},open(sys.argv[1],"w"))' "$GD/devkit-session.lock" "$$"
stop s1; [ $? = 0 ] && ok "a worktree another live session holds is skipped" || fail "locked worktree blocked: $(cat "$TMP/err")"
rm -f "$GD/devkit-session.lock"

G "$P" worktree add -q -b sub "$TMP/wt-sub" && echo s > "$TMP/wt-sub/s.txt" && G "$TMP/wt-sub" add s.txt && G "$TMP/wt-sub" commit -qm sub
mkdir -p "$TMP/tr/subagents" && printf '{"worktreePath":"%s"}' "$TMP/wt-sub" > "$TMP/tr/subagents/agent-x.meta.json"
stop s1; [ $? = 2 ] && ! grep -q "wt-sub" "$TMP/err" && ok "a subagent still running in its worktree is not pulled in" || fail "running subagent worktree demanded: $(cat "$TMP/err")"
printf '{"type":"user","message":{"content":"<task-notification><status>completed</status><worktree><worktreePath>%s</worktreePath></worktree></task-notification>"}}\n' "$TMP/wt-sub" >> "$TR"
stop s1; [ $? = 2 ] && grep -q "wt-sub" "$TMP/err" && ok "  … once it reports completion, its worktree must be brought back" || fail "finished subagent worktree missed: $(cat "$TMP/err")"

stop s2; stop s2; stop s2; stop s2; rc=$?
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && ok "after 3 holds on the same pending set the Stop passes with a systemMessage" \
  || fail "no cap (rc=$rc out=$(cat "$TMP/out"))"

WORKTREE_MERGE_GATE=0 stop s3; [ $? = 0 ] && ok "WORKTREE_MERGE_GATE=0 turns it off" || fail "escape hatch ignored"
stop s4 "$TMP/wt-old"; [ $? = 0 ] && ok "a session that runs inside a linked worktree is a worker: its leader merges" || fail "worker session blocked"
printf '{"session_id":"s5","hook_event_name":"Stop","transcript_path":"/nope"}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "no transcript: fail-open" || fail "missing transcript blocked"

out="$(printf '{"session_id":"s6","hook_event_name":"SessionStart"}' | SESSION_FETCH=0 STALE_RERUN=0 CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/session_context.sh" 2>/dev/null)"
printf '%s' "$out" | grep -q "wt-old" && printf '%s' "$out" | grep -q "ahead=1" && ! printf '%s' "$out" | grep -q "wt-new" \
  && ok "session start names each worktree whose work is not in trunk, with its counts" \
  || fail "session start listing: $(printf '%s' "$out" | grep -i worktree)"


# ── an internal error while there is something to PROTECT holds the Stop (capped); with nothing to protect it passes ───────────────────────
# The session is the one of $TR (its start is older than the projects below); a worktree is its own when it is created after that start AND named in the transcript.
REALGIT="$(command -v git)"
tooluse2() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$1" >> "$TR"; }
stopk() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$2" "${4:-$TR}" \
  | CLAUDE_PROJECT_DIR="$3" bash "$1/hooks/worktree_merge_gate.sh" >"$TMP/out" 2>"$TMP/err"; }   # stopk <kit dir> <session id> <project> [transcript]
P2="$TMP/proj2"; mkdir -p "$P2" && G "$P2" init -q -b main . && echo a > "$P2/a.txt" && G "$P2" add a.txt && G "$P2" commit -qm init
tooluse2 "git worktree add -b ferr $TMP/wt-err"; G "$P2" worktree add -q -b ferr "$TMP/wt-err" && echo e > "$TMP/wt-err/e.txt"
KITX="$TMP/kitx"; cp -R "$DEVKIT_DIR" "$KITX" 2>/dev/null; cp "$KITX/scripts/git/worktree.py" "$TMP/worktree.py.orig"
# (a variant of the same size rewritten within the same second would be served from the old .pyc by python 3.14: forget the bytecode caches of the kit copy)
nopyc() { find "$KITX" -name __pycache__ -type d -exec rm -r {} + 2>/dev/null; true; }
inject() { nopyc; cp "$TMP/worktree.py.orig" "$KITX/scripts/git/worktree.py"; case "$1" in raise) printf '\ndef inventory(*a, **k):\n    raise RuntimeError("injected inventory failure")\n' >> "$KITX/scripts/git/worktree.py" ;; syntax) printf '\nthis is not python (\n' >> "$KITX/scripts/git/worktree.py" ;; exit1) printf '\ndef inventory(*a, **k):\n    raise SystemExit(1)\n' >> "$KITX/scripts/git/worktree.py" ;; exit2) printf '\ndef inventory(*a, **k):\n    raise SystemExit(2)\n' >> "$KITX/scripts/git/worktree.py" ;; alt) printf '\n_orig_inv = inventory\n_cnt = os.path.join(os.path.dirname(os.path.abspath(__file__)), "alt.cnt")\ndef inventory(*a, **k):\n    n = int(open(_cnt).read()) if os.path.exists(_cnt) else 0\n    open(_cnt, "w").write(str(n + 1))\n    if n %% 2 == 0:\n        raise RuntimeError("flaky")\n    return _orig_inv(*a, **k)\n' >> "$KITX/scripts/git/worktree.py"; rm -f "$KITX/scripts/git/alt.cnt" ;; esac; }

stopk "$DEVKIT_DIR" se1 "$P2"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-err" "$TMP/err" && ok "control: the real kit holds a session worktree with an uncommitted file" || fail "control (rc=$rc): $(cat "$TMP/err")"
inject raise
stopk "$KITX" se2 "$P2"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-err" "$TMP/err" && grep -q "RuntimeError" "$TMP/err" && grep -q "injected inventory failure" "$TMP/err" && grep -q "WORKTREE_MERGE_GATE=0" "$TMP/err" \
  && ok "inventory() raises while a session worktree exists: the Stop is HELD, the message names the exception, the worktree and the way out" \
  || fail "inventory error passed or message wrong (rc=$rc): $(cat "$TMP/err")"
stopk "$KITX" se3 "$P3"; rc=$?
[ "$rc" = 0 ] && ok "inventory() would raise, but there is nothing to protect (no responsible worktree): the Stop passes" || fail "blocked with nothing to protect (rc=$rc): $(cat "$TMP/err")"
for i in 1 2 3; do stopk "$KITX" se4 "$P2"; rc=$?; [ "$rc" = 2 ] || fail "error hold $i of 3 (rc=$rc)"; done
stopk "$KITX" se4 "$P2"; rc=$?
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && grep -q "KHÔNG chạy được" "$TMP/out" && grep -q "wt-err" "$TMP/out" \
  && ok "the cap applies to error holds: 3 holds, then the 4th Stop passes with a systemMessage that says the gate could not run" || fail "error holds not capped (rc=$rc out=$(cat "$TMP/out"))"
inject syntax
stopk "$KITX" se5 "$P2"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-err" "$TMP/err" && grep -q "SyntaxError" "$TMP/err" && ok "worktree.py cannot be imported while a session worktree exists: HELD (it used to pass)" || fail "import failure passed (rc=$rc): $(cat "$TMP/err")"
stopk "$KITX" se6 "$P3"; rc=$?
[ "$rc" = 0 ] && ok "worktree.py cannot be imported but there is nothing to protect: the Stop passes" || fail "import failure blocked with nothing to protect (rc=$rc)"
inject none; cp "$KITX/bin/session_lock.py" "$TMP/session_lock.py.orig"; nopyc; printf '\nraise RuntimeError("injected session_lock failure")\n' >> "$KITX/bin/session_lock.py"
stopk "$KITX" se7 "$P2"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-err" "$TMP/err" && ok "session_lock.py cannot be imported while a session worktree exists: still HELD (the lock of another session just cannot be seen)" || fail "session_lock import failure passed (rc=$rc): $(cat "$TMP/err")"
stopk "$KITX" se8 "$P3"; rc=$?
[ "$rc" = 0 ] && ok "session_lock.py cannot be imported but there is nothing to protect: the Stop passes" || fail "session_lock failure blocked with nothing to protect (rc=$rc)"
nopyc; cp "$TMP/session_lock.py.orig" "$KITX/bin/session_lock.py"

# a responsible worktree whose git dir cannot be determined is held, listed with the reason; one that is not ours is still not our business
P4="$TMP/proj4"; mkdir -p "$P4" && G "$P4" init -q -b main . && echo a > "$P4/a.txt" && G "$P4" add a.txt && G "$P4" commit -qm init
tooluse2 "git worktree add -b fad $TMP/wt-ad"; G "$P4" worktree add -q -b fad "$TMP/wt-ad"
G "$P4" worktree add -q -b fother "$TMP/wt-ad-other"      # created in the session, never named: not ours
mkdir -p "$TMP/shim-ad"; { printf '#!/bin/bash\ncase " $* " in *"/wt-ad "*"--absolute-git-dir"*|*"/wt-ad-other "*"--absolute-git-dir"*) echo "fatal: simulated" >&2; exit 128;; esac\nexec "%s" "$@"\n' "$REALGIT"; } > "$TMP/shim-ad/git"; chmod +x "$TMP/shim-ad/git"
PATH="$TMP/shim-ad:$PATH" stopk "$DEVKIT_DIR" sa1 "$P4"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-ad " "$TMP/err" && grep -q "cannot determine its git dir" "$TMP/err" && ! grep -q "wt-ad-other" "$TMP/err" \
  && ok "a responsible worktree whose git dir cannot be determined is HELD (listed with the reason); one that is not ours is not" \
  || fail "admin-dir failure (rc=$rc): $(cat "$TMP/err")"
for i in 2 3; do PATH="$TMP/shim-ad:$PATH" stopk "$DEVKIT_DIR" sa1 "$P4"; done
PATH="$TMP/shim-ad:$PATH" stopk "$DEVKIT_DIR" sa1 "$P4"; rc=$?
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && ok "  … and that hold is capped too (the 4th Stop passes with a systemMessage)" || fail "admin-dir holds not capped (rc=$rc)"
PATH="$TMP/shim-ad:$PATH" stopk "$DEVKIT_DIR" sa2 "$P3"; [ $? = 0 ] && ok "git dir failures of worktrees that are not ours do not hold anything" || fail "unrelated git dir failure held"


# ── round 2b2 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# the cap bounds ANY mix of causes: an inventory that fails on alternate stops, with a worktree that is merged but still there, ends in a pass
P5="$TMP/proj5"; mkdir -p "$P5" && G "$P5" init -q -b main . && echo a > "$P5/a.txt" && G "$P5" add a.txt && G "$P5" commit -qm init
tooluse2 "git worktree add -b fal $TMP/wt-alt"; G "$P5" worktree add -q -b fal "$TMP/wt-alt"      # no change in it: merged but still there
inject alt; rcs=""
for i in 1 2 3 4 5 6; do stopk "$KITX" sf1 "$P5"; rcs="$rcs $?"; done
[ "$rcs" = " 2 2 2 0 0 0" ] && ok "errors on alternate stops (an error row, then a merged-but-present row): holds 1-3, then every Stop of the session passes" || fail "alternating error/normal never reaches the cap: rcs=$rcs"

# a SystemExit from inventory (die() = exit 2, a git failure = exit 1) is held and capped like any other error
for code in exit2 exit1; do
  inject "$code"; rcs=""
  for i in 1 2 3 4 5; do stopk "$KITX" "sx$code" "$P2"; rcs="$rcs $?"; done
  [ "$rcs" = " 2 2 2 0 0" ] && grep -q "exit($( [ "$code" = exit2 ] && echo 2 || echo 1))" "$TMP/out" \
    && ok "inventory() calls $code: held 3 times, then the Stop passes (and the message says what happened)" \
    || fail "$code: rcs=$rcs out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
done
inject exit2; stopk "$KITX" sxm "$P2"
grep -q "worktree.py called exit(2)" "$TMP/err" && ! grep -q "SystemExit: 2" "$TMP/err" && ok "the reason of a SystemExit reads as what happened, not as SystemExit: 2" || fail "SystemExit reason: $(cat "$TMP/err")"

# the texts: the real cure for a broken git dir, the environment variable that cannot be set for one stop, no `agent-kit worktree status` after the cap
inject raise; stopk "$KITX" sm1 "$P2"
! grep -q "MỘT lần dừng" "$TMP/err" && grep -q "TRƯỚC khi khởi động phiên" "$TMP/err" && ok "the error hold says WORKTREE_MERGE_GATE=0 must be set BEFORE the session starts (not for one stop)" || fail "env var text: $(cat "$TMP/err")"
P6="$TMP/proj6"; mkdir -p "$P6" && G "$P6" init -q -b main . && echo a > "$P6/a.txt" && G "$P6" add a.txt && G "$P6" commit -qm init
tooluse2 "git worktree add -b fbr $TMP/wt-broken"; G "$P6" worktree add -q -b fbr "$TMP/wt-broken"; rm -f "$TMP/wt-broken/.git"
stopk "$DEVKIT_DIR" sb1 "$P6"; rc=$?
[ "$rc" = 2 ] && grep -q "git worktree prune" "$TMP/err" && grep -q "TRƯỚC khi khởi động phiên" "$TMP/err" && ! grep -q "MỘT lần dừng" "$TMP/err" \
  && ok "a worktree with a broken .git pointer: held, and the message names git worktree prune (not a remove that refuses)" || fail "broken pointer text (rc=$rc): $(cat "$TMP/err")"
for i in 2 3; do stopk "$DEVKIT_DIR" sb1 "$P6"; done; stopk "$DEVKIT_DIR" sb1 "$P6"
grep -q "git worktree list" "$TMP/out" && ! grep -q "agent-kit worktree status" "$TMP/out" && ok "the cap message of a gate that could not run advises git worktree list, not agent-kit worktree status" || fail "cap message: $(cat "$TMP/out")"
inject none; cp "$KITX/bin/session_lock.py" "$TMP/session_lock.py.orig2"; nopyc; printf '\nraise RuntimeError("injected session_lock failure")\n' >> "$KITX/bin/session_lock.py"
stopk "$KITX" sl1 "$P2"
grep -q "session_lock" "$TMP/err" && ok "a failing session_lock import is named in the hold text" || fail "session_lock cause not named: $(cat "$TMP/err")"
nopyc; cp "$TMP/session_lock.py.orig2" "$KITX/bin/session_lock.py"

# git worktree list failing must not wipe a debt. A None from git used to become "", paths empty,
# owed filtered to nothing, and save() wrote owed: []. The next Stop then had nothing to hold.
P6="$TMP/proj6"; mkdir -p "$P6" && G "$P6" init -q -b main . && echo a > "$P6/a.txt" && G "$P6" add a.txt && G "$P6" commit -qm init
TR6="$TMP/tr6.jsonl"
python3 - "$TR6" "$TMP/wt-list" <<'PY'
import json, sys
tr, wt = sys.argv[1], sys.argv[2]
open(tr, "w").write(
    json.dumps({"type": "user", "timestamp": "2020-01-01T00:00:00.000Z", "message": {"role": "user", "content": "go"}}) + "\n"
    + json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t", "name": "Bash",
        "input": {"command": "git worktree add -b flist " + wt}}]}}) + "\n")
PY
G "$P6" worktree add -q -b flist "$TMP/wt-list"
WTREAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TMP/wt-list")"
mkdir -p "$P6/.claude/audit-gate"
python3 -c 'import json,sys; json.dump({"owed":[sys.argv[1]],"sessions":{}}, open(sys.argv[2],"w"))' \
  "$WTREAL" "$P6/.claude/audit-gate/worktree_merge_gate.state"
mkdir -p "$TMP/shim-list"
printf '#!/bin/bash\ncase " $* " in *" worktree list "*) echo "fatal: simulated list" >&2; exit 128;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$TMP/shim-list/git"
chmod +x "$TMP/shim-list/git"
PATH="$TMP/shim-list:$PATH" stopk "$DEVKIT_DIR" sl1 "$P6" "$TR6"; rc=$?
owed_after="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1])).get("owed") or []))' "$P6/.claude/audit-gate/worktree_merge_gate.state")"
printf '%s\n' "$owed_after" | grep -q "$WTREAL" && [ "$rc" = 2 ] && grep -q "git worktree list failed" "$TMP/err" \
  && ok "git worktree list failed: the owed worktree is still owed and the Stop is held" \
  || fail "list failure wiped the debt or passed (rc=$rc owed='$owed_after' err=$(cat "$TMP/err"))"
P7="$TMP/proj7"; mkdir -p "$P7" && G "$P7" init -q -b main . && echo a > "$P7/a.txt" && G "$P7" add a.txt && G "$P7" commit -qm init
TR7="$TMP/tr7.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2020-01-01T00:00:00.000Z","message":{"role":"user","content":"look"}}' > "$TR7"
PATH="$TMP/shim-list:$PATH" stopk "$DEVKIT_DIR" sl2 "$P7" "$TR7"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$P7/.claude/audit-gate/worktree_merge_gate.state" ] \
  && ok "git worktree list failed with nothing owed and nothing named: the Stop passes and writes no empty debt" \
  || fail "list failure with nothing to protect (rc=$rc state=$([ -f "$P7/.claude/audit-gate/worktree_merge_gate.state" ] && echo written || echo none))"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate: all passed" || { echo "❌ test_worktree_merge_gate: $FAILS failed"; exit 1; }
