#!/usr/bin/env bash
# #1232: --sweep của .claude/bin/super-board-post-merge-clean.sh không dọn worktree của thẻ CLOSED không có PR MERGED riêng (PR gom vào
# PR khác, đóng tay): "kept card N: no merged PR of it into main", và file kit tự sinh (.claude/settings.json, .claude/agents/) không nằm
# trong DROP_RE nên giữ worktree mãi. Offline: gh giả, kit thật. CLEAN=<file> chạy bản cũ để thấy ĐỎ.
#   A thẻ CLOSED, không PR merged, không PR mở, worktree chỉ bẩn file sinh ra         -> gỡ
#   B như A nhưng còn sửa file thật (src/app.py)                                      -> giữ, kèm lý do
#   C thẻ MỞ / PR mở / lane sống / commit không ref nào giữ                           -> không gỡ
#   D thẻ có PR MERGED riêng                                                          -> vẫn dọn như cũ
set -u
export LC_ALL=C LANG=C DEVKIT_LANG=en
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEAN="${CLEAN:-$ROOT/.claude/bin/super-board-post-merge-clean.sh}"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-closed-1232.XXXXXX")"; SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/worktrees/\n.claude/super-board/\n' > "$R/.gitignore"
mkdir -p "$R/src" "$R/.claude"; echo code > "$R/src/app.py"; echo '{}' > "$R/.claude/settings.json"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q -u origin main; git -C "$R" remote set-head origin main
mkdir -p "$W" "$R/.claude/super-board/inflight"

card() {  # card <N> <branch>: nhánh một commit riêng, đã push, worktree issue-<N>-build
  git -C "$R" branch "$2" main; git -C "$R" worktree add -q "$TMP/edit" "$2"
  echo "c$1" > "$TMP/edit/f$1"; git -C "$TMP/edit" add -A; git -C "$TMP/edit" commit -qm "card $1"
  git -C "$R" worktree remove "$TMP/edit"; git -C "$R" push -q origin "$2"
  git -C "$R" worktree add -q "$W/issue-$1-build" "$2"
}
gen() { echo '{"x":1}' > "$W/issue-$1-build/.claude/settings.json"; mkdir -p "$W/issue-$1-build/.claude/agents"; echo a > "$W/issue-$1-build/.claude/agents/x.md"; }
issue() { printf '{"state":"%s","stateReason":"%s","closedAt":"%s"}\n' "$2" "$3" "$4" > "$TMP/issue$1.json"; }
OLD="2020-01-01T00:00:00Z"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" pr list "*"--state merged"*)
    case "$*" in *"head:issue-28-"*) cat "$FAKE_DIR/merged28.json" ;; *) echo '[]' ;; esac ;;
  *" pr list "*"--state open"*)
    case "$*" in *"head:issue-24-"*) printf '[{"number":240,"headRefName":"issue-24-x","isCrossRepository":false}]\n' ;; *) echo '[]' ;; esac ;;
  *" issue view "*)
    f="$FAKE_DIR/issue$n.json"; [ -f "$f" ] || echo '{"state":"OPEN","stateReason":"","closedAt":""}' > "$f"
    case " $* " in *" -q .state "*) python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$f" ;; *) cat "$f" ;; esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"; export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
unset SB_SWEEP_GRACE_S; export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

card 21 issue-21-a; issue 21 CLOSED COMPLETED "$OLD"; gen 21                                                  # A
card 22 issue-22-b; issue 22 CLOSED COMPLETED "$OLD"; gen 22; echo edit >> "$W/issue-22-build/src/app.py"      # B
card 23 issue-23-open; issue 23 OPEN "" ""                                                                     # C: thẻ mở
card 24 issue-24-x; issue 24 CLOSED COMPLETED "$OLD"                                                           # C: PR mở
card 25 issue-25-lane; issue 25 CLOSED COMPLETED "$OLD"                                                        # C: lane sống
sleep 300 & SL=$!; printf 'PID=%s\nLANE=build\n' "$SL" > "$R/.claude/super-board/inflight/25"
git -C "$R" worktree add -q --detach "$W/issue-26-build" main                                                  # C: commit không ref nào giữ
echo u > "$W/issue-26-build/u"; git -C "$W/issue-26-build" add -A; git -C "$W/issue-26-build" commit -qm unsaved
TIP26=$(git -C "$W/issue-26-build" rev-parse HEAD); issue 26 CLOSED COMPLETED "$OLD"
card 28 issue-28-m; issue 28 CLOSED COMPLETED "$OLD"                                                           # D: PR merged riêng
git -C "$R" merge -q --ff-only issue-28-m; git -C "$R" push -q origin main
printf '[{"number":280,"headRefName":"issue-28-m","headRefOid":"%s","baseRefName":"main","isCrossRepository":false,"mergedAt":"%s"}]\n' \
  "$(git -C "$R" rev-parse issue-28-m)" "$OLD" > "$TMP/merged28.json"
gen 28

bash "$CLEAN" --sweep "$R" --dry-run --min-interval 0 >"$TMP/dry.log" 2>&1
for k in 21 22 23 24 25 26 28; do [ -d "$W/issue-$k-build" ] || fail "d0 --dry-run removed worktree $k"; done
grep -qF "issue-21-build (card closed, no merged PR of its own" "$TMP/dry.log" && ok "d0 --dry-run says it would remove card 21's worktree" || { fail "d0 dry-run does not name worktree 21"; cat "$TMP/dry.log"; }

bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/sweep.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "s0 sweep exit 0" || fail "s0 sweep exit $rc"
[ ! -d "$W/issue-21-build" ] && ok "A closed card, no merged PR, only kit-generated dirt: worktree removed" || { fail "A worktree 21 kept"; grep -a "issue-21\|card 21" "$TMP/sweep.log"; }
[ -d "$W/issue-22-build" ] && [ "$(tail -1 "$W/issue-22-build/src/app.py")" = edit ] && grep -aq "issue-22-build: uncommitted edits outside the salvage list.*src/app.py" "$TMP/sweep.log" \
  && ok "B a real modified file keeps the worktree, with the reason" || { fail "B worktree 22 lost or no reason"; grep -a "issue-22\|card 22" "$TMP/sweep.log"; }
[ -d "$W/issue-23-build" ] && ok "C1 OPEN card untouched" || fail "C1 worktree 23 removed"
[ -d "$W/issue-24-build" ] && ok "C2 card with an open PR untouched" || fail "C2 worktree 24 removed"
[ -d "$W/issue-25-build" ] && ok "C3 live lane keeps the worktree" || fail "C3 worktree 25 removed"
[ -d "$W/issue-26-build" ] && [ "$(git -C "$W/issue-26-build" rev-parse HEAD)" = "$TIP26" ] && ok "C4 a commit no ref keeps: worktree kept" || { fail "C4 worktree 26 lost"; grep -a "issue-26" "$TMP/sweep.log"; }
[ ! -d "$W/issue-28-build" ] && ok "D card with its own merged PR still cleaned" || { fail "D worktree 28 kept"; grep -a "issue-28" "$TMP/sweep.log"; }
[ "$FAILS" -eq 0 ] && { echo "✅ test_sweep_closed_no_merged_pr_1232: all passed"; exit 0; }
echo "❌ test_sweep_closed_no_merged_pr_1232: $FAILS failed"; exit 1
