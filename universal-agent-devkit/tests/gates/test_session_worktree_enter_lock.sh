#!/usr/bin/env bash
# 25/10 (agent-workbench): cleanup-wt (hook --post-merge của merge gate, --auto ở SessionStart) gỡ worktree dropped-card-sweep lúc 12:35
# vì "merged: ancestor of main" trong khi phiên vẫn ở trong đó và gate --full đang chạy: gate mất thư mục, phiên mất cwd. cleanup-wt
# (mọi bản đã cài ở mọi repo) chỉ chừa worktree bị `git worktree lock`. K11 chỉ khoá khi ExitWorktree keep, và còn MỞ khoá khi phiên vào
# lại — đúng lúc phiên đang làm việc trong đó thì không có khoá nào.
#   E1 trunk mode: PostToolUse EnterWorktree khoá worktree `devkit-kept session=<sid> pid=<tiến trình phiên>`
#   E2 công cụ ngoài (git worktree remove không --force, như cleanup-wt chừa worktree khoá) không gỡ được nó
#   E3 `worktree remove` của kit do chính phiên gọi (đường WorktreeRemove của ExitWorktree remove) vẫn gỡ được: mở khoá của chính nó
#   E4 trunk mode tắt: EnterWorktree không khoá (harness tự `git worktree remove`, khoá sẽ chặn ExitWorktree remove) — như cũ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; SWPY="$DEVKIT_DIR/hooks/session_worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {   # repo <name> <true|false>: main checkout, trunk mode bật/tắt
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode "$2" \
    && G "$m" config user.name t && G "$m" config user.email t@t
}
wtadd() {   # wtadd <main> <name> <session>: worktree dựng như hook WorktreeCreate
  (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"
}
enter() {   # enter <main> <name> <session>: PostToolUse EnterWorktree (cha của python là shell này: pid phiên còn sống = $$)
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"tool_name":"EnterWorktree","tool_input":{"name":sys.argv[3]},"tool_response":{"worktreePath":sys.argv[2]+"/.claude/worktrees/"+sys.argv[3]}}))' \
    "$3" "$1" "$2" | CLAUDE_PROJECT_DIR="$1" python3 -I "$SWPY" record 2> "$TMP/rec.err"
}
lock_of() { G "$1" worktree list --porcelain | awk -v p="$1/.claude/worktrees/$2" '$1 == "worktree" { cur = $2 } $1 == "locked" && cur == p { sub(/^locked ?/, ""); print }'; }

# E1 + E2 + E3: trunk mode
repo a true; wtadd "$TMP/a" live s1; enter "$TMP/a" live s1
lk="$(lock_of "$TMP/a" live)"
[ "$lk" = "devkit-kept session=s1 pid=$$" ] && ok "E1: EnterWorktree (trunk mode) locks the session's worktree devkit-kept with its pid" \
  || fail "E1: lock='$lk' err=$(head -c 300 "$TMP/rec.err")"
G "$TMP/a" worktree remove "$TMP/a/.claude/worktrees/live" >/dev/null 2>&1
[ -d "$TMP/a/.claude/worktrees/live" ] && ok "E2: an outside tool (git worktree remove, no --force) cannot remove it while the session lives" \
  || fail "E2: the live session's worktree was removed by a plain git worktree remove"
(cd "$TMP/a" && python3 -I "$WTPY" remove "$TMP/a/.claude/worktrees/live" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/a/.claude/worktrees/live" ] && ok "E3: the session's own kit 'worktree remove' (ExitWorktree remove path) still removes it" \
  || fail "E3 (rc $rc): $(head -c 300 "$TMP/rm.out")"

# E4: trunk mode tắt: không khoá
repo b false; wtadd "$TMP/b" plain s2; enter "$TMP/b" plain s2
lk="$(lock_of "$TMP/b" plain)"
[ -z "$lk" ] && ok "E4: trunk mode off: EnterWorktree does not lock (harness git worktree remove keeps working)" || fail "E4: locked '$lk'"

# E5 (review 25/10): ExitWorktree remove mà WorktreeRemove từ chối (worktree còn commit chưa vào main): khoá của phiên phải được mở,
#    nếu không Stop thấy "kept by a live session", bỏ khỏi nợ, và worktree mồ côi
exitwt() {   # exitwt <main> <session> <action>
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"tool_name":"ExitWorktree","tool_input":{"action":sys.argv[3]},"tool_response":{}}))' \
    "$2" "$1" "$3" | CLAUDE_PROJECT_DIR="$1" python3 -I "$SWPY" record 2> "$TMP/rec.err"
}
repo c true; wtadd "$TMP/c" unmerged s5; enter "$TMP/c" unmerged s5
echo x > "$TMP/c/.claude/worktrees/unmerged/x.txt" && G "$TMP/c/.claude/worktrees/unmerged" add x.txt && G "$TMP/c/.claude/worktrees/unmerged" commit -qm x
[ -n "$(lock_of "$TMP/c" unmerged)" ] || fail "E5 setup: not locked after enter"
exitwt "$TMP/c" s5 remove
lk="$(lock_of "$TMP/c" unmerged)"
[ -z "$lk" ] && ok "E5: ExitWorktree remove (removal refused, work not in main): the session's lock is released for the Stop to adopt" \
  || fail "E5: still locked '$lk' after ExitWorktree remove"
# E5b: /clear đổi sid nhưng cùng tiến trình: khoá mang sid cũ, pid hiện tại — vẫn là của phiên này, ExitWorktree remove mở được
repo d true; wtadd "$TMP/d" cleared s6; enter "$TMP/d" cleared s6
mkdir -p "$TMP/d/.claude/audit-gate/session_worktree" && printf '%s\npid %s\n' "$TMP/d/.claude/worktrees/cleared" $$ > "$TMP/d/.claude/audit-gate/session_worktree/s7"
exitwt "$TMP/d" s7 remove
lk="$(lock_of "$TMP/d" cleared)"
[ -z "$lk" ] && ok "E5b: after /clear (new sid, same process) ExitWorktree remove still releases the old-sid lock by its pid" \
  || fail "E5b: still locked '$lk'"

# E6 (review 25/10): phiên KHỞI ĐỘNG sẵn trong worktree (Desktop worktree session, claude --worktree): không có EnterWorktree,
#    SessionStart phải khoá. E7: trunk mode tắt thì không.
start_in() {   # start_in <main> <name> <session>
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"SessionStart","cwd":sys.argv[2],"source":"startup"}))' \
    "$3" "$1/.claude/worktrees/$2" | CLAUDE_PROJECT_DIR="$1/.claude/worktrees/$2" DEVKIT_SCRATCH_CLEANUP=0 python3 -I "$DEVKIT_DIR/bin/session_lock.py" > /dev/null 2> "$TMP/start.err"
}
repo e true; wtadd "$TMP/e" started s8; start_in "$TMP/e" started s8
lk="$(lock_of "$TMP/e" started)"
[ "$lk" = "devkit-kept session=s8 pid=$$" ] && ok "E6: a session that STARTS in a worktree (trunk mode) gets it locked at SessionStart" \
  || fail "E6: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
repo f false; wtadd "$TMP/f" started s9; start_in "$TMP/f" started s9
lk="$(lock_of "$TMP/f" started)"
[ -z "$lk" ] && ok "E7: trunk mode off: SessionStart does not lock" || fail "E7: locked '$lk'"
# E8: worktree lane của super-board: runner gỡ nó bằng `git worktree remove` thô — khoá của worker đã chết sẽ chặn, nên không khoá
wtadd "$TMP/e" issue-12-build s10; start_in "$TMP/e" issue-12-build s10
lk="$(lock_of "$TMP/e" issue-12-build)"
[ -z "$lk" ] && ok "E8: a super-board lane worktree (issue-12-build) is not locked at SessionStart (the board removes it itself)" \
  || fail "E8: board lane worktree locked '$lk'"

echo
[ "$FAILS" = 0 ] && { echo "test_session_worktree_enter_lock: PASS"; exit 0; }
echo "test_session_worktree_enter_lock: $FAILS FAIL"; exit 1
