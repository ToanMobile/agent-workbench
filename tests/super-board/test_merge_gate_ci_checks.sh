#!/usr/bin/env bash
# Hồi quy A4 (bug F5 của #742, tách riêng): .claude/bin/super-board-merge-gate.sh không đọc CI (`gh pr checks` 0 lần) nên PR có
# check đỏ vẫn được squash-merge khi nhánh base không bật required checks. Gate phải đọc CI sau verify, trước migration và merge:
#   C1 check đỏ → exit 11, không `gh pr merge`, tên check có trên stdout (`ci-check:`) và stderr
#   C2 bucket lạ / rỗng → đỏ (fail-closed, exit 11)
#   C3 `gh pr checks` lỗi (không đọc được) → exit 4, không merge
#   C4 "no checks reported" (repo không có CI) → merge như cũ
#   C5 pending rồi pass → merge sau khi hết pending; pending quá SB_MERGE_AUTO_WAIT_S → exit 4, không merge
#   C6 check đỏ khi PR có migration → migration không chạy (đối chứng: check xanh → migration chạy)
#   C7 --dry-run + pending → thoát ngay (đọc CI 1 lần, không ngủ chờ); --dry-run + check đỏ → exit 11
#   C8 head đổi trong lúc chờ pending → exit 6 (về Review); check đỏ nhưng head đã đổi → exit 6, không in `ci-check:`
# Đối chứng: pass + skipping → merge. gh là bản giả, origin bare. Tương thích bash 3.2.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-ci.XXXXXX")"
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
    [ "$st" = pending_then_pass ] && { if [ "$c" -lt 2 ]; then st=pending; else st=pass; fi; }
    case "$st" in
      pass) echo '[{"name":"ci/test","state":"SUCCESS","bucket":"pass"},{"name":"docs","state":"SKIPPED","bucket":"skipping"}]' ;;
      fail) echo '[{"name":"ci/test","state":"FAILURE","bucket":"fail"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
      odd) echo '[{"name":"odd-check","state":"STALE","bucket":"weird"},{"name":"blank-check","state":"","bucket":""},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
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
  rm -f "$TMP/merge.calls" "$TMP/checks.calls" "$TMP/migrated" "$TMP/halt.json"
  local h t0; h=$(cat "$TMP/pr$n.head"); t0=$(date +%s)
  ( cd "$W/issue-$n-review" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --config "$CFG" --pr "$n" --expect-head "$h" --lock-timeout 5 "$@" ) \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  [ ! -e "$TMP/halt.json" ] || cat "$TMP/halt.json" >> "$TMP/halts.log"
}
count() { [ -s "$TMP/$1" ] && wc -l < "$TMP/$1" | tr -d ' ' || echo 0; }
why() { echo "rc=$RC merges=$(count merge.calls) checks=$(count checks.calls) out=[$(tail -4 "$TMP/out" | tr '\n' '|')] err=[$(tail -6 "$TMP/err" | tr '\n' '|')]"; }

# ── Đối chứng: pass + skipping → merge (đọc CI, một lần merge).
card_branch 1 b1
gate 1 FAKE_CHECKS=pass --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && [ "$(count checks.calls)" -ge 1 ] && ! grep -q '^ci-check:' "$TMP/out" \
  && ok "control: passing + skipped checks are read and the PR merges (exit 0, one merge call)" || fail "control pass: $(why)"

# ── C1. check đỏ → exit 11, không merge, tên check trên stdout và stderr.
card_branch 2 b2
gate 2 FAKE_CHECKS=fail --
[ "$RC" -eq 11 ] && [ "$(count merge.calls)" = 0 ] && grep -q '^ci-check: ci/test — FAILURE' "$TMP/out" \
  && grep -q 'ci-check: ci/test — FAILURE' "$TMP/err" && ! grep -q 'ci-check: lint' "$TMP/out" \
  && ok "C1 failing check: exit 11 (back to Build), no gh pr merge, the red check named on stdout and stderr" || fail "C1 failing: $(why)"

# ── C2. bucket lạ / rỗng → đỏ (fail-closed).
gate 2 FAKE_CHECKS=odd --
[ "$RC" -eq 11 ] && [ "$(count merge.calls)" = 0 ] && grep -q '^ci-check: odd-check' "$TMP/out" && grep -q '^ci-check: blank-check' "$TMP/out" \
  && ok "C2 unknown / empty bucket counts as red: exit 11, no merge" || fail "C2 odd bucket: $(why)"

# ── C3. `gh pr checks` không đọc được → exit 4, không merge.
gate 2 FAKE_CHECKS=broken --
[ "$RC" -eq 4 ] && [ "$(count merge.calls)" = 0 ] && [ "$(count checks.calls)" -ge 1 ] && grep -q 'could not read the CI checks' "$TMP/err" \
  && ok "C3 unreadable CI checks: exit 4 (next wave retries), no merge (fail-closed)" || fail "C3 unreadable: $(why)"

# ── C4. repo không có CI ("no checks reported") → merge như cũ.
gate 2 FAKE_CHECKS=none --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && [ "$(count checks.calls)" -ge 1 ] \
  && ok "C4 no checks reported: merges as before (exit 0)" || fail "C4 none: $(why)"

# ── C5. pending rồi pass → merge sau khi hết pending; pending mãi → exit 4.
card_branch 3 b3
gate 3 FAKE_CHECKS=pending_then_pass --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && [ "$(count checks.calls)" -ge 2 ] \
  && ok "C5 pending then pass: waits for the checks, then merges" || fail "C5 pending then pass: $(why)"
card_branch 4 b4
gate 4 FAKE_CHECKS=pending SB_MERGE_AUTO_WAIT_S=1 --
[ "$RC" -eq 4 ] && [ "$(count merge.calls)" = 0 ] && grep -q 'still pending' "$TMP/err" \
  && ok "C5 checks still pending after SB_MERGE_AUTO_WAIT_S: exit 4, no merge" || fail "C5 pending timeout: $(why)"

# ── C6. PR có migration: check đỏ → migration không chạy; đối chứng check xanh → migration chạy rồi merge.
card_branch 5 db/migrate/001_add.sql
gate 5 FAKE_CHECKS=fail --
[ "$RC" -eq 11 ] && [ ! -e "$TMP/migrated" ] && [ "$(count merge.calls)" = 0 ] \
  && ok "C6 red check on a migration PR: exit 11, the migration never runs" || fail "C6 red migration: $(why) migrated=$([ -e "$TMP/migrated" ] && echo yes || echo no)"
gate 5 FAKE_CHECKS=pass --
[ "$RC" -eq 0 ] && [ -e "$TMP/migrated" ] && [ "$(count merge.calls)" = 1 ] \
  && ok "C6 control: green checks on a migration PR: migration runs, then merge" || fail "C6 control: $(why)"

# ── C7. --dry-run: pending → không ngủ chờ (một lần đọc CI); check đỏ → exit 11.
card_branch 6 b6
gate 6 FAKE_CHECKS=pending SB_MERGE_AUTO_POLL_S=30 SB_MERGE_AUTO_WAIT_S=60 -- --dry-run
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 0 ] && [ "$(count checks.calls)" = 1 ] && [ "$ELAPSED" -lt 30 ] \
  && ok "C7 --dry-run with pending checks: reads CI once and returns without sleeping (${ELAPSED}s), nothing merged" || fail "C7 dry pending: $(why) elapsed=${ELAPSED}s"
gate 6 FAKE_CHECKS=fail -- --dry-run
[ "$RC" -eq 11 ] && [ "$(count merge.calls)" = 0 ] && grep -q '^ci-check: ci/test' "$TMP/out" \
  && ok "C7 --dry-run with a red check: exit 11" || fail "C7 dry red: $(why)"
gate 6 FAKE_CHECKS=pass -- --dry-run
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 0 ] && grep -q 'dry run: would squash-merge' "$TMP/err" \
  && ok "C7 control: --dry-run with green checks would merge (exit 0, nothing merged)" || fail "C7 dry control: $(why)"

# ── C8. head đổi trong lúc chờ pending → exit 6; check đỏ nhưng head đã đổi → exit 6, không in ci-check.
card_branch 7 b7
gate 7 FAKE_CHECKS=pending FAKE_MOVE_AFTER_CHECKS=1 --
[ "$RC" -eq 6 ] && [ "$(count merge.calls)" = 0 ] && [ ! -e "$TMP/migrated" ] && ! grep -q '^ci-check:' "$TMP/out" \
  && ok "C8 head moved while waiting for pending checks: exit 6 (back to Review), no merge" || fail "C8 moved pending: $(why)"
gate 7 FAKE_CHECKS=fail FAKE_MOVE_AFTER_CHECKS=1 --
[ "$RC" -eq 6 ] && [ "$(count merge.calls)" = 0 ] && ! grep -q 'ci-check:' "$TMP/out" "$TMP/err" \
  && ok "C8 red check but the head moved meanwhile: exit 6, no ci-check line" || fail "C8 moved red: $(why)"

[ ! -e "$TMP/halts.log" ] && ok "no GitHub halt recorded in any run" || fail "halt recorded: $(cat "$TMP/halts.log")"
[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_ci_checks: all passed" || { echo "❌ test_merge_gate_ci_checks: $FAILS failed"; exit 1; }
