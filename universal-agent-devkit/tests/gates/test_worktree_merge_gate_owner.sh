#!/usr/bin/env bash
# Regression (OfficeReader 2026-10-08; user: "it creates a worktree and leaves it there", "is there an automatic merge yet? I sit here
# making you run it 20 times", "just merge, and if there is a conflict fix it, safely"). hooks/worktree_merge_gate.sh only HELD the Stop and
# listed commands; four sessions were held three times each over a worktree that belonged to a session still working in it, then the
# cap let them go and the worktree stayed. Now the hook MERGES by itself and holds only for what cannot finish:
#   1. a worktree the session made (not one `worktree add` made, with a commit main lacks) is merged by the Stop itself: the Stop
#      passes, main has the work, the worktree is gone, the systemMessage says so
#   2. a CONFLICT is left open in the worktree and holds the Stop (it says how to resolve it, safely, there); once resolved and staged the
#      next Stop concludes the merge, fast-forwards main and removes the worktree by itself
#   3. the conflict is the OWNER's: a bystander session is not held while the owner is alive and working; once the owner ended, the
#      next session adopts the debt
#   4. main held by another live session: nothing is written to it, the worktree is held with the reason
#   5. WORKTREE_AUTO_MERGE=0 restores the old hold, with ONE command per worktree (real path) instead of three steps
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; LOCKPY="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && printf '1\n2\n3\n4\n5\n' > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
TRA="$TMP/tra.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TRA"
sleep 1.2
mention() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "git worktree add -b $1 $2" >> "$TRA"; }
mk_tr() { python3 -c 'import json,datetime,sys;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"next"}}))' > "$1"; }
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
live() { python3 -I "$LOCKPY" --register --session "$1" --pid "$$" "$P"; }       # a registered session whose process ($$) is alive
gone() { python3 -I "$LOCKPY" --unregister --session "$1" "$P"; }
state_owner() { python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("owners") or {}).get(sys.argv[2],""))' "$P/.claude/audit-gate/worktree_merge_gate.state" "$(cd "$1" && pwd -P)"; }

# 1: made by plain `git worktree add` (no devkit state), one commit main lacks -> merged by the Stop itself
mention feat1 "$TMP/wt-feat1"; G "$P" worktree add -q -b feat1 "$TMP/wt-feat1" && echo n > "$TMP/wt-feat1/n.txt" && G "$TMP/wt-feat1" add n.txt && G "$TMP/wt-feat1" commit -qm feat1
live A
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/wt-feat1" ] && [ -f "$P/n.txt" ] && ok "1: the Stop merges the worktree by itself: it passes, main has the work, the worktree is gone" || fail "1: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"
grep -q "đã tự gộp" "$TMP/out" && ok "  … and the systemMessage says what was merged" || fail "  … no systemMessage: $(cat "$TMP/out")"
[ -z "$(G "$P" status --porcelain --untracked-files=no)" ] && ok "  … main's tree is clean (fast-forward only)" || fail "  … main is dirty: $(G "$P" status --short)"

# 2 + 3: a conflicting worktree
sleep 1.2
mention feat2 "$TMP/wt-feat2"; G "$P" worktree add -q -b feat2 "$TMP/wt-feat2"
printf '1\n2\nE3\n4\n5\n' > "$TMP/wt-feat2/a.txt"; G "$TMP/wt-feat2" commit -qam "e3"
printf '1\n2\nM3\n4\n5\n' > "$P/a.txt"; G "$P" commit -qam "m3"; HEADC="$(G "$P" rev-parse HEAD)"
stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-feat2" "$TMP/err" && grep -q "XUNG ĐỘT" "$TMP/err" && ok "2: a conflict holds the Stop and says how to resolve it in the worktree" || fail "2: conflict (rc=$rc): $(cat "$TMP/err")"
[ "$(G "$P" rev-parse HEAD)" = "$HEADC" ] && grep -q "^M3$" "$P/a.txt" && ! grep -q "<<<<" "$P/a.txt" && ok "  … main was not touched" || fail "  … main changed during the conflict"
grep -q "<<<<<<<" "$TMP/wt-feat2/a.txt" && ok "  … the conflict is open in the worktree" || fail "  … no markers in the worktree"
[ "$(state_owner "$TMP/wt-feat2")" = "A" ] && ok "  … the state records A as the owner" || fail "  … owner not recorded: '$(state_owner "$TMP/wt-feat2")'"

TRB="$TMP/trb.jsonl"; mk_tr "$TRB"; live B
stop B "$TRB"; rc=$?
[ "$rc" = 0 ] && ok "3: bystander B is NOT held while the owner A is alive" || fail "3: bystander held (rc=$rc): $(cat "$TMP/err")"
stop A "$TRA"; rc=$?; [ "$rc" = 2 ] && ok "  … the owner A is still held" || fail "  … owner A passed (rc=$rc)"
gone A
stop B "$TRB"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-feat2" "$TMP/err" && [ "$(state_owner "$TMP/wt-feat2")" = "B" ] && ok "  … A has ended: the debt falls to B, who adopts it" || fail "  … debt lost or not adopted (rc=$rc owner='$(state_owner "$TMP/wt-feat2")'): $(cat "$TMP/err")"
printf '1\n2\nE3+M3\n4\n5\n' > "$TMP/wt-feat2/a.txt"; G "$TMP/wt-feat2" add a.txt      # B resolves it in the worktree and stops
stop B "$TRB"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/wt-feat2" ] && grep -q "^E3+M3$" "$P/a.txt" && [ -z "$(G "$P" status --porcelain --untracked-files=no)" ] \
  && ok "2: once resolved and staged, the next Stop concludes the merge, fast-forwards main and removes the worktree by itself" || fail "2: after resolving (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

# 4: main is held by another LIVE session: nothing is written to it
sleep 1.2
mention feat3 "$TMP/wt-feat3"; G "$P" worktree add -q -b feat3 "$TMP/wt-feat3" && echo three > "$TMP/wt-feat3/t.txt" && G "$TMP/wt-feat3" add t.txt && G "$TMP/wt-feat3" commit -qm feat3
HEAD4="$(G "$P" rev-parse HEAD)"
python3 -c 'import json,sys,time;json.dump({"session_id":"holder","started":time.time(),"heartbeat":time.time(),"pid":int(sys.argv[2]),"cwd":sys.argv[3]},open(sys.argv[1],"w"))' "$(G "$P" rev-parse --absolute-git-dir)/devkit-session.lock" "$$" "$P"
stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && [ -d "$TMP/wt-feat3" ] && [ "$(G "$P" rev-parse HEAD)" = "$HEAD4" ] && grep -q "phiên khác giữ" "$TMP/err" && ok "4: main held by another live session: nothing merged, the hold names the reason" || fail "4: (rc=$rc): $(cat "$TMP/err")"
rm -f "$(G "$P" rev-parse --absolute-git-dir)/devkit-session.lock"

# 5: switched off: the old hold, with one command and the real path
WORKTREE_AUTO_MERGE=0 stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && [ -d "$TMP/wt-feat3" ] && grep -q "agent-kit worktree finish '*$(cd "$TMP/wt-feat3" && pwd -P)" "$TMP/err" && ok "5: WORKTREE_AUTO_MERGE=0 holds again, with ONE command and the real path" || fail "5: (rc=$rc): $(cat "$TMP/err")"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/wt-feat3" ] && [ -f "$P/t.txt" ] && ok "  … and switched back on, the same Stop merges it" || fail "  … auto-merge after re-enable (rc=$rc): $(cat "$TMP/err")"

# 6: the owner is working INSIDE its worktree (EnterWorktree): not held there and not merged under its feet, but it IS the owner: a
# bystander must neither hold nor merge a worktree its owner is working in
sleep 1.2
mention feat4 "$TMP/wt-feat4"; G "$P" worktree add -q -b feat4 "$TMP/wt-feat4" && echo four > "$TMP/wt-feat4/f4.txt" && G "$TMP/wt-feat4" add f4.txt && G "$TMP/wt-feat4" commit -qm feat4
live A
printf '{"session_id":"A","hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$TRA" "$TMP/wt-feat4" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/wt-feat4" ] && ok "6: the owner is inside its worktree: the Stop passes and nothing is merged under its feet" || fail "6: (rc=$rc): $(cat "$TMP/err")"
[ "$(state_owner "$TMP/wt-feat4")" = "A" ] && ok "  … yet A is recorded as its owner" || fail "  … owner not recorded: '$(state_owner "$TMP/wt-feat4")'"
stop B "$TRB"; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/wt-feat4" ] && [ ! -f "$P/f4.txt" ] && ok "  … and bystander B neither holds nor merges a worktree its owner is working in" || fail "  … B touched A's worktree (rc=$rc): $(cat "$TMP/err")"

# 7: the merge takes longer than the hook may wait (a slow pre-commit in the worktree): the Stop passes at once, the merge goes on in the
# background and the worktree stays OWED, so a conflict it ends in is still found by the next Stop
sleep 1.2
mention feat5 "$TMP/wt-feat5"; G "$P" worktree add -q -b feat5 "$TMP/wt-feat5" && echo five > "$TMP/wt-feat5/f5.txt"      # uncommitted: the commit in the worktree runs the pre-commit hook
mkdir -p "$P/.git/hooks" && printf '#!/bin/sh\nsleep 3\nexit 0\n' > "$P/.git/hooks/pre-commit" && chmod +x "$P/.git/hooks/pre-commit"
T0=$(python3 -c 'import time;print(time.time())')
WORKTREE_AUTO_MERGE_WAIT_S=1 stop A "$TRA"; rc=$?
T1=$(python3 -c 'import time;print(time.time())')
[ "$rc" = 0 ] && [ -d "$TMP/wt-feat5" ] && grep -q "đang tự gộp ở nền" "$TMP/out" && ok "7: a merge slower than the wait budget: the Stop passes and says it goes on in the background" || fail "7: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"
python3 -c 'import sys;sys.exit(0 if float(sys.argv[2])-float(sys.argv[1]) < 6 else 1)' "$T0" "$T1" && ok "  … and it did not wait for the slow hook" || fail "  … the Stop waited for the slow merge"
python3 -c 'import json,sys;sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("owed",[]) else 1)' "$P/.claude/audit-gate/worktree_merge_gate.state" "$(cd "$TMP/wt-feat5" && pwd -P)" \
  && ok "  … the worktree is still OWED (a conflict it ends in is found by the next Stop)" || fail "  … the running worktree was dropped from the debt: $(cat "$P/.claude/audit-gate/worktree_merge_gate.state")"
WORKTREE_AUTO_MERGE_WAIT_S=1 stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "  … a second Stop while it runs passes (not a hold, not counted)" || fail "  … second Stop held (rc=$rc): $(cat "$TMP/err")"
for i in $(seq 1 30); do [ -d "$TMP/wt-feat5" ] || break; sleep 1; done
[ ! -d "$TMP/wt-feat5" ] && [ -f "$P/f5.txt" ] && ok "  … the background merge finished by itself: main has the work, the worktree is gone" || fail "  … background merge did not finish"
rm -f "$P/.git/hooks/pre-commit"

# 8: a wait budget larger than the hook's own alarm must not make the alarm pass the Stop in silence: the hook answers before it fires
sleep 1.2
mention feat6 "$TMP/wt-feat6"; G "$P" worktree add -q -b feat6 "$TMP/wt-feat6" && echo six > "$TMP/wt-feat6/f6.txt"
printf '#!/bin/sh\nsleep 20\nexit 0\n' > "$P/.git/hooks/pre-commit" && chmod +x "$P/.git/hooks/pre-commit"
T0=$(python3 -c 'import time;print(time.time())')
WORKTREE_AUTO_MERGE_WAIT_S=100 stop A "$TRA"; rc=$?
T1=$(python3 -c 'import time;print(time.time())')
python3 -c 'import sys;sys.exit(0 if float(sys.argv[2])-float(sys.argv[1]) < 13 else 1)' "$T0" "$T1" && grep -q "đang tự gộp ở nền" "$TMP/out" \
  && ok "8: a 100 s wait budget is cut to the hook's alarm: the Stop answers (with the background note) before the alarm would pass it silently" || fail "8: waited or lost the note (rc=$rc): $(cat "$TMP/out") $(cat "$TMP/err")"
for i in $(seq 1 40); do [ -d "$TMP/wt-feat6" ] || break; sleep 1; done
rm -f "$P/.git/hooks/pre-commit"

# 9: a <worktreePath> that appears only in TOOL OUTPUT (the agent read it somewhere) is not a worktree the session made: never merged
sleep 1.2
G "$P" worktree add -q -b feat7 "$TMP/wt-feat7" && echo seven > "$TMP/wt-feat7/f7.txt" && G "$TMP/wt-feat7" add f7.txt && G "$TMP/wt-feat7" commit -qm feat7
python3 -c 'import json,sys;print(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"<worktree><worktreePath>"+sys.argv[1]+"</worktreePath></worktree>"}]}}))' "$TMP/wt-feat7" >> "$TRA"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/wt-feat7" ] && [ ! -f "$P/f7.txt" ] && ok "9: a worktreePath seen only in tool output is not this session's: not merged, not removed" || fail "9: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "worktree merge gate owner + automerge: all checks passed" || { echo "worktree merge gate owner + automerge: $FAILS FAILED"; exit 1; }
