#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 7): merge train, verify đỏ CHỈ ở guard của điểm gộp ([merge-guard] trong .agents/gate-core.txt CỦA BASE)
# ⇒ chạy lại mỗi guard đỏ đúng một lần bằng lệnh ma trận (kiểm `rows == 1` của #578 không áp cho id guard). Khung như
# test_merge_train_single_test_retry.sh (gh giả + origin bare). Tương thích bash 3.2.
#   t1  hai guard đỏ, chạy lại xanh: PR merge, mỗi guard một dòng train-guard-flaky và một comment PR
#   t2  guard đỏ cả lần chạy lại: red, exit 11
#   t3  guard + suite thường đỏ: không chạy lại, red
#   t4  JSON có điều kiện bị REJECT che: không chạy lại, red
#   t5  lệnh verify ghép (`post-fix-gate.py … && npm test`): không chạy lại guard, red
#   t6  hai PR: guard flaky ở lượt [81 82] (đỏ vì 82), [81] xanh sạch: merge 81 KHÔNG kèm ghi chú flaky của lượt đỏ
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"
GCMD="echo x >> $TMP/rerun.count; [ ! -f $TMP/guard.red ]"
python3 - "$R/.agents/regression_matrix.active.json" "$GCMD" <<'PY'
import json, sys
json.dump([{"component": "g", "watch_files": ["*"], "mandatory_regression_tests": [
    {"id": "REG-G1", "name": "guard", "command": sys.argv[2]}, {"id": "REG-G2", "name": "guard 2", "command": sys.argv[2]},
    {"id": "REG-SB-01", "name": "plain suite", "command": "true"}]}], open(sys.argv[1], "w"))
PY
printf '[core]\n.agents/gate-core.txt\n\n[merge-guard]\nREG-G1\nREG-G2\n' > "$R/.agents/gate-core.txt"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  printf '%s\n' "$1" > "$W/issue-$1-build/f$1"
  git -C "$W/issue-$1-build" add "f$1"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$1" > "$TMP/pr$1.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
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
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
mkdir -p "$TMP/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
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
reset_run() { rm -f "$TMP/merged" "$TMP/rerun.count" "$TMP/gh.issue_create" "$TMP/gh.pr_comment" "$TMP/halt.json"; }
merged_list() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
reruns() { if [ -f "$TMP/rerun.count" ]; then wc -l < "$TMP/rerun.count" | tr -d ' '; else echo 0; fi; }

E=$(printf '\033')
mklog() {   # mklog <file> <json> <TRẠNG THÁI|id>...: log giả của post-fix-gate (lớp tĩnh đạt, REJECT) + dòng JSON của --json
  local f="$1" j="$2" s st id; shift 2
  : > "$f"
  for s in "$@"; do
    st="${s%%|*}"; id="${s#*|}"
    printf '    %s[91m[ ] %s%s[0m | %s[1m%-15s%s[0m : name\n' "$E" "$st" "$E" "$E" "$id" "$E" >> "$f"
  done
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E" >> "$f"
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n' >> "$f"
  printf '{"exit_code":1,"matrix_problem":"","tests_touched":%s,"regression_tests":[{"id":"REG-G1","status":"FAIL"}],"unreadable":[],"uncovered":[],"orphan_tests":[],"busy":false,"budget_exhausted":false}\n' "$j" >> "$f"
}
# cfg_log <cfg> <log> [nối thêm]: verify = một post-fix-gate.py giả in log đó và thoát 1 (bỏ qua mọi cờ train chèn)
cfg_log() {
  local d; d=$(mktemp -d "$TMP/pfg.XXXXXX")
  printf 'import sys\nsys.stdout.write(open("%s").read())\nsys.exit(1)\n' "$2" > "$d/post-fix-gate.py"
  printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 %s/post-fix-gate.py%s"]}\n' "$d" "${3:+ $3}" > "$1"
}
git -C "$R" worktree add -q --detach "$W/review" origin/main

# t1
mklog "$TMP/g.log" '[]' "FAIL|REG-G1" "FAIL|REG-G2"
cfg_log "$TMP/cfg1.json" "$TMP/g.log"
card_branch 71; reset_run; rm -f "$TMP/guard.red"
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg1.json" --prs 71 ) >"$TMP/t1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "71 " ] && [ "$(reruns)" = 2 ] && ok "t1. hai guard xanh khi chạy lại: PR merge, mỗi guard chạy lại một lần" \
  || fail "t1. exit $rc merged=$(merged_list) reruns=$(reruns): $(tail -6 "$TMP/t1.log")"
[ "$(grep -c '^train-guard-flaky: 71 REG-G' "$TMP/t1.log")" = 2 ] && [ "$(grep -c 'merge-guard' "$TMP/gh.pr_comment" 2>/dev/null)" = 2 ] \
  && ok "t1. mỗi guard một dòng train-guard-flaky và một comment PR" || fail "t1. ghi chú: $(grep train-guard "$TMP/t1.log" | tr '\n' ';')"

# t2
card_branch 72; reset_run; touch "$TMP/guard.red"
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg1.json" --prs 72 ) >"$TMP/t2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ -z "$(merged_list)" ] && ! grep -q '^train-guard-flaky' "$TMP/t2.log" && ok "t2. guard đỏ cả lần chạy lại: red" \
  || fail "t2. exit $rc merged=$(merged_list): $(tail -6 "$TMP/t2.log")"
rm -f "$TMP/guard.red"

# t3
mklog "$TMP/mixed.log" '[]' "FAIL|REG-G1" "FAIL|REG-SB-01"
cfg_log "$TMP/cfg3.json" "$TMP/mixed.log"
card_branch 73; reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg3.json" --prs 73 ) >"$TMP/t3.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ "$(reruns)" = 0 ] && ok "t3. guard + suite thường: không chạy lại, red" || fail "t3. exit $rc reruns=$(reruns)"

# t4
mklog "$TMP/masked.log" '["tests/t.sh"]' "FAIL|REG-G1"
cfg_log "$TMP/cfg4.json" "$TMP/masked.log"
card_branch 74; reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg4.json" --prs 74 ) >"$TMP/t4.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ "$(reruns)" = 0 ] && ok "t4. điều kiện bị REJECT che: không chạy lại, red" || fail "t4. exit $rc reruns=$(reruns)"

# t5
cfg_log "$TMP/cfg5.json" "$TMP/g.log" "&& echo ran >> $TMP/npm.ran"
card_branch 75; reset_run; rm -f "$TMP/npm.ran"
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg5.json" --prs 75 ) >"$TMP/t5.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ "$(reruns)" = 0 ] && [ -z "$(merged_list)" ] && ok "t5. lệnh verify ghép: không chạy lại guard, red" \
  || fail "t5. exit $rc reruns=$(reruns) merged=$(merged_list)"

# t6: lệnh 1 = guard đỏ khi cây có f82 (chạy lại xanh); lệnh 2 = suite thường đỏ khi cây có f82. Không f82: cả hai xanh.
mklog "$TMP/g6.log" '[]' "FAIL|REG-G1"
mklog "$TMP/p6.log" '[]' "FAIL|REG-SB-01"
mkdir -p "$TMP/c6a" "$TMP/c6b"
for x in a:g6 b:p6; do
  printf 'import os, sys\nif os.path.exists("f82"):\n    sys.stdout.write(open("%s").read()); sys.exit(1)\n' "$TMP/${x#*:}.log" > "$TMP/c6${x%%:*}/post-fix-gate.py"
done
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 %s","python3 %s"]}\n' \
  "$TMP/c6a/post-fix-gate.py" "$TMP/c6b/post-fix-gate.py" > "$TMP/cfg6.json"
card_branch 81; card_branch 82; reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg6.json" --prs 81,82 ) >"$TMP/t6.log" 2>&1; rc=$?
[ "$(merged_list)" = "81 " ] && ! grep -q '^train-guard-flaky' "$TMP/t6.log" && ! grep -q 'merge-guard' "$TMP/gh.pr_comment" 2>/dev/null \
  && ok "t6. merge 81 không kèm ghi chú flaky của lượt [81 82] đỏ" \
  || fail "t6. exit $rc merged=$(merged_list): $(grep -E 'train-(guard-)?flaky|train-result' "$TMP/t6.log" | tr '\n' ';')"

[ "$FAILS" -eq 0 ] && { echo "test_merge_train_guard_retry: PASS"; exit 0; }
echo "test_merge_train_guard_retry: FAIL ($FAILS)"; exit 1
