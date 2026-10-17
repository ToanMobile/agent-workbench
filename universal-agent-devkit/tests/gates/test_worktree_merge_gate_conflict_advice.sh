#!/usr/bin/env bash
# Hồi quy (17/10, đo thật): khi tự gộp gặp XUNG ĐỘT, hooks/worktree_merge_gate.sh khuyên `git -C <worktree> add <file>`. Harness của Claude
# chặn `git -C` với đường dẫn tính lúc chạy, nên agent làm đúng lời khuyên thì bị chặn. worktree.py (_conflict, 8c5a407) đã đổi sang
# `cd <wt> && git add <file> && git commit --no-edit` rồi `agent-kit worktree finish <wt>`; câu XUNG ĐỘT của hook phải cùng dạng đó.
#   1 xung đột: Stop bị giữ, câu "XUNG ĐỘT khi tự gộp" của hook có dạng mới với đường dẫn thật của worktree, cả thông báo không còn `git -C`
#   2 làm đúng lời khuyên (cd, add, commit --no-edit) rồi Stop lại: main có bản đã sửa, worktree bị gỡ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # như test_worktree_merge_gate_owner.sh ca 2: chế độ một checkout một phiên
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # đường dẫn thật: đúng chữ hook in ra
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && printf '1\n2\n3\n' > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
G "$P" config user.email t@t; G "$P" config user.name t   # bước 2 chạy lời khuyên nguyên văn, không -c
TR="$TMP/tr.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR"
sleep 1.2
W="$TMP/wt-c"
python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "git worktree add -b fc $W" >> "$TR"
G "$P" worktree add -q -b fc "$W"
printf '1\nW2\n3\n' > "$W/a.txt"; G "$W" commit -qam w2
printf '1\nM2\n3\n' > "$P/a.txt"; G "$P" commit -qam m2
stop() { printf '{"session_id":"c1","hook_event_name":"Stop","transcript_path":"%s"}' "$TR" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

# 1: xung đột
stop; rc=$?
QW="$(python3 -c 'import shlex,sys;print(shlex.quote(sys.argv[1]))' "$W")"
[ "$rc" = 2 ] && grep -q "<<<<<<<" "$W/a.txt" && ok "1: a conflict holds the Stop and stays open in the worktree" || fail "1: (rc=$rc): $(cat "$TMP/err")"
grep "XUNG ĐỘT khi tự gộp" "$TMP/err" | grep -qF "cd $QW && git add <file> && git commit --no-edit" \
  && grep -qF "agent-kit worktree finish $QW" "$TMP/err" \
  && ok "  … the hook's own conflict sentence says cd <wt> && git add <file> && git commit --no-edit, then finish, with the real path" \
  || fail "  … conflict sentence: $(cat "$TMP/err")"
! grep -q "git -C" "$TMP/err" && ok "  … no git -C anywhere in the hold text" || fail "  … git -C still advised: $(grep -n 'git -C' "$TMP/err")"

# 2: làm đúng lời khuyên, rồi Stop lại
printf '1\nW2+M2\n3\n' > "$W/a.txt"
(cd "$W" && git add a.txt && git commit --no-edit -q) || fail "2: the advised commands failed"
stop; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && grep -q "^W2+M2$" "$P/a.txt" \
  && ok "2: following the advice word for word, the next Stop fast-forwards main and removes the worktree" || fail "2: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate_conflict_advice: all passed" || { echo "❌ test_worktree_merge_gate_conflict_advice: $FAILS failed"; exit 1; }
