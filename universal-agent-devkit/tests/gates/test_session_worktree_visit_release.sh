#!/usr/bin/env bash
# #428 (agent-workbench): phiên eaac452a EnterWorktree vào worktree lane issue-416-build rồi ExitWorktree keep: khoá devkit-kept ở lại
# vì pid phiên còn sống, QA không tạo được worktree cho PR #423. Phiên chỉ ghé vào (EnterWorktree `path`) thì không được để khoá lại.
#   V1 ghé vào worktree có sẵn rồi ExitWorktree keep: khoá devkit-kept của phiên được nhả
#   V2 worktree do chính phiên tạo (EnterWorktree `name`) rồi keep: khoá giữ nguyên
#   V3 khoá của phiên khác không bị đụng khi phiên ghé vào rời đi
#   V4 ghé vào worktree A rồi EnterWorktree sang B: khoá của A được nhả
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; SWPY="$DEVKIT_DIR/hooks/session_worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode true
}
wtadd() { (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"; }
hook() {   # hook <main> <session> <tool> <tool_input json> <tool_response json>
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"tool_name":sys.argv[3],"tool_input":json.loads(sys.argv[4]),"tool_response":json.loads(sys.argv[5])}))' \
    "$2" "$1" "$3" "$4" "$5" | CLAUDE_PROJECT_DIR="$1" python3 -I "$SWPY" record 2> "$TMP/rec.err"
}
visit() { hook "$1" "$3" EnterWorktree "{\"path\":\"$1/.claude/worktrees/$2\"}" "{\"worktreePath\":\"$1/.claude/worktrees/$2\"}"; }
create() { hook "$1" "$3" EnterWorktree "{\"name\":\"$2\"}" "{\"worktreePath\":\"$1/.claude/worktrees/$2\"}"; }
leave() { hook "$1" "$2" ExitWorktree "{\"action\":\"$3\"}" '{}'; }
lock_of() { G "$1" worktree list --porcelain | awk -v p="$1/.claude/worktrees/$2" '$1 == "worktree" { cur = $2 } $1 == "locked" && cur == p { sub(/^locked ?/, ""); print }'; }

repo a; wtadd "$TMP/a" lane s0; visit "$TMP/a" lane s1; leave "$TMP/a" s1 keep
lk="$(lock_of "$TMP/a" lane)"
[ -z "$lk" ] && ok "V1: a session that only visited a worktree leaves no devkit-kept lock on ExitWorktree keep" || fail "V1: still locked '$lk'"

repo b; wtadd "$TMP/b" mine s2; create "$TMP/b" mine s2; leave "$TMP/b" s2 keep
lk="$(lock_of "$TMP/b" mine)"
[ "$lk" = "devkit-kept session=s2 pid=$$" ] && ok "V2: a worktree the session created keeps its devkit-kept lock after keep" || fail "V2: lock='$lk'"

repo c; wtadd "$TMP/c" lane s0; G "$TMP/c" worktree lock --reason "devkit-kept session=other pid=$PPID" "$TMP/c/.claude/worktrees/lane"
visit "$TMP/c" lane s3; leave "$TMP/c" s3 keep
lk="$(lock_of "$TMP/c" lane)"
[ "$lk" = "devkit-kept session=other pid=$PPID" ] && ok "V3: another session's lock is left alone" || fail "V3: lock='$lk'"

repo d; wtadd "$TMP/d" one s0; wtadd "$TMP/d" two s0; visit "$TMP/d" one s4; visit "$TMP/d" two s4
lk="$(lock_of "$TMP/d" one)"
[ -z "$lk" ] && ok "V4: moving on to another worktree releases the lock of the one only visited" || fail "V4: one locked '$lk'"

#   V5 record without a pid (holder_pid None) still reads as a visit; V6 /clear (reown) and a rewrite after a failed lock keep `visit` (#413 x #428)
repo e; wtadd "$TMP/e" lane s0
py() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw; '"$1" "$DEVKIT_DIR/hooks" "${@:2}"; }
py 'sw.write_record(sys.argv[2], "s5", sys.argv[3], pid=None, visit=True); print(sw.raw_visit(sys.argv[2], "s5"))' "$TMP/e" "$TMP/e/.claude/worktrees/lane" | grep -qx True \
  && ok "V5: a visit record with no pid line still reads as a visit" || fail "V5: raw_visit False without a pid"
py 'sw.write_record(sys.argv[2], "old", sys.argv[3], pid=int(sys.argv[4]), visit=True); sw.reown(sys.argv[2], "new", sys.argv[3], lambda s: False); print(sw.raw_visit(sys.argv[2], "new"))' "$TMP/e" "$TMP/e/.claude/worktrees/lane" "$$" \
  | grep -qx True && ok "V6: reown (/clear) carries the visit line to the new session id" || fail "V6: reown dropped visit"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
