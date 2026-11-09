#!/usr/bin/env bash
# #1012 mục (b) (05/11 08:24–09:10): #1009 (test sửa) giữ khoá merge suốt verify tới lúc merge; #1007 và #1004 verify lạc quan ngoài
# khoá trên base cũ CÙNG lúc ⇒ #1009 merge thì kết quả của họ cũ ⇒ verify lại. Luật mới: trước verify ngoài khoá, khoá merge đang bị một
# gate sống giữ (pid sống, mốc chưa cũ) thì chờ (có hạn: SB_MERGE_WAIT_HOLDER_S, mặc định phần còn lại của --lock-timeout; poll 5 s như
# acquire) tới khi nó thả, fetch base mới rồi verify một lần. Người giữ chết / khoá cũ ⇒ không chờ. Hết hạn ⇒ hành vi cũ.
#   1. gate A (SB_MERGE_OPTIMISTIC=0: giữ khoá suốt verify, verify chặn tới khi thả) giữ khoá; gate B (lạc quan) khởi động ⇒ B không
#      verify trước khi A thả khoá; A merge (base dời) ⇒ B verify ĐÚNG MỘT lần, trên cây có file của A; cả hai exit 0
#                                                                                — ĐỎ trên gốc (B verify 2 lần, lần 1 trước khi A thả)
#   2. khoá do pid đã chết để lại ⇒ B không chờ, verify một lần, merge
#   3. A giữ khoá mãi, SB_MERGE_WAIT_HOLDER_S=2 ⇒ B chờ có hạn rồi verify như cũ (ngoài khoá), không bỏ verify
# Verify giả (cwd = scratch) đếm lượt chạy và ghi PR đang giữ khoá. gh giả: `pr merge` squash-push THẬT vào origin. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
unset SB_MERGE_OPTIMISTIC SB_MERGE_WAIT_HOLDER_S SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wait-holder-test.XXXXXX")"
trap 'touch "$TMP"/release* 2>/dev/null; kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review"; B="$TMP/builder"; M="$TMP/merger"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
echo base > "$R/base.txt"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" fetch -q origin
git -C "$R" worktree add -q --detach "$WT" main
git clone -q "$O" "$B"; git -C "$B" config user.email t@example.invalid; git -C "$B" config user.name t
git clone -q "$O" "$M"; git -C "$M" config user.email t@example.invalid; git -C "$M" config user.name t
LOCK="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/super-board/merge.lock"

# PR n: nhánh issue-n-x từ main lúc tạo, thêm file f<n>.
mkpr() {
  local n="$1" h
  git -C "$B" fetch -q origin; git -C "$B" checkout -q -B "issue-$n-x" origin/main
  echo "pr$n" > "$B/f$n"; git -C "$B" add "f$n"; git -C "$B" commit -qm "card$n"
  git -C "$B" push -q origin "issue-$n-x"
  h=$(git -C "$B" rev-parse HEAD)
  git -C "$B" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"--json mergeable"*) echo MERGEABLE ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    if [ -s "$FAKE_DIR/merged$n" ]; then printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/merged$n")" "$head"
    else printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"; fi ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json body"*) jq -r '.body // ""' "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json title"*) echo "fix: t" ;;
  *" pr view "*"mergeCommit"*) [ -s "$FAKE_DIR/merged$n" ] && cat "$FAKE_DIR/merged$n" || echo "" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr comment "*) : ;;
  *" pr merge "*)
    ( cd "$FAKE_DIR/merger" && git fetch -q origin && git checkout -q -B main origin/main \
        && git merge -q --squash "origin/issue-$n-x" && git commit -qm "squash #$n" && git push -q origin main ) >&2 || exit 1
    git -C "$FAKE_DIR/merger" rev-parse HEAD > "$FAKE_DIR/merged$n"
    echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_HELD=1
export DEVKIT_SLOT_LOAD_FILE="$TMP/slot-load"; echo 1 > "$DEVKIT_SLOT_LOAD_FILE"

# verify.sh <n>: lệnh verify giả. Ghi vlog: lượt thứ mấy, có file f<k> nào của PR khác, PR đang giữ khoá; block<n> thì chờ release<n>.
cat > "$TMP/verify.sh" <<SH
#!/usr/bin/env bash
n="\$1"; T="$TMP"
inv=\$(( \$(grep -c "^start \$n " "\$T/vlog" 2>/dev/null || true) + 1 ))
lockpr=none; [ -r "$LOCK/pr" ] && lockpr=\$(cat "$LOCK/pr")
echo "start \$n inv=\$inv files=\$(ls f* 2>/dev/null | tr '\n' ',') lockpr=\$lockpr" >> "\$T/vlog"
if [ -f "\$T/block\$n" ]; then w=0; while [ ! -e "\$T/release\$n" ] && [ "\$w" -lt 1200 ]; do sleep 0.1; w=\$((w + 1)); done; fi
echo "end \$n inv=\$inv" >> "\$T/vlog"
exit 0
SH

gate() {  # gate <n> [env …] — chạy từ WT; log $TMP/gate<n>.log, mã thoát vào $TMP/rc<n>
  local n="$1" cfg="$TMP/cfg$1.json"; shift
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":[sys.argv[1]]}))' \
    "bash $TMP/verify.sh $n" > "$cfg"
  ( cd "$WT" && env SB_GITHUB_HALT_FILE="$TMP/halt$n.json" "$@" bash "$GATE" --config "$cfg" --pr "$n" \
      --expect-head "$(cat "$TMP/pr$n.head")" --lock-timeout 120 ) >"$TMP/gate$n.log" 2>&1
  echo $? > "$TMP/rc$n"
}
rc() { cat "$TMP/rc$1" 2>/dev/null || echo none; }
wait_for() { local s="$1" n=0; shift; while ! "$@"; do [ "$n" -ge $((s * 10)) ] && return 1; sleep 0.1; n=$((n + 1)); done; }
vlog_has() { grep -q "$1" "$TMP/vlog" 2>/dev/null; }
log_has() { grep -q "$2" "$TMP/gate$1.log" 2>/dev/null; }
starts() { grep -c "^start $1 " "$TMP/vlog" 2>/dev/null || true; }
why() { grep 'merge-gate' "$TMP/gate$1.log" | tail -5 | tr '\n' '|'; }

# ── 1. A giữ khoá suốt verify; B khởi động ⇒ B chờ A, rồi verify đúng một lần trên base có f1 ─────────────────────
mkpr 1; mkpr 2
: > "$TMP/block1"
gate 1 SB_MERGE_OPTIMISTIC=0 & G1=$!
wait_for 60 vlog_has '^start 1 inv=1' || fail "1: setup: gate A never started its verify: $(why 1)"
gate 2 & G2=$!
# gate B đọc GitHub rồi tới chỗ verify trong vài giây: 10 s mà chưa verify (và log nói đang chờ người giữ khoá) là đang chờ A.
if wait_for 10 vlog_has '^start 2 '; then
  fail "1: gate B started verifying while gate A held the merge lock: $(grep '^start 2 ' "$TMP/vlog" | head -1)"
else
  ok "1: gate B does not verify while gate A holds the merge lock"
fi
log_has 2 'waiting for the merge lock holder' && ok "1: gate B says it waits for the lock holder (pid, PR, phase)" \
  || fail "1: no 'waiting for the merge lock holder' line: $(why 2)"
touch "$TMP/release1"
wait "$G1" 2>/dev/null; wait "$G2" 2>/dev/null
[ "$(rc 1)" = 0 ] && [ "$(rc 2)" = 0 ] && ok "1: both gates merge (exit 0)" || fail "1: rc A=$(rc 1) rc B=$(rc 2): $(why 1) / $(why 2)"
[ "$(starts 2)" -eq 1 ] && ok "1: gate B verified exactly once" || fail "1: gate B verified $(starts 2) times: $(grep ' 2 inv=' "$TMP/vlog" | tr '\n' '|')"
grep -q '^start 2 inv=1 files=f1,f2, ' "$TMP/vlog" && ok "1: … on the base A merged (the tree has f1)" \
  || fail "1: gate B's first verify did not run on A's merged base: $(grep '^start 2 ' "$TMP/vlog" | head -1)"

# ── 2. khoá do pid đã chết để lại: không chờ ─────────────────────────────────────────────────────────────────
mkpr 3
sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null
mkdir -p "$LOCK"; date +%s > "$LOCK/at"; echo "$DEAD" > "$LOCK/pid"; echo "$DEAD" > "$LOCK/pgid"; hostname > "$LOCK/host"; echo 9 > "$LOCK/pr"
t0=$(date +%s); gate 3; t1=$(date +%s)
[ "$(rc 3)" = 0 ] && [ "$(starts 3)" -eq 1 ] && ! log_has 3 'waiting for the merge lock holder' \
  && ok "2: dead holder's lock: no wait, one verify, merged ($((t1 - t0)) s)" \
  || fail "2: rc=$(rc 3) verifies=$(starts 3): $(why 3)"

# ── 3. A giữ khoá mãi, SB_MERGE_WAIT_HOLDER_S=2: chờ có hạn rồi verify như cũ ───────────────────────────────────
mkpr 4; mkpr 5
: > "$TMP/block4"
gate 4 SB_MERGE_OPTIMISTIC=0 & G4=$!
wait_for 60 vlog_has '^start 4 inv=1' || fail "3: setup: gate A never started its verify: $(why 4)"
gate 5 SB_MERGE_WAIT_HOLDER_S=2 & G5=$!
if wait_for 30 vlog_has '^start 5 inv=1'; then
  ok "3: wait capped at SB_MERGE_WAIT_HOLDER_S=2: gate B verifies while A still holds the lock (old behaviour)"
else
  fail "3: gate B never verified within 30 s with a 2 s wait cap: $(why 5)"
fi
log_has 5 'still holds the merge lock after' && ok "3: log says the wait ran out" || fail "3: no cap line: $(why 5)"
touch "$TMP/release4"
wait "$G4" 2>/dev/null; wait "$G5" 2>/dev/null
[ "$(rc 4)" = 0 ] && [ "$(rc 5)" = 0 ] && ok "3: both gates merge (exit 0)" || fail "3: rc A=$(rc 4) rc B=$(rc 5): $(why 4) / $(why 5)"

echo "---"; [ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
