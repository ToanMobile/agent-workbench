#!/usr/bin/env bash
# 19/10: verify của merge gate (post-fix-gate --full) chạy ngay cả khi máy tải ~60 (5 board cùng build): REG-DK-ALL-01 của PR #87
# (thẻ #12) chọn 127 test và quá 900 s, thẻ quay về Ready mãi. Luật: ngay trước verify, gate chờ tải 1 phút xuống dưới
# SB_MERGE_LOAD_MAX, có giới hạn SB_MERGE_LOAD_WAIT_S; hết giờ vẫn verify như cũ (không bỏ bước nào); --dry-run không chờ.
# SB_MERGE_LOAD_FILE là móc test: đọc tải từ file thay cho os.getloadavg(). Ngưỡng thời gian tính theo poll, không theo giây
# tuyệt đối: dưới tải cao riêng phần khởi động gate đã mất 4–5 s (review 19/10).
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
LOADF="$TMP/load"
export SB_MERGE_LOAD_FILE="$LOADF" SB_MERGE_LOAD_MAX=10
gate() { ( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" "$@" ); }
# Gate chạy xong và verify thật sự đã chạy: không thì một ca "không chờ" qua được chỉ vì gate chết sớm.
ran() { [ "$1" -eq 11 ] && [ -f "$STARTED" ]; }

# Ca 1: tải 99 suốt, poll 1, chờ tối đa 3 s → có dòng chờ, hết giờ vẫn verify (exit 11), verify sau ≥ 3 s, trong khoá.
echo 99 > "$LOADF"; rm -f "$STARTED"
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=3 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate1.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate1.log" \
  && ok "high load: the gate says it waits" || fail "no wait message at load 99: $(grep merge-gate "$TMP/gate1.log" | head -3)"
grep -q "verifying anyway" "$TMP/gate1.log" \
  && ok "wait capped: the gate verifies anyway" || fail "no capped-wait message: $(grep merge-gate "$TMP/gate1.log" | head -4)"
if [ -f "$STARTED" ] && [ $(( $(cat "$STARTED") - t0 )) -ge 3 ]; then ok "verify started after the 3 s wait"
else fail "verify did not wait (started=$(cat "$STARTED" 2>/dev/null || echo none), t0=$t0)"; fi
ran "$rc" && ok "verify still ran and decided (exit 11)" || fail "gate exit $rc (want 11 with a verify run)"
# Chờ trong khoá: dòng "lock taken" đứng trước dòng chờ (lối ra nhanh trước khoá không phải chờ).
lt=$(grep -n "lock taken" "$TMP/gate1.log" | head -1 | cut -d: -f1); wl=$(grep -n "waiting for load" "$TMP/gate1.log" | head -1 | cut -d: -f1)
[ -n "$lt" ] && [ -n "$wl" ] && [ "$lt" -lt "$wl" ] && ok "the wait comes after the lock and the early exits" \
  || fail "wait not after 'lock taken' (lock line ${lt:-none}, wait line ${wl:-none})"

# Ca 2: tải 99 rồi xuống 2 sau ~2 s, poll 1, chờ tối đa 60 s → verify bắt đầu khi tải xuống, xa trước 60 s.
echo 99 > "$LOADF"; rm -f "$STARTED"
( sleep 2; echo 2 > "$LOADF" ) &
writer=$!
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate2.log" 2>&1; rc=$?
wait "$writer" 2>/dev/null
d=$(( $(cat "$STARTED" 2>/dev/null || echo 0) - t0 ))
[ "$d" -ge 2 ] && [ "$d" -lt 40 ] && ok "verify started once the load dropped (${d}s, cap 60)" || fail "verify start ${d}s after the gate (want 2..39)"
grep -q "verifying anyway" "$TMP/gate2.log" && fail "load dropped but the gate says it gave up waiting" || ok "no capped-wait message when the load dropped"
ran "$rc" && ok "load dropped: verify ran (exit 11)" || fail "load dropped: gate exit $rc"

# Ca 3: tải thấp, poll 30 → không chờ: một lần chờ nhầm tốn ≥ 30 s, xa hơn mọi độ trễ khởi động.
echo 3 > "$LOADF"; rm -f "$STARTED"
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=30 gate >"$TMP/gate3.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate3.log" && fail "low load: the gate still waits" || ok "low load: no wait"
d=$(( $(cat "$STARTED" 2>/dev/null || echo 99) - t0 ))
[ "$d" -lt 25 ] && ok "low load: verify started without a poll (${d}s)" || fail "low load: verify started after ${d}s"
ran "$rc" && ok "low load: verify ran (exit 11)" || fail "low load: gate exit $rc"

# Ca 4: SB_MERGE_LOAD_WAIT_S=0 tắt việc chờ; ca 5: --dry-run không chờ.
echo 99 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=0 SB_MERGE_LOAD_POLL_S=30 gate >"$TMP/gate4.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate4.log" && fail "SB_MERGE_LOAD_WAIT_S=0 still waits" || ok "SB_MERGE_LOAD_WAIT_S=0: no wait"
ran "$rc" && ok "SB_MERGE_LOAD_WAIT_S=0: verify ran (exit 11)" || fail "SB_MERGE_LOAD_WAIT_S=0: gate exit $rc"
rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=30 gate --dry-run >"$TMP/gate5.log" 2>&1
grep -q "waiting for load" "$TMP/gate5.log" && fail "--dry-run waits for the load" || ok "--dry-run: no wait"

# Ca 6: số có 0 đứng đầu (08 = bát phân trong $(( ))) đọc là thập phân: gate không chết, vẫn chờ 2 s rồi verify.
echo 99 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=02 SB_MERGE_LOAD_POLL_S=08 SB_MERGE_LOAD_MAX=08 gate >"$TMP/gate6.log" 2>&1; rc=$?
ran "$rc" && ok "leading-zero settings: gate survives and verifies (exit 11)" || fail "leading-zero settings: gate exit $rc: $(tail -3 "$TMP/gate6.log")"
grep -q "waiting for load 99 to drop below 8 before verify (at most 2s)" "$TMP/gate6.log" \
  && ok "leading-zero settings read as decimal (max 8, cap 2 s)" || fail "leading-zero settings not honoured: $(grep merge-gate "$TMP/gate6.log" | head -3)"
# Ca 7: giá trị sai không tắt việc chờ trong im lặng: gate nói ra.
echo 3 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=30m gate >"$TMP/gate7.log" 2>&1; rc=$?
grep -q "SB_MERGE_LOAD_WAIT_S='30m' is not a number" "$TMP/gate7.log" \
  && ok "invalid wait setting is reported" || fail "invalid wait setting dropped silently: $(grep merge-gate "$TMP/gate7.log" | head -3)"
ran "$rc" && ok "invalid wait setting: verify ran (exit 11)" || fail "invalid wait setting: gate exit $rc"

# Ca 8: lúc chờ, mốc "at" của khoá được làm mới (không thì gate khác gỡ khoá "bỏ quên" và hai merge chạy cùng lúc).
AT="$WT/.claude/super-board/inflight/merge.lock/at"
echo 99 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=8 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate8.log" 2>&1 &
gp=$!
i=0; while [ "$i" -lt 60 ] && ! grep -q "waiting for load" "$TMP/gate8.log" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
a1=$(cat "$AT" 2>/dev/null || echo 0); sleep 3; a2=$(cat "$AT" 2>/dev/null || echo 0)
wait "$gp"
[ "$a2" -gt "$a1" ] && ok "lock stamp refreshed while waiting ($a1 -> $a2)" || fail "lock stamp not refreshed while waiting ($a1 -> $a2)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_load_wait: PASS"; exit 0; } || { echo "test_merge_gate_load_wait: FAIL ($FAILS)"; exit 1; }
