#!/usr/bin/env bash
# Regression test (OfficeReader / GeelyEx2, 2026-10-01): agents created worktrees, finished, and the
# session ended without bringing the work back — trunk silently lacked code and tasks were redone.
# hooks/worktree_merge_gate.sh: a Stop is held while a worktree THIS session is responsible for
# (created after the session started, or named in its transcript as a subagent worktreePath) still
# holds commits or files that are not in the main checkout. Older unreferenced worktrees, worktrees
# another live session holds, and a session that itself runs in a linked worktree are not its business.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate: all passed" || { echo "❌ test_worktree_merge_gate: $FAILS failed"; exit 1; }
