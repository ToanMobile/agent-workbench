#!/usr/bin/env bash
# 18/10 (OfficeReader, Neighbours, GeelyEx2): hooks/worktree_merge_gate.sh + scripts/git/worktree.py ở trunk mode.
#   K1  1 worktree của phiên đã chết nằm trên nhánh ĐÃ PUBLISH (có ref remote): automerge không bao giờ gộp được nó, nên phiên ở main không
#         bị giữ Stop 3/3 vì nó (trước đây: "worktree đang ở nhánh … đã PUBLISH … gộp bằng tay")
#       2 worktree của super-board (.claude/worktrees/issue-<N>-build) mà worker đã chết: không phải nợ của phiên khác — không gộp vào main
#         local (board gộp qua PR + merge gate), không giữ Stop
#   K11 3 worktree phiên tự tạo, ExitWorktree keep (PostToolUse ghi khoá `devkit-kept`): Stop vẫn gộp vào main nhưng KHÔNG gỡ khi phiên còn sống
#       4 khoá `devkit-kept` của một pid đã chết: `worktree remove` gỡ được (mở khoá trước)
#   K7  5 `worktree add` không tính worktree của super-board vào WORKTREE_MAX
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null WORKTREE_AUTO_MERGE_WAIT_S=9
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; SWPY="$DEVKIT_DIR/hooks/session_worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {   # repo <name>: main checkout ở trunk mode
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode true \
    && G "$m" config user.name t && G "$m" config user.email t@t
}
wtadd() {   # wtadd <main> <name> <session> [branch]: worktree dựng như hook WorktreeCreate
  (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" ${4:+"$4"} --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"
}
commit_in() { echo "$3" > "$1/.claude/worktrees/$2/$3.txt" && G "$1/.claude/worktrees/$2" add "$3.txt" && G "$1/.claude/worktrees/$2" commit -qm "$3"; }
record() {   # record <main> <session> <worktree name> [pid]
  mkdir -p "$1/.claude/audit-gate/session_worktree" && { printf '%s\n' "$1/.claude/worktrees/$3"; [ -z "${4:-}" ] || printf 'pid %s\n' "$4"; } > "$1/.claude/audit-gate/session_worktree/$2"
}
DEAD=2147483646
transcript() {   # transcript <file> [đường dẫn một lệnh 'worktree add' đã nêu]
  python3 -c 'import json,sys,time,datetime; f,p=sys.argv[1],sys.argv[2]
ts=datetime.datetime.fromtimestamp(time.time()-60, datetime.timezone.utc).isoformat().replace("+00:00","Z")
with open(f,"w") as o:
    o.write(json.dumps({"type":"user","timestamp":ts,"message":{"role":"user","content":"go"}})+"\n")
    if p: o.write(json.dumps({"type":"assistant","timestamp":ts,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"agent-kit worktree add "+p}}]}})+"\n")' "$1" "${2:-}"
}
stop() {   # stop <main> <session> <cwd> <transcript> [env...]
  local m="$1" s="$2" c="$3" t="$4"; shift 4
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$s" "$c" "$t" \
    | env CLAUDE_PROJECT_DIR="$m" "$@" bash "$HOOK" > "$TMP/out" 2> "$TMP/err"
}
transcript "$TMP/t1.jsonl"

# 1 K1: worktree của phiên đã chết, nhánh đã publish: không giữ Stop, không đụng
repo a; wtadd "$TMP/a" pub s9 feat-x; commit_in "$TMP/a" pub nine; record "$TMP/a" s9 pub "$DEAD"
G "$TMP/a" update-ref refs/remotes/origin/feat-x "$(G "$TMP/a" rev-parse feat-x)"
for i in 1 2; do stop "$TMP/a" s1 "$TMP/a" "$TMP/t1.jsonl"; rc=$?; [ "$rc" = 0 ] || break; done
[ "$rc" = 0 ] && ! grep -q "PUBLISH" "$TMP/err" && [ -d "$TMP/a/.claude/worktrees/pub" ] && [ ! -f "$TMP/a/nine.txt" ] \
  && ok "K1: dead session's worktree on a published branch: Stop not held (twice), worktree untouched" \
  || fail "K1 published (rc $rc): err=$(head -c 400 "$TMP/err")"

# 1b OCR 18/10: cùng worktree đó có thêm commit CHƯA push: vẫn không giữ Stop, nhưng phải được nói ra (không bỏ im lặng)
commit_in "$TMP/a" pub ninebis
stop "$TMP/a" s1 "$TMP/a" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && grep -q "chưa push" "$TMP/out" && grep -qF "$TMP/a/.claude/worktrees/pub" "$TMP/out" \
  && ok "  … with a commit not pushed: still not held, but a note names it" || fail "unpushed published worktree dropped silently (rc $rc): out=$(head -c 300 "$TMP/out")"

# 2 K1: worktree super-board issue-73-build trên nhánh issue-73-<slug> chưa publish (worker đã chết): không gộp vào main local, không giữ Stop
repo b; wtadd "$TMP/b" issue-73-build s8 issue-73-drive-filter; commit_in "$TMP/b" issue-73-build board; record "$TMP/b" s8 issue-73-build "$DEAD"
stop "$TMP/b" s1 "$TMP/b" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/b/board.txt" ] && [ -d "$TMP/b/.claude/worktrees/issue-73-build" ] \
  && ok "K1: super-board worktree (named branch) of a dead worker: not merged into local main, not removed, Stop not held" \
  || fail "K1 board (rc $rc, merged: $( [ -f "$TMP/b/board.txt" ] && echo yes || echo no)): err=$(head -c 400 "$TMP/err")"
# 2b đối chứng (review 18/10): một phiên tự EnterWorktree(name="issue-42") — detached, không nhánh — rồi chết: vẫn là nợ, được gộp vào main
wtadd "$TMP/b" issue-42 s6; commit_in "$TMP/b" issue-42 fortytwo; record "$TMP/b" s6 issue-42 "$DEAD"
stop "$TMP/b" s1 "$TMP/b" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/b/fortytwo.txt" ] && ok "  … a detached session worktree merely NAMED issue-42 (dead owner): still adopted and merged" \
  || fail "detached issue-42 skipped as a board worktree (rc $rc, merged: $( [ -f "$TMP/b/fortytwo.txt" ] && echo yes || echo no)): $(head -c 300 "$TMP/err")"

# 3 K11: phiên s1 tự tạo worktree, commit, ExitWorktree keep -> Stop gộp nhưng giữ worktree
repo c; wtadd "$TMP/c" kept s1; commit_in "$TMP/c" kept three; record "$TMP/c" s1 kept $$
transcript "$TMP/t3.jsonl" "$TMP/c/.claude/worktrees/kept"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":"s1","cwd":sys.argv[1],"tool_name":"ExitWorktree","tool_input":{"action":"keep"},"tool_response":{}}))' \
  "$TMP/c" > "$TMP/p3.json"
CLAUDE_PROJECT_DIR="$TMP/c" python3 -I "$SWPY" record < "$TMP/p3.json" 2> "$TMP/rec.err"   # cha của python là chính shell này: pid còn sống
G "$TMP/c" worktree list --porcelain | grep -q "^locked devkit-kept session=s1 pid=$$" || fail "K11 setup: no devkit-kept lock: $(cat "$TMP/rec.err") $(G "$TMP/c" worktree list --porcelain | tr '\n' ' ')"
stop "$TMP/c" s1 "$TMP/c" "$TMP/t3.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/c/three.txt" ] && [ -d "$TMP/c/.claude/worktrees/kept" ] \
  && ok "K11: ExitWorktree keep: Stop merges into main and keeps the worktree while its session lives" \
  || fail "K11 kept (rc $rc, merged: $( [ -f "$TMP/c/three.txt" ] && echo yes || echo no), dir: $( [ -d "$TMP/c/.claude/worktrees/kept" ] && echo kept || echo removed)): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"
# #406 N3: khoá giờ còn do EnterWorktree / SessionStart đặt — câu báo nói lý do thật (phiên còn sống đang dùng), không "ExitWorktree keep"
grep -q "phiên còn sống đang dùng nó" "$TMP/out" && ! grep -q "ExitWorktree keep" "$TMP/out" \
  && ok "  … the Stop note says a live session is using the worktree (not 'ExitWorktree keep')" || fail "K11 note: out=$(head -c 400 "$TMP/out")"

# 4 K11: khoá devkit-kept của pid đã chết: worktree remove mở khoá rồi gỡ (công việc đã ở main)
G "$TMP/c" worktree unlock "$TMP/c/.claude/worktrees/kept" 2>/dev/null
G "$TMP/c" worktree lock --reason "devkit-kept session=s1 pid=$DEAD" "$TMP/c/.claude/worktrees/kept"
(cd "$TMP/c" && python3 -I "$WTPY" remove "$TMP/c/.claude/worktrees/kept" > "$TMP/out" 2> "$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/c/.claude/worktrees/kept" ] && ok "K11: a devkit-kept lock of a dead pid: worktree remove unlocks and removes it" \
  || fail "K11 dead lock (rc $rc): err=$(head -c 300 "$TMP/err")"

# 4b K11: keep KHÔNG ghi được (worktree đã bị người khác khoá): cảnh báo phải tới model (additionalContext trên stdout), không chỉ stderr
repo e; wtadd "$TMP/e" kx s1; record "$TMP/e" s1 kx $$
G "$TMP/e" worktree lock --reason "someone else" "$TMP/e/.claude/worktrees/kx"
sed 's#"cwd": *"[^"]*"#"cwd": "'"$TMP/e"'"#' "$TMP/p3.json" > "$TMP/p4.json"
CLAUDE_PROJECT_DIR="$TMP/e" python3 -I "$SWPY" record < "$TMP/p4.json" > "$TMP/rec.out" 2> "$TMP/rec.err"
grep -q '"additionalContext"' "$TMP/rec.out" && grep -q "KEEP NOT RECORDED" "$TMP/rec.out" \
  && ok "K11: a keep that cannot be recorded is told to the model (additionalContext on stdout)" || fail "keep failure silent: out=$(cat "$TMP/rec.out") err=$(cat "$TMP/rec.err")"

# 5 K7: worktree của super-board không chiếm chỗ WORKTREE_MAX
repo d; G "$TMP/d" worktree add -q -b issue-40-fix "$TMP/d/.claude/worktrees/issue-40-qa"   # như super-board dựng: git worktree add -b
(cd "$TMP/d" && WORKTREE_MAX=1 python3 -I "$WTPY" add "$TMP/d-extra" --no-init > "$TMP/out" 2> "$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/d-extra" ] && ok "K7: a super-board worktree takes no WORKTREE_MAX slot" || fail "K7 (rc $rc): err=$(head -c 300 "$TMP/err")"
(cd "$TMP/d" && WORKTREE_MAX=1 python3 -I "$WTPY" add "$TMP/d-extra2" --no-init > "$TMP/out" 2> "$TMP/err"); rc=$?
[ "$rc" = 4 ] && ok "  … but an ordinary worktree still does (the 2nd add at WORKTREE_MAX=1 is refused, rc 4)" || fail "K7 cap gone (rc $rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_board_kept: PASS"; exit 0; } || { echo "test_worktree_merge_gate_board_kept: FAIL ($FAILS)"; exit 1; }
