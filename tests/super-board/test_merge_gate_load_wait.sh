#!/usr/bin/env bash
# 19/10: verify của merge gate (post-fix-gate --full) chạy ngay cả khi máy tải ~60 (5 board cùng build): REG-DK-ALL-01 của PR #87
# (thẻ #12) chọn 127 test và quá 900 s, thẻ quay về Ready mãi. Luật: trước khi giữ khoá merge, gate chờ tải 1 phút xuống dưới
# SB_MERGE_LOAD_MAX, có giới hạn SB_MERGE_LOAD_WAIT_S; hết giờ vẫn verify như cũ (không bỏ bước nào). Không giữ khoá lúc chờ.
# SB_MERGE_LOAD_FILE là móc test: đọc tải từ file thay cho os.getloadavg().
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-loadwait-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
# Slot nặng riêng của test: slot toàn máy có thể đang bị merge gate thật giữ (chờ tới 3600 s).
export SB_HEAVY_SLOT_DIR="$TMP/slots"
# Verify đỏ (exit 3) để gate không merge; dòng đầu ghi giây bắt đầu verify.
STARTED="$TMP/verify.started"
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["date +%%s > %s; echo \\"KẾT LUẬN: FAIL\\"; exit 3"]}' "$STARTED" > "$CFG"
LOCK="$WT/.claude/super-board/inflight/merge.lock"
LOADF="$TMP/load"
export SB_MERGE_LOAD_FILE="$LOADF" SB_MERGE_LOAD_MAX=10 SB_MERGE_LOAD_POLL_S=1
gate() { ( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ); }

# Ca 1: tải 99 suốt, chờ tối đa 3 s → có dòng chờ, không giữ khoá lúc chờ, hết giờ vẫn verify (exit 11), verify bắt đầu sau ≥ 3 s.
echo 99 > "$LOADF"; rm -f "$STARTED"
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=3 gate >"$TMP/gate1.log" 2>&1 &
gp=$!
sleep 1.5
[ -d "$LOCK" ] && fail "merge lock is held while waiting for the load to drop" || ok "no merge lock held while waiting"
wait "$gp"; rc=$?
grep -q "waiting for load" "$TMP/gate1.log" \
  && ok "high load: the gate says it waits" || fail "no wait message at load 99: $(grep merge-gate "$TMP/gate1.log" | head -3)"
grep -q "verifying anyway" "$TMP/gate1.log" \
  && ok "wait capped: the gate verifies anyway" || fail "no capped-wait message: $(grep merge-gate "$TMP/gate1.log" | head -4)"
if [ -f "$STARTED" ] && [ $(( $(cat "$STARTED") - t0 )) -ge 3 ]; then ok "verify started after the 3 s wait"
else fail "verify did not wait (started=$(cat "$STARTED" 2>/dev/null || echo none), t0=$t0)"; fi
[ "$rc" -eq 11 ] && ok "verify still ran and decided (exit 11)" || fail "gate exit $rc (want 11)"

# Ca 2: tải 99 rồi xuống 2 sau ~2 s, chờ tối đa 30 s → verify bắt đầu khi tải xuống, không phải hết 30 s.
echo 99 > "$LOADF"; rm -f "$STARTED"
( sleep 2; echo 2 > "$LOADF" ) &
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=30 gate >"$TMP/gate2.log" 2>&1; rc=$?
d=$(( $(cat "$STARTED" 2>/dev/null || echo 0) - t0 ))
[ "$d" -ge 2 ] && [ "$d" -le 10 ] && ok "verify started once the load dropped (${d}s)" || fail "verify start ${d}s after the gate (want 2..10)"
grep -q "verifying anyway" "$TMP/gate2.log" && fail "load dropped but the gate says it gave up waiting" || ok "no capped-wait message when the load dropped"

# Ca 3: tải thấp → không chờ.
echo 3 > "$LOADF"; rm -f "$STARTED"
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=30 gate >"$TMP/gate3.log" 2>&1
grep -q "waiting for load" "$TMP/gate3.log" && fail "low load: the gate still waits" || ok "low load: no wait"
d=$(( $(cat "$STARTED" 2>/dev/null || echo 99) - t0 ))
[ "$d" -le 2 ] && ok "low load: verify started at once (${d}s)" || fail "low load: verify started after ${d}s"

# Ca 4: SB_MERGE_LOAD_WAIT_S=0 tắt việc chờ.
echo 99 > "$LOADF"
SB_MERGE_LOAD_WAIT_S=0 gate >"$TMP/gate4.log" 2>&1
grep -q "waiting for load" "$TMP/gate4.log" && fail "SB_MERGE_LOAD_WAIT_S=0 still waits" || ok "SB_MERGE_LOAD_WAIT_S=0: no wait"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_load_wait: PASS"; exit 0; } || { echo "test_merge_gate_load_wait: FAIL ($FAILS)"; exit 1; }
