#!/usr/bin/env bash
# 18/10 (GeelyEx2 PR #48): khi verify đỏ, .claude/bin/super-board-merge-gate.sh chép log vào "$REPO_PATH/.claude/super-board/
# last-merge-verify-pr-<N>.log". repo.path là "." = thư mục đang đứng, thường là một worktree; repo nào không ignore mẫu đó thì file chưa track
# này làm `agent-kit worktree remove` từ chối gỡ worktree. Luật: log nằm NGOÀI mọi worktree (git common dir/super-board/), worktree sạch.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-verifylog-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"   # như GeelyEx2: KHÔNG ignore .claude/super-board/*.log
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo verify-said-no; false"]}' > "$CFG"

( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ok "red verify, branch not behind base: merge gate exit 11" || fail "gate exit $rc (want 11): $(tail -5 "$TMP/gate.log")"
[ ! -e "$WT/.claude/super-board/last-merge-verify-pr-5.log" ] && [ -z "$(git -C "$WT" status --porcelain)" ] \
  && ok "no log file left in the worktree it ran from (status clean, worktree remove not blocked)" \
  || fail "log written into the worktree: $(git -C "$WT" status --porcelain | head -3)"
CD="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"   # như gate: cd + pwd -P (không --path-format, git < 2.31)
[ -n "$CD" ] && [ -d "$CD" ] || { fail "fixture: git common dir not found"; echo "test_merge_gate_verify_log_outside: FAIL"; exit 1; }   # không bao giờ rm -rf "/super-board"
grep -q "verify-said-no" "$CD/super-board/last-merge-verify-pr-5.log" 2>/dev/null && grep -qF "$CD/super-board/last-merge-verify-pr-5.log" "$TMP/gate.log" \
  && ok "the log is kept in the git common dir and the message names that path" || fail "log not in $CD/super-board: $(grep 'log saved' "$TMP/gate.log")"

# Không ghi được log (một FILE tên super-board chiếm chỗ thư mục): vẫn exit 11 đúng lý do, nói "(not saved)", không chết giữa chừng (set -e)
rm -rf "$CD/super-board" && : > "$CD/super-board"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && grep -q "log saved to (not saved)" "$TMP/gate2.log" && grep -q "verify-said-no" "$TMP/gate2.log" \
  && ok "log cannot be written: still exit 11, the verify output on stderr, '(not saved)' said" || fail "unwritable log dir (rc $rc): $(tail -3 "$TMP/gate2.log")"

# Verify chạy trong scratch nhưng post-fix-gate ưu tiên CLAUDE_PROJECT_DIR / TARGET_DIR hơn cwd: bên gọi mang sẵn hai biến đó (runner, agent)
# thì verify kiểm nhầm cây chính → xanh sai. Cả hai nhánh (lệnh post-fix-gate.py chạy eval, lệnh khác qua heavy-slot) phải gỡ chúng.
rm -f "$CD/super-board"
for kind in pfg other; do
  if [ "$kind" = pfg ]; then cmd=": post-fix-gate.py; echo \\\"\${CLAUDE_PROJECT_DIR:-unset}|\${TARGET_DIR:-unset}\\\" > $TMP/env-$kind.seen; false"
  else cmd="echo \\\"\${CLAUDE_PROJECT_DIR:-unset}|\${TARGET_DIR:-unset}\\\" > $TMP/env-$kind.seen; false"; fi
  printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["%s"]}\n' "$cmd" > "$TMP/cfg-env-$kind.json"
  ( cd "$WT" && CLAUDE_PROJECT_DIR="$R" TARGET_DIR="$R" bash "$GATE" --config "$TMP/cfg-env-$kind.json" --pr 5 --expect-head "$H" ) >"$TMP/gate-env-$kind.log" 2>&1
  seen=$(cat "$TMP/env-$kind.seen" 2>/dev/null || echo "<verify did not run>")
  [ "$seen" = "unset|unset" ] && ok "verify ($kind) runs without the caller's CLAUDE_PROJECT_DIR / TARGET_DIR" \
    || fail "verify ($kind) inherited the caller's project dir (checks the wrong tree): $seen"
done

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_verify_log_outside: PASS"; exit 0; } || { echo "test_merge_gate_verify_log_outside: FAIL ($FAILS)"; exit 1; }
