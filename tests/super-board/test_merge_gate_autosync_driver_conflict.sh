#!/usr/bin/env bash
# 02/11 (PR #916 đụng #911): gần như PR nào cũng nối đuôi .agents/regression_matrix.active.json (merge=devkit-matrix); driver chỉ có
# ở local nên PR merge sau bị GitHub báo CONFLICTING và merge gate thoát 14, mỗi lần một vòng gộp-push-chạy-lại bằng tay
# (test_durations.txt, merge=union, không còn track từ #920; fixture vẫn dùng d.txt merge=union làm ví dụ driver thứ hai). Ngoại lệ hẹp của #570 (merge gate, khối "đồng bộ nhánh PR"). Hành vi mong đợi, mỗi ý có assert:
#   a) CONFLICTING, hai phía chỉ cùng nối đuôi file có driver đặt tên, gộp local sạch ⇒ gate đẩy merge commit (cha 1 = head đã review,
#      cha 2 = base) lên nhánh PR ở remote (fast-forward), verify chạy trên đúng commit đó, merge với --match-head-commit = head mới, exit 0
#   b) có file hai phía cùng sửa mà không có driver đặt tên ⇒ exit 14 như cũ, không đẩy gì, không verify
#   c) nhánh PR trên remote đã dời trước lúc đẩy (GitHub còn báo head cũ) ⇒ exit 14, remote giữ commit của người kia (không ghi đè)
#   c2) như c nhưng GitHub cũng thấy head mới ⇒ exit 14, không đẩy
#   d) --dry-run ⇒ exit 14 như cũ, không đẩy gì
#   e) verify đỏ sau khi đã đẩy (exit 11), lượt sau vẫn --expect-head <head cũ> ⇒ head mới được nhận (biên nhận của gate), merge exit 0
#   f) như e nhưng có người đẩy thêm commit lên trên merge commit của gate ⇒ lượt sau exit 6 (head moved) như cũ
# gh giả đọc head và mergeable từ remote trần của fixture (CONFLICTING khi main chưa là tổ tiên của nhánh). Tương thích bash 3.2.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-autosync-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_MERGEABLE_POLL_S=0
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
O="$FAKE_DIR/origin.git"
tip() { git -C "$O" rev-parse refs/heads/issue-61-x 2>/dev/null || echo 0000000000000000000000000000000000000000; }
conflicting() { ! git -C "$O" merge-base --is-ancestor refs/heads/main "$(tip)" 2>/dev/null; }
case " $* " in
  *" pr view "*"--json mergeable"*)
    echo x >> "$FAKE_DIR/mergeable-calls"
    # Ca c / c2: lần đọc đầu, một phiên khác đẩy commit lên nhánh PR.
    if [ -f "$FAKE_DIR/race.sh" ] && [ ! -e "$FAKE_DIR/raced" ]; then : > "$FAKE_DIR/raced"; bash "$FAKE_DIR/race.sh" >/dev/null 2>&1; fi
    if conflicting; then echo CONFLICTING; else echo MERGEABLE; fi ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-61-x $(cat "$FAKE_DIR/gh.head" 2>/dev/null || tip)" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/gh.head" 2>/dev/null || tip)" ;;
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

# setup <tên>: fixture mới. Nhánh PR và main cùng nối đuôi m.txt (merge=devkit-matrix, driver cấu hình trong repo) và d.txt (merge=union).
# SHARED_PLAIN=1: hai phía còn cùng sửa s.txt (không driver), ở hai dòng khác nhau (gộp local vẫn sạch).
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
  printf 'm.txt merge=devkit-matrix\nd.txt merge=union\n' > "$R/.gitattributes"
  mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
  echo m0 > "$R/m.txt"; echo d0 > "$R/d.txt"; printf '1\n2\n3\n4\n5\n6\n' > "$R/s.txt"; echo a > "$R/a"
  git -C "$R" add -A; git -C "$R" commit -qm init
  git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
  git -C "$R" branch -q --no-track issue-61-x main
  git -C "$R" worktree add -q "$WT" issue-61-x
  echo m-pr >> "$WT/m.txt"; echo d-pr >> "$WT/d.txt"; echo 61 > "$WT/f61"
  [ "${SHARED_PLAIN:-0}" = 1 ] && printf '1-pr\n2\n3\n4\n5\n6\n' > "$WT/s.txt"
  # GATTR=1: the PR itself edits .gitattributes (could swap the named driver of a shared file)
  [ "${GATTR:-0}" = 1 ] && printf 'z.txt merge=union\n' >> "$WT/.gitattributes"
  # BIGLIST=1: ~120 KB of changed file names, so `git diff --name-only | grep -q` would SIGPIPE git before it finishes writing
  if [ "${BIGLIST:-0}" = 1 ]; then
    mkdir -p "$WT/big"
    for i in $(seq 1 1000); do : > "$WT/big/$(printf 'f%04d-%0100d' "$i" 0)"; done
  fi
  git -C "$WT" add -A; git -C "$WT" commit -qm card61
  git -C "$R" push -q origin issue-61-x
  X=$(git -C "$R" rev-parse issue-61-x)
  git -C "$R" diff "$X~1" "$X" > "$D/pr61.diff"
  # metadata khớp đúng diff (github-read đối chiếu số file và số dòng thêm/bớt)
  git -C "$R" diff --numstat "$X~1" "$X" | python3 -c 'import json,sys
rows=[l.split("\t") for l in sys.stdin.read().splitlines() if l]
print(json.dumps({"files":[{"path":r[2]} for r in rows],"labels":[],"body":"","additions":sum(int(r[0]) for r in rows),
  "deletions":sum(int(r[1]) for r in rows),"changedFiles":len(rows)}))' > "$D/pr61.meta"
  echo m-main >> "$R/m.txt"; echo d-main >> "$R/d.txt"
  [ "${SHARED_PLAIN:-0}" = 1 ] && printf '1\n2\n3\n4\n5\n6-main\n' > "$R/s.txt"
  git -C "$R" commit -qam main-moves; git -C "$R" push -q origin main
  B=$(git -C "$R" rev-parse main)
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":[sys.argv[1]]}))' \
    "if [ -e $D/fail-once ]; then rm -f $D/fail-once; exit 1; fi; echo ran > $D/verify-ran; git rev-parse HEAD > $D/verify-head" > "$D/cfg.json"
}
# gate [--expect-head <sha>] [cờ khác…]: chạy gate từ worktree reviewer; RC, ORIGIN_HEAD.
gate() {
  ( cd "$WT" && bash "$GATE" --config "$D/cfg.json" --pr 61 "$@" ) >>"$D/gate.log" 2>&1; RC=$?
  ORIGIN_HEAD=$(git -C "$O" rev-parse issue-61-x)
}
# race_script <ghim head GitHub 0|1>: phiên khác đẩy commit Z lên nhánh PR ở lần đọc mergeable đầu tiên.
race_script() {
  git clone -q "$O" "$D/racer"
  git -C "$D/racer" checkout -q issue-61-x
  printf 'cd %s && echo race >> f61 && git -c user.email=r@example.invalid -c user.name=r commit -qam race && git push -q origin issue-61-x\n' "$D/racer" > "$D/race.sh"
  [ "$1" = 1 ] && echo "$X" > "$D/gh.head"
  return 0
}
scratch_left() { ls -d "$D"/repo/.claude/worktrees/.merge-scratch-* >/dev/null 2>&1; }

# a) chỉ file có driver đặt tên: đẩy merge commit, verify trên nó, merge với head mới
setup sync_ok; gate --expect-head "$X"
N="$ORIGIN_HEAD"
[ "$RC" -eq 0 ] && ok "a: driver-only conflict: gate exit 0" || fail "a: gate exit $RC, want 0: $(grep 'merge-gate' "$D/gate.log" | tail -4)"
[ "$(git -C "$O" rev-list --parents -n 1 "$N")" = "$N $X $B" ] \
  && ok "a: PR branch on origin is one merge commit on top of the reviewed head (parents: head ${X:0:8}, base ${B:0:8})" \
  || fail "a: origin issue-61-x ${N:0:8} parents: $(git -C "$O" rev-list --parents -n 1 "$N")"
[ "$(cat "$D/verify-head" 2>/dev/null)" = "$N" ] && ok "a: verify ran on the pushed merge commit" \
  || fail "a: verify head $(cat "$D/verify-head" 2>/dev/null || echo none), want ${N:0:8}"
grep -q -- "--match-head-commit $N" "$D/merge-args" 2>/dev/null && ok "a: merged with --match-head-commit = the new head" \
  || fail "a: merge args: $(cat "$D/merge-args" 2>/dev/null || echo 'gh pr merge not called')"
grep -q "pushed issue-61-x: $X -> $N" "$D/gate.log" && ok "a: log says what was pushed" || fail "a: no 'pushed' line in the log"
[ "$(cat "$R/.git/super-board/approved-merge-heads/$N" 2>/dev/null)" = "$X" ] && ok "a: receipt approved-merge-heads/<new> = reviewed head" \
  || fail "a: receipt missing or wrong"
scratch_left && fail "a: scratch dir left behind" || ok "a: no .merge-scratch-* left behind"

# b) file hai phía cùng sửa không có driver: exit 14 như cũ
SHARED_PLAIN=1 setup shared_plain; gate --expect-head "$X"
[ "$RC" -eq 14 ] && ok "b: shared file without a named driver: exit 14" || fail "b: gate exit $RC, want 14: $(grep 'merge-gate' "$D/gate.log" | tail -3)"
[ "$ORIGIN_HEAD" = "$X" ] && ok "b: nothing pushed" || fail "b: PR branch moved ${X:0:8} -> ${ORIGIN_HEAD:0:8}"
[ ! -e "$D/verify-ran" ] && [ ! -e "$D/merge-args" ] && ok "b: no verify, no merge" || fail "b: verify or merge ran"
grep -q "git merge --no-edit origin/main" "$D/gate.log" && ok "b: today's fix message" || fail "b: fix message missing"
grep -q 's.txt (changed on both sides) has no named merge driver' "$D/gate.log" && ok "b: log names the file without a driver" \
  || fail "b: reason line missing: $(grep 'not syncing' "$D/gate.log")"

# c) remote đã dời trước lúc đẩy, GitHub còn báo head cũ: exit 14, không ghi đè
setup race_stale_github; race_script 1; gate --expect-head "$X"
Z=$(git -C "$D/racer" rev-parse HEAD)
[ "$RC" -eq 14 ] && ok "c: remote branch moved before the push: exit 14" || fail "c: gate exit $RC, want 14: $(grep 'merge-gate' "$D/gate.log" | tail -3)"
[ "$ORIGIN_HEAD" = "$Z" ] && ok "c: the other push stays on origin (nothing force-pushed)" || fail "c: origin ${ORIGIN_HEAD:0:8}, want the racer ${Z:0:8}"
[ ! -e "$D/verify-ran" ] && [ ! -e "$D/merge-args" ] && ok "c: no verify, no merge" || fail "c: verify or merge ran"

# c2) GitHub cũng thấy head mới: exit 14, không đẩy
setup race_github_moved; race_script 0; gate --expect-head "$X"
Z=$(git -C "$D/racer" rev-parse HEAD)
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$Z" ] && [ ! -e "$D/verify-ran" ] && ok "c2: GitHub head moved before the push: exit 14, nothing pushed" \
  || fail "c2: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (racer ${Z:0:8})"

# d) --dry-run: exit 14 như cũ, không đẩy
setup dry; gate --expect-head "$X" --dry-run
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ ! -e "$D/verify-ran" ] && ok "d: --dry-run: exit 14, nothing pushed" \
  || fail "d: gate exit $RC, origin ${ORIGIN_HEAD:0:8}, want 14 and ${X:0:8}"

# e) verify đỏ sau khi đẩy; lượt sau --expect-head <head cũ> nhận head mới của gate
setup rerun_ok; : > "$D/fail-once"; gate --expect-head "$X"; RC1=$RC; N="$ORIGIN_HEAD"
gate --expect-head "$X"
[ "$RC1" -eq 11 ] && [ "$N" != "$X" ] && [ "$RC" -eq 0 ] && grep -q -- "--match-head-commit $N" "$D/merge-args" 2>/dev/null \
  && ok "e: red verify after the push (11), re-run with the reviewed --expect-head merges the gate's own head (0)" \
  || fail "e: first exit $RC1, second exit $RC, origin ${N:0:8}: $(grep 'merge-gate' "$D/gate.log" | tail -3)"

# f) như e nhưng có commit người khác chồng lên: head moved, exit 6
setup rerun_moved; : > "$D/fail-once"; gate --expect-head "$X"; RC1=$RC
git clone -q "$O" "$D/other"; git -C "$D/other" checkout -q issue-61-x
echo extra >> "$D/other/f61"; git -C "$D/other" -c user.email=o@example.invalid -c user.name=o commit -qam extra; git -C "$D/other" push -q origin issue-61-x
gate --expect-head "$X"
[ "$RC1" -eq 11 ] && [ "$RC" -eq 6 ] && [ ! -e "$D/merge-args" ] && ok "f: a commit pushed on top of the gate's merge: exit 6 (head moved)" \
  || fail "f: first exit $RC1, second exit $RC, want 11 then 6"

# g) the PR edits .gitattributes: its own attributes are never trusted to name the driver ⇒ exit 14, nothing pushed
GATTR=1 setup gattr; gate --expect-head "$X"
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ ! -e "$D/verify-ran" ] && ok "g: PR changes .gitattributes: exit 14, nothing pushed, no verify" \
  || fail "g: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (want ${X:0:8}): $(grep 'merge-gate' "$D/gate.log" | tail -3)"
grep -q 'the PR changes a .gitattributes file' "$D/gate.log" && ok "g: log names the reason" || fail "g: reason line missing"

# g2) same with a huge changed-file list (pipefail + grep -q early exit must not turn the guard fail-open)
GATTR=1 BIGLIST=1 setup gattr_big; gate --expect-head "$X"
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ ! -e "$D/verify-ran" ] && ok "g2: .gitattributes edit among 1000 changed files: exit 14, nothing pushed" \
  || fail "g2: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (want ${X:0:8}): $(grep 'merge-gate' "$D/gate.log" | tail -3)"

# h) --preflight on a CONFLICTING PR: exit 14 as before, nothing pushed (the train must never sync a branch)
setup preflight; gate --expect-head "$X" --preflight
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && ok "h: --preflight: exit 14, nothing pushed" || fail "h: gate exit $RC, origin ${ORIGIN_HEAD:0:8}"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_autosync_driver_conflict: PASS"; exit 0; } || { echo "test_merge_gate_autosync_driver_conflict: FAIL ($FAILS)"; exit 1; }
