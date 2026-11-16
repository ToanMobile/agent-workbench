#!/usr/bin/env bash
# Hồi quy #890 (residual sau #882, merge gate đọc CI). gh giả, origin bare, tương thích bash 3.2.
#   R1 base dời trong lúc chờ CI pending: không bao giờ merge cây đã verify trên base cũ (verify chạy lại trên base mới, hoặc exit 4)
#   R2 SB_MERGE_AUTO_WAIT_S 20 chữ số / lớn hơn LOCK_TIMEOUT/2: chờ bị chặn ở LOCK_TIMEOUT/2 rồi exit 4 (code cũ chờ tới 2700 s)
#   R3 SB_MERGE_AUTO_WAIT_S=08 (bát phân) vẫn là 8 giây thập phân, merge sau khi hết pending
#   R4 check rỗng state + rỗng bucket: dòng ci-check in `unknown`, không phải dòng rỗng sau dấu gạch
#   R5 `gh pr checks` lỗi tạm (502) một lần rồi đọc được: merge (code cũ: exit 4 ngay)
#   R6 lỗi đọc CI kéo dài: vẫn exit 4, không merge (fail-closed)
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
# gh giả. `pr checks` đếm lần gọi ở checks.calls; FAKE_CHECKS: pass | pending | pending_then_pass | flaky_then_pass (502 lần đầu) | blank | broken.
# FAKE_BASE_MOVE=1: ở lần đọc CI đầu tiên main của origin tiến thêm một commit (push ngoài gate lúc gate đang chờ CI).
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr checks "*)
    echo "$*" >> "$FAKE_DIR/checks.calls"
    c=$(wc -l < "$FAKE_DIR/checks.calls" | tr -d ' ')
    if [ "${FAKE_BASE_MOVE:-0}" = 1 ] && [ "$c" -eq 1 ]; then
      t="$FAKE_DIR/mover$n"; git clone -q "$FAKE_ORIGIN" "$t"; echo moved > "$t/moved"
      git -C "$t" add moved; git -C "$t" -c user.email=t@example.invalid -c user.name=t commit -qm "main moves"
      git -C "$t" push -q origin HEAD:refs/heads/main
    fi
    st=${FAKE_CHECKS:-pass}
    [ "$st" = pending_then_pass ] && { if [ "$c" -lt 2 ]; then st=pending; else st=pass; fi; }
    [ "$st" = flaky_then_pass ] && { if [ "$c" -lt 2 ]; then st=broken; else st=pass; fi; }
    case "$st" in
      pass) echo '[{"name":"ci/test","state":"SUCCESS","bucket":"pass"}]' ;;
      pending) echo '[{"name":"ci/test","state":"IN_PROGRESS","bucket":"pending"}]'; exit 8 ;;
      blank) echo '[{"name":"blank-check","state":"","bucket":""}]'; exit 1 ;;
      *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac ;;
  *" pr merge "*) echo "$*" >> "$FAKE_DIR/merge.calls"
                  git -C "$FAKE_REPO" push -q origin "$head:refs/heads/main" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R" FAKE_ORIGIN="$O"
export SB_NOTIFY_SKIP=1 SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0
export SB_MERGE_AUTO_POLL_S=1 SB_MERGE_AUTO_WAIT_S=20
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo v >> %s/verify.calls"],
  "migrations":{"allowed_envs":["test"],"target_env":"test","commands":{"test":"touch %s/migrated"}}}\n' "$TMP" "$TMP" > "$CFG"

# gate <N> <env…> -- <args…>: chạy gate từ worktree review của thẻ N; RC, out (stdout), err (stderr), ELAPSED (giây).
gate() {
  local n="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$TMP/merge.calls" "$TMP/checks.calls" "$TMP/verify.calls" "$TMP/migrated" "$TMP/halt.json"
  local h t0; h=$(cat "$TMP/pr$n.head"); t0=$(date +%s)
  ( cd "$W/issue-$n-review" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --config "$CFG" --pr "$n" --expect-head "$h" --lock-timeout 5 "$@" ) \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  [ ! -e "$TMP/halt.json" ] || cat "$TMP/halt.json" >> "$TMP/halts.log"
}
count() { [ -s "$TMP/$1" ] && wc -l < "$TMP/$1" | tr -d ' ' || echo 0; }
why() { echo "rc=$RC merges=$(count merge.calls) checks=$(count checks.calls) out=[$(tail -4 "$TMP/out" | tr '\n' '|')] err=[$(tail -6 "$TMP/err" | tr '\n' '|')]"; }


# R1: base dời lúc chờ CI (gh giả không squash thật: merge.calls=1 chỉ nói gate ĐÃ gọi merge, rc không đáng tin). Cây merge đã verify trên base cũ không được squash-merge nguyên: verify lại (verify.calls ≥ 2) hoặc không merge.
card_branch 1 b1
gate 1 FAKE_CHECKS=pending_then_pass FAKE_BASE_MOVE=1 --
if [ "$(count merge.calls)" = 0 ]; then [ "$RC" -eq 4 ] && ok "R1 base moved while waiting for CI: not merged (exit 4)" || fail "R1: $(why)"
else [ "$(count verify.calls)" -ge 2 ] && ok "R1 base moved while waiting for CI: merged only after verifying again on the new base ($(count verify.calls) verify runs)" || fail "R1 merged an old-base tree: $(why) verifies=$(count verify.calls)"; fi

# R2: 20 chữ số và LOCK_TIMEOUT 4 ⇒ chờ tối đa 2 s rồi exit 4 (code cũ: `[` báo số quá lớn, hạn chờ không bao giờ tới).
card_branch 2 b2
gate 2 FAKE_CHECKS=pending SB_MERGE_AUTO_WAIT_S=99999999999999999999 SB_MERGE_AUTO_POLL_S=1 --
[ "$RC" -eq 4 ] && [ "$(count merge.calls)" = 0 ] && [ "$ELAPSED" -lt 15 ] && ok "R2 20-digit SB_MERGE_AUTO_WAIT_S is capped at LOCK_TIMEOUT/2: exit 4 after ${ELAPSED}s" || fail "R2: $(why) elapsed=${ELAPSED}s"

# R3: 08 là thập phân; pending rồi pass trong hạn ⇒ merge.
card_branch 3 b3
gate 3 FAKE_CHECKS=pending_then_pass SB_MERGE_AUTO_WAIT_S=08 SB_MERGE_AUTO_POLL_S=1 -- --lock-timeout 40
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && ok "R3 SB_MERGE_AUTO_WAIT_S=08 read as decimal: waits, then merges" || fail "R3: $(why)"

# R4: state và bucket rỗng ⇒ ci-check ... — unknown.
card_branch 4 b4
gate 4 FAKE_CHECKS=blank --
[ "$RC" -eq 11 ] && grep -q '^ci-check: blank-check — unknown$' "$TMP/out" && ok "R4 empty state and bucket print 'unknown'" || fail "R4: $(why) out=$(cat "$TMP/out")"

# R5: lỗi đọc tạm một lần ⇒ thử lại, merge.
card_branch 5 b5
gate 5 FAKE_CHECKS=flaky_then_pass --
[ "$RC" -eq 0 ] && [ "$(count merge.calls)" = 1 ] && ok "R5 one transient 502 reading CI is retried: merges" || fail "R5: $(why)"

# R6: lỗi kéo dài ⇒ exit 4, không merge, đủ 3 lần đọc.
card_branch 6 b6
gate 6 FAKE_CHECKS=broken --
[ "$RC" -eq 4 ] && [ "$(count merge.calls)" = 0 ] && [ "$(count checks.calls)" -ge 3 ] && ok "R6 persistent read failure: 3 reads, exit 4, no merge (fail-closed)" || fail "R6: $(why)"

[ ! -e "$TMP/halts.log" ] && ok "no GitHub halt recorded in any run" || fail "halt recorded: $(cat "$TMP/halts.log")"
[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_ci_residual: all passed" || { echo "❌ test_merge_gate_ci_residual: $FAILS failed"; exit 1; }
