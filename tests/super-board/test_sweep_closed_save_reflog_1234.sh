#!/usr/bin/env bash
# #1234: --sweep gỡ worktree của thẻ CLOSED (không PR merged riêng) dù còn commit chỉ-reflog (bằng chứng QA v1 bị lùi nhánh): kit
# `remove --save-reflog` cất commit vào refs/devkit/discarded/* rồi gỡ. Thẻ mở / có PR mở: không gỡ. Offline: gh giả, kit thật.
# CLEAN=<file> chạy bản cũ để thấy ĐỎ.
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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-closed-1234.XXXXXX")"; SL=""
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


# E: CLOSED card, detached worktree, a QA evidence commit v1 that only the HEAD reflog names (HEAD moved back to the branch tip)
card 31 issue-31-qa; issue 31 CLOSED COMPLETED "$OLD"
git -C "$W/issue-31-build" checkout -q --detach; echo v1 > "$W/issue-31-build/ev"; git -C "$W/issue-31-build" add -A; git -C "$W/issue-31-build" commit -qm "evidence v1"
SHA31=$(git -C "$W/issue-31-build" rev-parse HEAD); git -C "$W/issue-31-build" reset -q --hard HEAD~1
# F: same shape, but the card is OPEN / has an OPEN PR
card 32 issue-32-open; issue 32 OPEN "" ""
git -C "$W/issue-32-build" checkout -q --detach; echo v1 > "$W/issue-32-build/ev"; git -C "$W/issue-32-build" add -A; git -C "$W/issue-32-build" commit -qm "evidence v1"; git -C "$W/issue-32-build" reset -q --hard HEAD~1
card 24 issue-24-x; issue 24 CLOSED COMPLETED "$OLD"
git -C "$W/issue-24-build" checkout -q --detach; echo v1 > "$W/issue-24-build/ev"; git -C "$W/issue-24-build" add -A; git -C "$W/issue-24-build" commit -qm "evidence v1"; git -C "$W/issue-24-build" reset -q --hard HEAD~1

bash "$CLEAN" --sweep "$R" --dry-run --min-interval 0 >"$TMP/dry.log" 2>&1
for k in 24 31 32; do [ -d "$W/issue-$k-build" ] || fail "d0 --dry-run removed worktree $k"; done
bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/sweep.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "s0 sweep exit 0" || fail "s0 sweep exit $rc"
kept=0; for r in $(git -C "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/*'); do git -C "$R" merge-base --is-ancestor "$SHA31" "$r" 2>/dev/null && kept=1; done
[ ! -d "$W/issue-31-build" ] && [ "$kept" = 1 ] && ok "E closed card with a reflog-only commit: worktree removed, commit kept under refs/devkit/discarded" || { fail "E worktree 31 kept=$kept"; grep -a "issue-31\|card 31" "$TMP/sweep.log"; }
[ -d "$W/issue-32-build" ] && ok "F1 OPEN card untouched" || fail "F1 worktree 32 removed"
[ -d "$W/issue-24-build" ] && ok "F2 card with an open PR untouched" || fail "F2 worktree 24 removed"
[ "$FAILS" -eq 0 ] && { echo "✅ test_sweep_closed_save_reflog_1234: all passed"; exit 0; }
echo "❌ test_sweep_closed_save_reflog_1234: $FAILS failed"; exit 1
