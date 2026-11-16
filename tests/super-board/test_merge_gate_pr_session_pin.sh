#!/usr/bin/env bash
# Hồi quy #981: lượt gate trực tiếp thiếu --expect-head chỉ in WARNING rồi ghim head vừa đọc, nên PR phiên không có review độc lập vẫn merge.
# Giờ: không --expect-head thì cần comment approved-head:<sha40> hợp lệ (super-board-approved-head.jq) = head; không có => không merge (exit 6).
#   S1 không approved-head, không --expect-head  => exit 6, không gh pr merge
#   S2 approved-head (OWNER, bare) = head         => merge (exit 0)
#   S3 approved-head ≠ head                       => exit 6, không merge
#   S4 approved-head bare của COLLABORATOR        => exit 6 (cần approved-by)
#   S5 --dry-run không --expect-head, không duyệt => không chặn (giữ như cũ, chỉ cảnh báo)
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
  local h t0 EXH=(); h=$(cat "$TMP/pr$n.head"); t0=$(date +%s); [ -z "${USE_EXPECT:-}" ] || EXH=(--expect-head "$h")
  ( cd "$W/issue-$n-review" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --config "$CFG" --pr "$n" ${EXH[@]+"${EXH[@]}"} --lock-timeout 5 "$@" ) \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  [ ! -e "$TMP/halt.json" ] || cat "$TMP/halt.json" >> "$TMP/halts.log"
}
count() { [ -s "$TMP/$1" ] && wc -l < "$TMP/$1" | tr -d ' ' || echo 0; }
why() { echo "rc=$RC merges=$(count merge.calls) checks=$(count checks.calls) out=[$(tail -4 "$TMP/out" | tr '\n' '|')] err=[$(tail -6 "$TMP/err" | tr '\n' '|')]"; }


# meta_with <N> <assoc> <approved-sha|-> : PR meta với comment approved-head.
meta_with() {
  local n="$1" assoc="$2" sha="$3" body=""
  [ "$sha" = - ] || body="[qa] ok\napproved-head:$sha"
  printf '{"files":[{"path":"b%s","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1,"author":{"login":"builder"},"comments":[{"authorAssociation":"%s","author":{"login":"rev"},"body":"%s"}]}' "$n" "$assoc" "$body" > "$TMP/pr$n.meta"
}
card_branch 1 b1; meta_with 1 OWNER -
gate 1 FAKE_CHECKS=pass --
[ "$RC" -eq 6 ] && [ "$(count merge.calls)" = 0 ] && ok "S1 no approved-head, no --expect-head: exit 6, no merge" || fail "S1: $(why)"
meta_with 1 OWNER "$(cat "$TMP/pr1.head")"
gate 1 FAKE_CHECKS=pass --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && ok "S2 approved-head = head (OWNER): merges" || fail "S2: $(why)"
card_branch 2 b2; meta_with 2 OWNER 1111111111111111111111111111111111111111
gate 2 FAKE_CHECKS=pass --
[ "$RC" -eq 6 ] && [ "$(count merge.calls)" = 0 ] && ok "S3 approved-head != head: exit 6, no merge" || fail "S3: $(why)"
meta_with 2 COLLABORATOR "$(cat "$TMP/pr2.head")"
gate 2 FAKE_CHECKS=pass --
[ "$RC" -eq 6 ] && [ "$(count merge.calls)" = 0 ] && ok "S4 bare approved-head of a COLLABORATOR: exit 6" || fail "S4: $(why)"
meta_with 2 OWNER -
gate 2 FAKE_CHECKS=pass -- --dry-run
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 0 ] && ok "S5 --dry-run without approval keeps the old warning path" || fail "S5: $(why)"
[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_pr_session_pin: all passed" || { echo "❌ test_merge_gate_pr_session_pin: $FAILS failed"; exit 1; }
