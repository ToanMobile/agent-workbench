#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 1): worktree_merge_gate.sh ở trunk mode, repo CÓ ma trận gate. Automerge ở Stop không chạy suite:
#   1  worktree của chính phiên, chưa có biên nhận ⇒ không gộp, không suite, Stop bị giữ MỘT lần (lời nêu `agent-kit worktree finish`)
#   2  Stop sau đó cùng HEAD ⇒ không giữ lại
#   3  lời giữa chừng (CHƯA XONG) ⇒ không giữ
#   4  có biên nhận scoped của cây (agent chạy gate trong worktree) ⇒ gộp vào main, không giữ, không suite ở Stop
#   5  worktree của phiên đã hết (adopted), chưa biên nhận ⇒ không giữ phiên này, chỉ ghi chú (vẫn nợ)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null WORKTREE_AUTO_MERGE_WAIT_S=9
unset WORKTREE_TRUNK_MODE WORKTREE_MAX DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_PRIORITY DEVKIT_GATE_CACHE_MAX_S DEVKIT_GATE_EVERY_STOP
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export GATE_COUNT="$TMP/count"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
runs() { [ -f "$GATE_COUNT" ] && wc -l < "$GATE_COUNT" | tr -d ' ' || echo 0; }
repo() {   # repo <name>: main checkout in trunk mode, matrix committed (suite ghi GATE_COUNT)
  local m="$TMP/$1"; mkdir -p "$m/.agents" && G "$m" init -q -b main \
    && printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n.agents/evidence/\n.agents/regression_journal/\n' > "$m/.gitignore" \
    && printf 'echo run >> "$GATE_COUNT"\necho ok\n' > "$m/check.sh" && echo a > "$m/a.sh" \
    && echo '{"profile":"backend"}' > "$m/.agents/active-profile.json" \
    && printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"apps","command":"bash check.sh"}]}]}\n' > "$m/.agents/regression_matrix.active.json" \
    && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode true && G "$m" config user.name t && G "$m" config user.email t@t
}
wtadd() { (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"; }
commit_in() { echo "echo $3" > "$1/.claude/worktrees/$2/$3.sh" && G "$1/.claude/worktrees/$2" add "$3.sh" && G "$1/.claude/worktrees/$2" commit -qm "$3"; }
record() { mkdir -p "$1/.claude/audit-gate/session_worktree" && { printf '%s\n' "$1/.claude/worktrees/$3"; [ -z "${4:-}" ] || printf 'pid %s\n' "$4"; } > "$1/.claude/audit-gate/session_worktree/$2"; }
DEAD=2147483646
transcript() { python3 -c 'import json,sys,time,datetime; f=sys.argv[1]
ts=datetime.datetime.fromtimestamp(time.time()-60, datetime.timezone.utc).isoformat().replace("+00:00","Z")
open(f,"w").write(json.dumps({"type":"user","timestamp":ts,"message":{"role":"user","content":"go"}})+"\n")' "$1"; }
stop() {   # stop <main> <session> <cwd> <transcript> [reply]
  python3 -c 'import json,sys; d={"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}
if sys.argv[4]: d["last_assistant_message"]=sys.argv[4]
print(json.dumps(d))' "$2" "$3" "$4" "${5:-}" | env CLAUDE_PROJECT_DIR="$1" bash "$HOOK" > "$TMP/out" 2> "$TMP/err"
}

repo a; wtadd "$TMP/a" s1 s1; commit_in "$TMP/a" s1 one; record "$TMP/a" s1 s1; transcript "$TMP/t1.jsonl"
M0="$(G "$TMP/a" rev-parse HEAD)"; rm -f "$GATE_COUNT"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl" "CHƯA XONG — còn sửa tiếp"; rc=$?
[ "$rc" = 0 ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$M0" ] && ok "3. lời giữa chừng: không gộp, không giữ" || fail "3. rc=$rc err=$(head -c 300 "$TMP/err")"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 2 ] && grep -q "worktree finish" "$TMP/err" && [ "$(G "$TMP/a" rev-parse HEAD)" = "$M0" ] && [ "$(runs)" = 0 ] \
  && ok "1. worktree phiên chưa biên nhận: không gộp, không suite, giữ một lần nêu worktree finish" || fail "1. rc=$rc runs=$(runs) err=$(head -c 400 "$TMP/err") out=$(head -c 300 "$TMP/out")"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && ok "2. Stop sau, cùng HEAD: không giữ lại" || fail "2. rc=$rc err=$(head -c 300 "$TMP/err")"

( cd "$TMP/a/.claude/worktrees/s1" && python3 "$GATE" --run-tests --scoped --brief ) > "$TMP/gout" 2>&1; g=$?
W="$(G "$TMP/a/.claude/worktrees/s1" rev-parse HEAD)"; n="$(runs)"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$W" ] && [ "$(runs)" = "$n" ] \
  && ok "4. biên nhận scoped: gộp vào main ở Stop, không chạy suite" || fail "4. gate=$g rc=$rc main=$(G "$TMP/a" rev-parse HEAD) want=$W runs=$(runs)/$n out=$(head -c 300 "$TMP/out")"

repo c; wtadd "$TMP/c" s9 s9; commit_in "$TMP/c" s9 nine; record "$TMP/c" s9 s9 "$DEAD"; M2="$(G "$TMP/c" rev-parse HEAD)"; rm -f "$GATE_COUNT"
stop "$TMP/c" s1 "$TMP/c" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ "$(G "$TMP/c" rev-parse HEAD)" = "$M2" ] && [ -d "$TMP/c/.claude/worktrees/s9" ] && grep -q "worktree finish" "$TMP/out" && [ "$(runs)" = 0 ] \
  && ok "5. worktree của phiên đã hết, chưa biên nhận: ghi chú, không giữ phiên này" || fail "5. rc=$rc out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
