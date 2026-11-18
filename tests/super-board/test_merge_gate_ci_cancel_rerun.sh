#!/usr/bin/env bash
# Regression #1021 (17/11): PR #1239's devkit-tests run was CANCELLED by GitHub (pr-review.yml concurrency cancel-in-progress)
# while its head stayed the same; the merge gate read bucket "cancel" as red, exit 11 sent the card back to Build, and after
# rebuild_cap the card went Blocked. A re-run of the same check passed in 28 s. A cancelled check is no verdict on the code:
#   K1 cancel, then pass after a re-run -> the gate re-runs the cancelled run once (gh run rerun <id>), waits, merges (exit 0)
#   K2 cancel that never clears -> exit 4 (next wave retries), never 11 (no rebuild), no merge
#   K3 control: fail stays red (exit 11) and is never re-run
# Same fake-gh harness as test_merge_gate_ci_checks.sh. bash 3.2 compatible.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-ci-cancel.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card_branch <N> <file>: nhánh issue-<N>-x thêm đúng một dòng vào <file>, đã push; diff + metadata cho gh giả; worktree review.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  mkdir -p "$(dirname "$W/issue-$1-build/$2")"; echo "$1" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
  git -C "$R" worktree add -q --detach "$W/issue-$1-review" "$(cat "$TMP/pr$1.head")"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: `pr checks` trả theo FAKE_CHECKS (đếm lần gọi ở checks.calls); `pr merge` ghi merge.calls và đưa head lên main của origin.
# FAKE_MOVE_AFTER_CHECKS=1: sau lần đọc CI đầu tiên, PR báo head khác (push mới trong lúc gate chờ).
case " $* " in *" run rerun "*) echo "$*" >> "$FAKE_DIR/rerun.calls"; exit 0 ;; esac
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    now=$head
    [ "${FAKE_MOVE_AFTER_CHECKS:-0}" = 1 ] && [ -s "$FAKE_DIR/checks.calls" ] && now=0000000000000000000000000000000000000000
    printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$now" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr checks "*)
    echo "$*" >> "$FAKE_DIR/checks.calls"
    c=$(wc -l < "$FAKE_DIR/checks.calls" | tr -d ' ')
    st=${FAKE_CHECKS:-pass}
    [ "$st" = cancel_then_pass ] && { if [ -s "$FAKE_DIR/rerun.calls" ]; then st=pass; else st=cancel; fi; }
    [ "$st" = pending_then_pass ] && { if [ "$c" -lt 2 ]; then st=pending; else st=pass; fi; }
    case "$st" in
      pass) echo '[{"name":"ci/test","state":"SUCCESS","bucket":"pass"},{"name":"docs","state":"SKIPPED","bucket":"skipping"}]' ;;
      fail) echo '[{"name":"ci/test","state":"FAILURE","bucket":"fail"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
      odd) echo '[{"name":"odd-check","state":"STALE","bucket":"weird"},{"name":"blank-check","state":"","bucket":""},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
      cancel) echo '[{"name":"ci/test","state":"CANCELLED","bucket":"cancel","link":"https://github.com/o/r/actions/runs/4411/job/77"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
      pending) echo '[{"name":"ci/test","state":"IN_PROGRESS","bucket":"pending"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 8 ;;
      none) echo "no checks reported on the 'issue-$n-x' branch" >&2; exit 1 ;;
      *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac ;;
  *" pr merge "*) echo "$*" >> "$FAKE_DIR/merge.calls"
                  git -C "$FAKE_REPO" push -q origin "$head:refs/heads/main" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_NOTIFY_SKIP=1 SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0
export SB_MERGE_AUTO_POLL_S=1 SB_MERGE_AUTO_WAIT_S=20
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"],
  "migrations":{"allowed_envs":["test"],"target_env":"test","commands":{"test":"touch %s/migrated"}}}\n' "$TMP" > "$CFG"

# gate <N> <env…> -- <args…>: chạy gate từ worktree review của thẻ N; RC, out (stdout), err (stderr), ELAPSED (giây).
gate() {
  local n="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$TMP/merge.calls" "$TMP/checks.calls" "$TMP/rerun.calls" "$TMP/migrated" "$TMP/halt.json"
  local h t0; h=$(cat "$TMP/pr$n.head"); t0=$(date +%s)
  ( cd "$W/issue-$n-review" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --config "$CFG" --pr "$n" --expect-head "$h" --lock-timeout 5 "$@" ) \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  [ ! -e "$TMP/halt.json" ] || cat "$TMP/halt.json" >> "$TMP/halts.log"
}
count() { [ -s "$TMP/$1" ] && wc -l < "$TMP/$1" | tr -d ' ' || echo 0; }
why() { echo "rc=$RC merges=$(count merge.calls) checks=$(count checks.calls) out=[$(tail -4 "$TMP/out" | tr '\n' '|')] err=[$(tail -6 "$TMP/err" | tr '\n' '|')]"; }

card_branch 1 b1
gate 1 FAKE_CHECKS=cancel_then_pass --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && grep -q 'run rerun 4411' "$TMP/rerun.calls" 2>/dev/null \
  && ok "K1 cancelled check: re-run once, then merges" || fail "K1 cancel then pass: $(why) reruns=$(count rerun.calls)"

card_branch 2 b2
gate 2 FAKE_CHECKS=cancel SB_MERGE_AUTO_WAIT_S=2 --
[ "$RC" -eq 4 ] && [ "$(count merge.calls)" = 0 ] && [ "$(count rerun.calls)" = 1 ] \
  && ok "K2 check stays cancelled: exit 4 (retry next wave, no rebuild), one re-run, no merge" || fail "K2 cancel forever: $(why) reruns=$(count rerun.calls)"

card_branch 3 b3
gate 3 FAKE_CHECKS=fail --
[ "$RC" -eq 11 ] && [ "$(count merge.calls)" = 0 ] && [ "$(count rerun.calls)" = 0 ] \
  && ok "K3 control: failing check stays red (exit 11), never re-run" || fail "K3 fail: $(why) reruns=$(count rerun.calls)"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_ci_cancel_rerun: all passed" || { echo "❌ test_merge_gate_ci_cancel_rerun: $FAILS failed"; exit 1; }
