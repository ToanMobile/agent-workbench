#!/usr/bin/env bash
# #1012 (05/11, PR #1007): merge gate verify xanh 09:05→10:07, rồi trong khoá ngắn GitHub báo CONFLICTING (main dời vì #1009 nối đuôi
# ma trận, merge=devkit-matrix) ⇒ exit 14, mất 60 phút verify. AUTOSYNC (driver_only_overlap / sync_candidate) chỉ chạy ở lần đọc
# mergeable ĐẦU (trước verify); mergeable_or_14 trong khoá thoát 14 thẳng. Hành vi mong đợi, mỗi ý có assert:
#   a) lần đọc đầu MERGEABLE (main là tổ tiên của nhánh PR), main dời trong lúc verify (chỉ nối đuôi m.txt, merge=devkit-matrix) ⇒ trong
#      khoá GitHub báo CONFLICTING ⇒ gate gộp base mới vào scratch, verify lại TRONG khoá, đẩy merge commit (cha 1 = head đã review,
#      cha 2 = base mới) lên nhánh PR (fast-forward), merge với --match-head-commit = head mới, exit 0      — ĐỎ trên gốc (exit 14)
#   b) như a nhưng main còn sửa s.txt (PR cũng sửa, không có driver) ⇒ exit 14 như cũ, không đẩy gì, không verify lần hai
#   c) như a nhưng --dry-run ⇒ exit 14 như cũ (dry run không đồng bộ nhánh), không đẩy gì
#   d) như a nhưng main dời thêm lần nữa giữa fetch_base_now và fetch của sync_candidate (grok REVISE 05/11) ⇒ gộp, verify và đẩy theo
#      đúng tip sync_candidate đã kiểm driver: exit 0, cha 2 = tip mới nhất                                   — ĐỎ trên 008caf68 (exit 4)
# gh giả đọc head và mergeable từ remote trần (CONFLICTING khi main chưa là tổ tiên của nhánh). Tương thích bash 3.2.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-inlock-sync-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_MERGEABLE_POLL_S=0
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX SB_MERGE_OPTIMISTIC SB_MERGE_WAIT_HOLDER_S

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
O="$FAKE_DIR/origin.git"
tip() { git -C "$O" rev-parse refs/heads/issue-61-x 2>/dev/null || echo 0000000000000000000000000000000000000000; }
conflicting() { ! git -C "$O" merge-base --is-ancestor refs/heads/main "$(tip)" 2>/dev/null; }
case " $* " in
  *" pr view "*"--json mergeable"*)
    # ca d: main dời thêm lần nữa ngay lúc gate hỏi mergeable trong khoá (sau fetch_base_now, trước fetch của sync_candidate)
    if conflicting && [ -e "$FAKE_DIR/race" ] && [ ! -e "$FAKE_DIR/raced" ]; then
      touch "$FAKE_DIR/raced"
      ( cd "$FAKE_DIR/merger" && git pull -q origin main && echo m-main2 >> m.txt && git commit -qam main-moves-again && git push -q origin main )
    fi
    if conflicting; then echo CONFLICTING; else echo MERGEABLE; fi | tee -a "$FAKE_DIR/mergeable-answers" ;;
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
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH"

# setup <tên>: nhánh PR cắt từ main hiện tại (lần đọc đầu MERGEABLE), PR nối đuôi m.txt (merge=devkit-matrix) và sửa dòng 1 của s.txt.
# Verify giả (cwd = scratch) ghi vlog: lượt thứ mấy, HEAD, cây, PR đang giữ khoá merge; lượt 1 đẩy một commit lên origin main (một PR
# khác vừa merge): nối đuôi m.txt; SHARED_PLAIN=1 thì còn sửa dòng 6 của s.txt (không driver: GitHub xung đột thật).
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
  X=$(git -C "$R" rev-parse issue-61-x)
  git -C "$R" diff "$X~1" "$X" > "$D/pr61.diff"
  git -C "$R" diff --numstat "$X~1" "$X" | python3 -c 'import json,sys
rows=[l.split("\t") for l in sys.stdin.read().splitlines() if l]
print(json.dumps({"files":[{"path":r[2]} for r in rows],"labels":[],"body":"","additions":sum(int(r[0]) for r in rows),
  "deletions":sum(int(r[1]) for r in rows),"changedFiles":len(rows)}))' > "$D/pr61.meta"
  git clone -q "$O" "$D/merger"
  git -C "$D/merger" config user.email o@example.invalid; git -C "$D/merger" config user.name o
  cat > "$D/verify.sh" <<SH
#!/usr/bin/env bash
inv=\$(( \$(grep -c '^start ' "$D/vlog" 2>/dev/null || true) + 1 ))
lockpr=none; [ -r "$R/.git/super-board/merge.lock/pr" ] && lockpr=\$(cat "$R/.git/super-board/merge.lock/pr")
echo "start inv=\$inv head=\$(git rev-parse HEAD) lockpr=\$lockpr" >> "$D/vlog"
if [ "\$inv" -eq 1 ]; then
  cd "$D/merger" && git pull -q origin main && echo m-main >> m.txt
  [ "${SHARED_PLAIN:-0}" = 1 ] && printf '1\n2\n3\n4\n5\n6-main\n' > s.txt
  git commit -qam main-moves && git push -q origin main
fi
exit 0
SH
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":[sys.argv[1]]}))' \
    "bash $D/verify.sh" > "$D/cfg.json"
}
gate() {
  ( cd "$WT" && bash "$GATE" --config "$D/cfg.json" --pr 61 --lock-timeout 60 "$@" ) >>"$D/gate.log" 2>&1; RC=$?
  ORIGIN_HEAD=$(git -C "$O" rev-parse issue-61-x)
  B2=$(git -C "$O" rev-parse main)
}
starts() { grep -c '^start ' "$D/vlog" 2>/dev/null || true; }
why() { grep 'merge-gate' "$D/gate.log" | tail -4 | tr '\n' '|'; }

# a) driver-only conflict that appears only inside the lock: sync + verify again in the lock + merge
setup inlock_ok; gate --expect-head "$X"
N="$ORIGIN_HEAD"
[ "$(head -1 "$D/mergeable-answers" 2>/dev/null)" = MERGEABLE ] && grep -q CONFLICTING "$D/mergeable-answers" \
  && ok "a: fixture: first mergeable read MERGEABLE, CONFLICTING inside the lock" \
  || fail "a: fixture: mergeable answers $(tr '\n' ' ' < "$D/mergeable-answers" 2>/dev/null)"
[ "$RC" -eq 0 ] && ok "a: CONFLICTING only on a named-driver file inside the lock: exit 0 (not 14)" || fail "a: gate exit $RC, want 0: $(why)"
[ "$(git -C "$O" rev-list --parents -n 1 "$N")" = "$N $X $B2" ] \
  && ok "a: PR branch on origin is one merge commit on the reviewed head (parents ${X:0:8} + new base ${B2:0:8})" \
  || fail "a: origin issue-61-x ${N:0:8} parents: $(git -C "$O" rev-list --parents -n 1 "$N") (want X ${X:0:8} + base ${B2:0:8})"
[ "$(starts)" -eq 2 ] && grep -q "^start inv=2 head=$N lockpr=61" "$D/vlog" \
  && ok "a: verified again once, inside the merge lock, on the merge commit that was pushed" \
  || fail "a: verifies: $(tr '\n' '|' < "$D/vlog" 2>/dev/null)"
grep -q -- "--match-head-commit $N" "$D/merge-args" 2>/dev/null && ok "a: merged with --match-head-commit = the pushed head" \
  || fail "a: merge args: $(cat "$D/merge-args" 2>/dev/null || echo 'gh pr merge not called')"
[ "$(cat "$R/.git/super-board/approved-merge-heads/$N" 2>/dev/null)" = "$X" ] && ok "a: receipt approved-merge-heads/<new> = reviewed head" \
  || fail "a: receipt approved-merge-heads/${N:0:8} missing or wrong"
ls -d "$R"/.claude/worktrees/.merge-scratch-* >/dev/null 2>&1 && fail "a: scratch left behind" || ok "a: no .merge-scratch-* left behind"

# b) a real conflict inside the lock (s.txt has no named driver): exit 14 as before
SHARED_PLAIN=1 setup inlock_plain; gate --expect-head "$X"
[ "$RC" -eq 14 ] && ok "b: shared file without a named driver inside the lock: exit 14" || fail "b: gate exit $RC, want 14: $(why)"
[ "$ORIGIN_HEAD" = "$X" ] && ok "b: nothing pushed" || fail "b: PR branch moved ${X:0:8} -> ${ORIGIN_HEAD:0:8}"
[ "$(starts)" -eq 1 ] && [ ! -e "$D/merge-args" ] && ok "b: no second verify, no merge" || fail "b: verifies $(starts), merge-args $(cat "$D/merge-args" 2>/dev/null)"
grep -q 's.txt (changed on both sides) has no named merge driver' "$D/gate.log" && ok "b: log names the file without a driver" \
  || fail "b: reason line missing: $(why)"

# c) --dry-run never syncs a branch: exit 14 as before
setup inlock_dry; gate --expect-head "$X" --dry-run
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ "$(starts)" -eq 1 ] && ok "c: --dry-run: exit 14, nothing pushed, one verify" \
  || fail "c: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (want ${X:0:8}), verifies $(starts): $(why)"

# d) main moves again between fetch_base_now and sync_candidate's own fetch: sync onto the tip whose drivers were checked
setup inlock_race; touch "$D/race"; gate --expect-head "$X"
N="$ORIGIN_HEAD"
[ -e "$D/raced" ] && ok "d: fixture: main moved again at the in-lock mergeable read" || fail "d: fixture: race not triggered"
[ "$RC" -eq 0 ] && ok "d: exit 0 (not 4)" || fail "d: gate exit $RC, want 0: $(why)"
[ "$(git -C "$O" rev-list --parents -n 1 "$N")" = "$N $X $B2" ] \
  && ok "d: pushed merge commit = reviewed head + the newest base ${B2:0:8}" \
  || fail "d: origin issue-61-x ${N:0:8} parents: $(git -C "$O" rev-list --parents -n 1 "$N") (want X ${X:0:8} + base ${B2:0:8})"
[ "$(starts)" -eq 2 ] && grep -q "^start inv=2 head=$N lockpr=61" "$D/vlog" \
  && ok "d: verified again once, inside the lock, on the pushed merge commit" || fail "d: verifies: $(tr '\n' '|' < "$D/vlog" 2>/dev/null)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_conflicting_in_lock_sync: PASS"; exit 0; } || { echo "test_merge_gate_conflicting_in_lock_sync: FAIL ($FAILS)"; exit 1; }
