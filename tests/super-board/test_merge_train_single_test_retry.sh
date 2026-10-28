#!/usr/bin/env bash
# Test hồi quy #578: verify đỏ CHỈ vì đúng một test của REG-DK-ALL-01 thì train chạy lại đúng test đó một lần trước khi gán red.
# Offline: `gh` giả + origin bare (cùng khung với test_merge_train.sh). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-retry-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card_branch <N> <file> [<content>]: nhánh issue-<N>-x thêm file <file>, đã đẩy lên origin; ghi diff + metadata cho gh giả.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  mkdir -p "$W/issue-$1-build/$(dirname "$2")"
  printf '%s\n' "${3:-$1}" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":%s,"deletions":0,"changedFiles":1}' "$2" "$(git -C "$R" diff --numstat origin/main "issue-$1-x" | cut -f1)" > "$TMP/pr$1.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: trạng thái PR từ $FAKE_DIR/pr<N>.*; `pr merge` mô phỏng squash; `issue list/create` và `pr comment` được ghi lại cho test.
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head" 2>/dev/null)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *" issue list "*) echo 0 ;;
  *" issue create "*) printf '%s\n' "$*" >> "$FAKE_DIR/gh.issue_create"; echo "https://example.invalid/issues/900" ;;
  *" pr comment "*) printf '%s\n' "$*" >> "$FAKE_DIR/gh.pr_comment" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
mkdir -p "$TMP/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
# Shim: preflight luôn qua; mọi lời gọi khác exec merge gate thật.
for a in "\$@"; do
  if [ "\$a" = --preflight ]; then echo "preflight: ok"; exit 0; fi
done
exec bash "$ROOT/.claude/bin/super-board-merge-gate.sh" "\$@"
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/rerun.count" "$TMP/gh.issue_create" "$TMP/gh.pr_comment"; }
merged_list() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reruns() { if [ -f "$TMP/rerun.count" ]; then wc -l < "$TMP/rerun.count" | tr -d ' '; else echo 0; fi; }

# card_script <N> <path> <exit>: PR thêm test <path>: ghi một dòng vào $TMP/rerun.count rồi thoát <exit>.
card_script() { card_branch "$1" "$2" "$(printf 'echo x >> %s/rerun.count\nexit %s' "$TMP" "$3")"; }

# Log giả theo định dạng post-fix-gate (lớp tĩnh đạt, KẾT LUẬN REJECT): mỗi đối số là `TRẠNG THÁI|id|dòng đuôi`.
E=$(printf '\033')
mklog() {
  local f="$1" s st id tl; shift
  : > "$f"
  for s in "$@"; do
    IFS='|' read -r st id tl <<EOT
$s
EOT
    printf '    %s[91m[ ] %s%s[0m | %s[1m%-15s%s[0m : name\n' "$E" "$st" "$E" "$E" "$id" "$E" >> "$f"
    [ -z "$tl" ] || printf '           %s[2m| %s%s[0m\n' "$E" "$tl" "$E" >> "$f"
  done
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91m%s[1mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E" "$E" >> "$f"
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n' >> "$f"
}
# cfg_log <cfg> <log>: lệnh verify luôn in <log> rồi thoát 1 (đỏ).
cfg_log() { printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; cat %s; exit 1"]}\n' "$TMP" "$2" > "$1"; }
git -C "$R" worktree add -q --detach "$W/review" origin/main

# ── 1. Đúng một test đỏ, chạy lại XANH: PR merge, ghi rõ flaky vào PR và vào thẻ riêng của test; verify chỉ chạy 1 lần.
mklog "$TMP/one.log" "FAIL|REG-DK-ALL-01|✖ tests/gates/test_flaky.sh"
cfg_log "$TMP/cfg1.json" "$TMP/one.log"
card_script 61 tests/gates/test_flaky.sh 0
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg1.json" --prs 61 ) >"$TMP/t1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "61 " ] && ok "flaky: PR merged (exit 0)" || fail "flaky: exit $rc merged=$(merged_list): $(tail -6 "$TMP/t1.log")"
[ "$(runs)" = 1 ] && [ "$(reruns)" = 1 ] && ok "flaky: verify ran once, the one red test re-ran exactly once" || fail "flaky: verify $(runs) times, re-ran $(reruns) times"
grep -q "^train-flaky: 61 tests/gates/test_flaky.sh" "$TMP/t1.log" && ok "flaky: train-flaky line names the test" || fail "flaky: no train-flaky line: $(grep train "$TMP/t1.log")"
grep -q "flaky" "$TMP/gh.pr_comment" 2>/dev/null && ok "flaky: noted on the PR" || fail "flaky: no PR comment"
grep -q "test_flaky.sh" "$TMP/gh.issue_create" 2>/dev/null && ok "flaky: card filed for the test" || fail "flaky: no card for the test"

# ── 2. Đỏ cả hai lần: vẫn red, train-detail có tên test, không ghi flaky.
mklog "$TMP/two.log" "FAIL|REG-DK-ALL-01|✖ tests/gates/test_real.sh"
cfg_log "$TMP/cfg2.json" "$TMP/two.log"
card_script 62 tests/gates/test_real.sh 1
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg2.json" --prs 62 ) >"$TMP/t2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ -z "$(merged_list)" ] && grep -q "^train-result: 62 red$" "$TMP/t2.log" && ok "red twice: train-result red, exit 11, nothing merged" || fail "red twice: exit $rc merged=$(merged_list): $(tail -6 "$TMP/t2.log")"
[ "$(reruns)" = 1 ] && ok "red twice: re-ran once, not more" || fail "red twice: re-ran $(reruns) times"
grep -q "^train-detail: 62 .*test_real.sh" "$TMP/t2.log" && ok "red twice: train-detail names the test" || fail "red twice: no test name in detail: $(grep train "$TMP/t2.log")"
[ ! -e "$TMP/gh.pr_comment" ] && ! grep -q "^train-flaky" "$TMP/t2.log" && ok "red twice: no flaky note" || fail "red twice: flaky note written"

# ── 3. Không nới tiêu chuẩn: hai test đỏ / một suite khác cũng đỏ / tên test mất / đường dẫn ra ngoài cây → red ngay, không chạy lại.
card_script 63 tests/gates/test_a.sh 0
{ mklog "$TMP/multi.log" "FAIL|REG-DK-ALL-01|✖ tests/gates/test_a.sh"; printf '           %s[2m| ✖ tests/gates/test_b.sh%s[0m\n' "$E" "$E" >> "$TMP/multi.log"; }
mklog "$TMP/other.log" "FAIL|REG-DK-ALL-01|✖ tests/gates/test_a.sh" "FAIL|REG-SB-01|AssertionError"
mklog "$TMP/noname.log" "FAIL|REG-DK-ALL-01|AssertionError: cut tail"
mklog "$TMP/escape.log" "FAIL|REG-DK-ALL-01|✖ ../../etc/passwd.sh"
n=3
for c in multi other noname escape; do
  n=$((n + 1)); cfg_log "$TMP/cfg$n.json" "$TMP/$c.log"; reset_run
  ( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg$n.json" --prs 63 ) >"$TMP/t$n.log" 2>&1; rc=$?
  [ "$rc" -eq 11 ] && [ "$(reruns)" = 0 ] && [ -z "$(merged_list)" ] && ok "$c: red at once, no re-run" || fail "$c: exit $rc reruns=$(reruns) merged=$(merged_list): $(tail -4 "$TMP/t$n.log")"
done

# ── 4. #616: một suite shard (REG-DK-ALL-GATES-01) cũng được chạy lại riêng đúng test đỏ: flaky, PR merge, verify 1 lần.
mklog "$TMP/shard.log" "FAIL|REG-DK-ALL-GATES-01|✖ tests/gates/test_shard_flaky.sh"
cfg_log "$TMP/cfg9.json" "$TMP/shard.log"
card_script 64 tests/gates/test_shard_flaky.sh 0
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg9.json" --prs 64 ) >"$TMP/t9.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "64 " ] && [ "$(runs)" = 1 ] && [ "$(reruns)" = 1 ] && grep -q "^train-flaky: 64 tests/gates/test_shard_flaky.sh" "$TMP/t9.log" \
  && ok "shard id: one red test re-ran once, flaky, PR merged" || fail "shard id: exit $rc merged=$(merged_list) runs=$(runs) reruns=$(reruns): $(tail -4 "$TMP/t9.log")"
# hai suite shard cùng đỏ → vẫn red ngay (không nới)
mklog "$TMP/shard2.log" "FAIL|REG-DK-ALL-GATES-01|✖ tests/gates/test_a.sh" "FAIL|REG-DK-ALL-REST-01|✖ tests/gates/test_b.sh"
cfg_log "$TMP/cfg10.json" "$TMP/shard2.log"
card_script 65 tests/gates/test_a.sh 0
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg10.json" --prs 65 ) >"$TMP/t10.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ "$(reruns)" = 0 ] && ok "two red shard suites: red at once, no re-run" || fail "two red shard suites: exit $rc reruns=$(reruns)"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_train_single_test_retry: all passed" || { echo "❌ test_merge_train_single_test_retry: $FAILS failed"; exit 1; }
