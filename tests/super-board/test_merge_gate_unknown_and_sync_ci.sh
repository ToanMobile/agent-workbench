#!/usr/bin/env bash
# #1021 (P3 của review #1016): merge gate
#   1) MG_BASE gán cả khi lần đọc mergeable đầu là UNKNOWN: base không dời thì trong khoá không đọc lại, PR thành CONFLICTING chỉ lộ ở
#      `gh pr merge` sau verify. Mong đợi: UNKNOWN ⇒ đọc lại trong khoá ⇒ exit 14; gh pr merge được gọi 0 lần.
#   2) sau autosync_push trong khoá, ci_precheck chạy khi check của head mới chưa đăng ký. Mong đợi: chờ có hạn tới khi danh sách check
#      khác rỗng rồi mới merge; hết hạn ⇒ exit 4 (như CI pending).
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-unknown-sync-ci-test.XXXXXX")"
trap '[ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_MERGEABLE_POLL_S=0 SB_MERGE_AUTO_POLL_S=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX SB_MERGE_OPTIMISTIC SB_MERGE_WAIT_HOLDER_S SB_MERGE_SYNC_CI_WAIT_S

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
O="$FAKE_DIR/origin.git"
tip() { git -C "$O" rev-parse refs/heads/issue-61-x 2>/dev/null || echo 0000000000000000000000000000000000000000; }
conflicting() { ! git -C "$O" merge-base --is-ancestor refs/heads/main "$(tip)" 2>/dev/null; }
case " $* " in
  *" pr view "*"--json mergeable"*)
    # ca 1: GitHub còn tính (UNKNOWN) tới khi verify chạy xong
    if [ -e "$FAKE_DIR/unknown-until-verify" ] && [ ! -e "$FAKE_DIR/verify-ran" ]; then echo UNKNOWN
    elif [ -e "$FAKE_DIR/unknown-until-ci-pending" ] && [ ! -e "$FAKE_DIR/ci-pending-done" ]; then echo UNKNOWN
    elif conflicting; then echo CONFLICTING; else echo MERGEABLE; fi | tee -a "$FAKE_DIR/mergeable-answers" ;;
  *" pr checks "*)
    # ca 2: head cũ X luôn có check; head đồng bộ Y chưa có check ở FAKE_EMPTY_READS lần đọc đầu
    if [ "$(tip)" = "$(cat "$FAKE_DIR/x" 2>/dev/null)" ]; then
      # ca 4: lần đọc thứ 2 sau verify (ci_precheck trong khoá; lần 1 là trước khoá) trả pending một lần rồi xanh
      if [ -e "$FAKE_DIR/pending-once" ] && [ -e "$FAKE_DIR/verify-ran" ] && [ ! -e "$FAKE_DIR/ci-pending-done" ]; then
        echo x >> "$FAKE_DIR/post-verify-reads"
        [ "$(wc -l < "$FAKE_DIR/post-verify-reads")" -ge 2 ] || { echo '[{"name":"ci","state":"SUCCESS","bucket":"pass"}]'; exit 0; }
        touch "$FAKE_DIR/ci-pending-done"; echo '[{"name":"ci","state":"PENDING","bucket":"pending"}]'; exit 0; fi
      echo '[{"name":"ci","state":"SUCCESS","bucket":"pass"}]'; exit 0; fi
    n=$(cat "$FAKE_DIR/checks-reads" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_DIR/checks-reads"
    if [ "$n" -lt "$(cat "$FAKE_DIR/empty-reads" 2>/dev/null || echo 2)" ]; then echo '[]'; else echo '[{"name":"ci","state":"SUCCESS","bucket":"pass"}]'; fi ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-61-x $(tip)" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(tip)" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr61.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr61.diff" ;;
  *" pr merge "*)
    echo "$*" > "$FAKE_DIR/merge-args"
    conflicting && { echo "GraphQL: Pull Request has merge conflicts (mergePullRequest)" >&2; exit 1; }
    case " $* " in *" --match-head-commit $(tip) "*) echo "merged #61" ;; *) echo "GraphQL: Head branch was modified" >&2; exit 1 ;; esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# setup <tên> <main_moves: plain|driver|none>: nhánh PR cắt từ main hiện tại, PR nối đuôi m.txt (merge=devkit-matrix) và sửa dòng 1 của s.txt.
# Verify giả (cwd = scratch) đánh dấu verify-ran; nếu MAIN_MOVES_IN_VERIFY=1 thì lượt 1 đẩy một commit nối đuôi m.txt lên origin main.
setup() {
  local name="$1"
  D="$TMP/$name"; mkdir -p "$D"
  export FAKE_DIR="$D" SB_GITHUB_HALT_FILE="$D/halt.json"
  O="$D/origin.git"; R="$D/repo"; WT="$D/repo/.claude/worktrees/review-x"
  git init -q --bare -b main "$O"
  git init -q -b main "$R"
  git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
  git -C "$R" config merge.devkit-matrix.driver 'git merge-file --union -q %A %O %B'
  printf '/.claude/worktrees/\n' > "$R/.gitignore"
  printf 'm.txt merge=devkit-matrix\n' > "$R/.gitattributes"
  mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
  echo m0 > "$R/m.txt"; printf '1\n2\n3\n4\n5\n6\n' > "$R/s.txt"; echo a > "$R/a"
  git -C "$R" add -A; git -C "$R" commit -qm init
  git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
  git -C "$R" branch -q --no-track issue-61-x main
  git -C "$R" worktree add -q "$WT" issue-61-x
  echo m-pr >> "$WT/m.txt"; printf '1-pr\n2\n3\n4\n5\n6\n' > "$WT/s.txt"; echo 61 > "$WT/f61"
  git -C "$WT" add -A; git -C "$WT" commit -qm card61
  git -C "$R" push -q origin issue-61-x
  X=$(git -C "$R" rev-parse issue-61-x); echo "$X" > "$D/x"
  git -C "$R" diff "$X~1" "$X" > "$D/pr61.diff"
  git -C "$R" diff --numstat "$X~1" "$X" | python3 -c 'import json,sys
rows=[l.split("\t") for l in sys.stdin.read().splitlines() if l]
print(json.dumps({"files":[{"path":r[2]} for r in rows],"labels":[],"body":"","additions":sum(int(r[0]) for r in rows),
  "deletions":sum(int(r[1]) for r in rows),"changedFiles":len(rows)}))' > "$D/pr61.meta"
  git clone -q "$O" "$D/merger"
  git -C "$D/merger" config user.email o@example.invalid; git -C "$D/merger" config user.name o
  cat > "$D/verify.sh" <<SH
#!/usr/bin/env bash
touch "$D/verify-ran"
inv=\$(( \$(grep -c '^start ' "$D/vlog" 2>/dev/null || true) + 1 ))
echo "start inv=\$inv head=\$(git rev-parse HEAD)" >> "$D/vlog"
if [ "\$inv" -eq 1 ] && [ "${MAIN_MOVES_IN_VERIFY:-0}" = 1 ]; then
  cd "$D/merger" && git pull -q origin main
  if [ "${MAIN_MOVES_CONFLICT:-0}" = 1 ]; then echo g > g.txt; git add g.txt; else echo m-main >> m.txt; fi
  git commit -qam main-moves && git push -q origin main
fi
exit 0
SH
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":[sys.argv[1]]}))' \
    "bash $D/verify.sh" > "$D/cfg.json"
}
gate() {
  ( cd "$WT" && bash "$GATE" --config "$D/cfg.json" --pr 61 --lock-timeout 60 "$@" ) >>"$D/gate.log" 2>&1; RC=$?
}
why() { grep 'merge-gate' "$D/gate.log" | tail -4 | tr '\n' '|'; }

# 1) P3-1: first mergeable read UNKNOWN; main moved BEFORE the gate (so origin/main is current and never moves again), conflict on a
# file the fake GitHub calls conflicting: the in-lock read must happen anyway ⇒ exit 14 và gh pr merge được gọi 0 lần
setup unknown_then_conflict
touch "$D/unknown-until-verify"
( cd "$D/merger" && git pull -q origin main && echo g > g.txt && git add g.txt && git commit -qam main-first && git push -q origin main )
git -C "$R" fetch -q origin main
gate --expect-head "$X"
[ "$RC" -eq 14 ] && ok "1: UNKNOWN then CONFLICTING in the lock, base unchanged: exit 14" || fail "1: gate exit $RC, want 14: $(why)"
[ ! -e "$D/merge-args" ] && ok "1: gh pr merge never called" || fail "1: gh pr merge called: $(cat "$D/merge-args")"
grep -q CONFLICTING "$D/mergeable-answers" 2>/dev/null && ok "1: CONFLICTING was read in the lock" || fail "1: no in-lock mergeable read"

# 2) P3-2: driver-only conflict appears in the lock (main moves during verify), sync push, checks of the new head register late
MAIN_MOVES_IN_VERIFY=1 setup sync_ci_wait
echo 2 > "$D/empty-reads"
gate --expect-head "$X"
[ "$RC" -eq 0 ] && ok "2: sync in the lock, checks appear late: exit 0" || fail "2: gate exit $RC, want 0: $(why)"
[ "$(cat "$D/checks-reads" 2>/dev/null || echo 0)" -ge 3 ] && ok "2: gate re-read the checks of the new head until they showed up ($(cat "$D/checks-reads") reads)" \
  || fail "2: checks reads $(cat "$D/checks-reads" 2>/dev/null || echo 0), want >= 3"
grep -q 'waiting (at most' "$D/gate.log" && ok "2: log says it waits for check registration" || fail "2: no wait line: $(why)"

# 3) checks never register: exit 4, not merged
MAIN_MOVES_IN_VERIFY=1 setup sync_ci_never
echo 9999 > "$D/empty-reads"
SB_MERGE_SYNC_CI_WAIT_S=3 gate --expect-head "$X"
[ "$RC" -eq 4 ] && [ ! -e "$D/merge-args" ] && ok "3: checks never register: exit 4, no merge" || fail "3: gate exit $RC, merge-args $(cat "$D/merge-args" 2>/dev/null): $(why)"

# 4) R1 (review #1239): UNKNOWN also in the lock after the base moved during verify, then CI pending => drop lock + continue. The base
# must not be pinned on that UNKNOWN: the next lap re-reads mergeable (CONFLICTING: s.txt changed on both sides) => exit 14, no merge call
MAIN_MOVES_IN_VERIFY=1 MAIN_MOVES_CONFLICT=1 setup unknown_in_lock_ci_pending
touch "$D/unknown-until-verify" "$D/unknown-until-ci-pending" "$D/pending-once"
gate --expect-head "$X"
[ "$RC" -eq 14 ] && ok "4: UNKNOWN in the lock, CI pending lap, then CONFLICTING: exit 14" || fail "4: gate exit $RC, want 14: $(why)"
[ ! -e "$D/merge-args" ] && ok "4: gh pr merge never called" || fail "4: gh pr merge called: $(cat "$D/merge-args")"

echo
if [ "$FAILS" -eq 0 ]; then echo "test_merge_gate_unknown_and_sync_ci: PASS"; exit 0; else echo "test_merge_gate_unknown_and_sync_ci: FAIL ($FAILS)"; exit 1; fi
