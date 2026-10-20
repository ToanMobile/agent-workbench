#!/usr/bin/env bash
# 19/10: verify của merge gate (post-fix-gate --full) chạy ngay cả khi máy tải ~60 (5 board cùng build): REG-DK-ALL-01 của PR #87
# (thẻ #12) chọn 127 test và quá 900 s, thẻ quay về Ready mãi. Luật: trong khoá, trước khi chốt base, gate chờ tải 1 phút xuống dưới
# SB_MERGE_LOAD_MAX, có giới hạn SB_MERGE_LOAD_WAIT_S; hết giờ vẫn verify như cũ (không bỏ bước nào); --dry-run không chờ.
# SB_MERGE_LOAD_FILE là móc test: đọc tải từ file thay cho os.getloadavg(). Ngưỡng thời gian tính theo poll, không theo giây
# tuyệt đối: dưới tải cao riêng phần khởi động gate đã mất 4–5 s (review 19/10).
# Mặc định tắt: board bật bằng merge_load_wait_s trong config; biến môi trường SB_MERGE_LOAD_WAIT_S ghi đè.
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
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT
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
  *" pr view "*"state,mergeCommit,headRefOid"*) st=$(cat "$FAKE_DIR/pr$n.state" 2>/dev/null || echo OPEN); mc=null; [ "$st" = MERGED ] && mc="{\"oid\":\"$head\"}"; printf '{"state":"%s","mergeCommit":%s,"headRefOid":"%s"}\n' "$st" "$mc" "$head" ;;
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

# Đợi tới khi gate in dòng chờ (tối đa 30 s) rồi mới chạy lệnh: không phụ thuộc gate khởi động nhanh hay chậm.
when_waiting() { local i=0; while [ "$i" -lt 60 ] && ! grep -q "waiting for load" "$1" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done; }

# Ca 2: tải 99, gate vào chờ, rồi tải xuống 2; poll 1, chờ tối đa 60 s → verify bắt đầu khi tải xuống, xa trước 60 s.
echo 99 > "$LOADF"; rm -f "$STARTED"
( when_waiting "$TMP/gate2.log"; echo 2 > "$LOADF" ) &
writer=$!
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate2.log" 2>&1; rc=$?
wait "$writer" 2>/dev/null
d=$(( $(cat "$STARTED" 2>/dev/null || echo $((t0 + 9999))) - t0 ))
grep -q "load 2 after" "$TMP/gate2.log" && ok "the gate waited, then saw the load drop" || fail "no mid-wait drop seen: $(grep merge-gate "$TMP/gate2.log" | head -4)"
[ "$d" -lt 40 ] && ok "verify started once the load dropped (${d}s, cap 60)" || fail "verify start ${d}s after the gate (want < 40)"
grep -q "verifying anyway" "$TMP/gate2.log" && fail "load dropped but the gate says it gave up waiting" || ok "no capped-wait message when the load dropped"
ran "$rc" && ok "load dropped: verify ran (exit 11)" || fail "load dropped: gate exit $rc"

# Ca 3: tải thấp, poll 30 → không chờ: một lần chờ nhầm tốn ≥ 30 s, xa hơn mọi độ trễ khởi động.
echo 3 > "$LOADF"; rm -f "$STARTED"
t0=$(date +%s)
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=30 gate >"$TMP/gate3.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate3.log" && fail "low load: the gate still waits" || ok "low load: no wait"
d=$(( $(cat "$STARTED" 2>/dev/null || echo $((t0 + 9999))) - t0 ))
[ "$d" -lt 25 ] && ok "low load: verify started without a poll (${d}s)" || fail "low load: verify started after ${d}s"
ran "$rc" && ok "low load: verify ran (exit 11)" || fail "low load: gate exit $rc"

# Ca 3b: không biến môi trường, config không có merge_load_wait_s → mặc định không chờ (test khác của gate không bị chậm).
echo 99 > "$LOADF"; rm -f "$STARTED"
( unset SB_MERGE_LOAD_WAIT_S; SB_MERGE_LOAD_POLL_S=1 gate ) >"$TMP/gate3b.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate3b.log" && fail "no merge_load_wait_s in the config, yet the gate waits" || ok "config without merge_load_wait_s: no wait"
ran "$rc" && ok "config without merge_load_wait_s: verify ran (exit 11)" || fail "config without merge_load_wait_s: gate exit $rc"
# Ca 3c: config bật merge_load_wait_s=3 (không biến môi trường) → chờ rồi verify.
CFG_ON="$TMP/cfg-on.json"; jq '.merge_load_wait_s = 3' "$CFG" > "$CFG_ON"
echo 99 > "$LOADF"; rm -f "$STARTED"
( unset SB_MERGE_LOAD_WAIT_S; cd "$WT" && SB_MERGE_LOAD_POLL_S=1 bash "$GATE" --config "$CFG_ON" --pr 5 --expect-head "$H" ) >"$TMP/gate3c.log" 2>&1; rc=$?
grep -q "waiting for load 99 to drop below 10 before verify (at most 3s)" "$TMP/gate3c.log" \
  && ok "config merge_load_wait_s=3: the gate waits" || fail "config merge_load_wait_s=3 ignored: $(grep merge-gate "$TMP/gate3c.log" | head -3)"
ran "$rc" && ok "config merge_load_wait_s=3: verify ran after the wait (exit 11)" || fail "config merge_load_wait_s=3: gate exit $rc"

# Ca 4: SB_MERGE_LOAD_WAIT_S=0 tắt việc chờ; ca 5: --dry-run không chờ.
echo 99 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=0 SB_MERGE_LOAD_POLL_S=30 gate >"$TMP/gate4.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate4.log" && fail "SB_MERGE_LOAD_WAIT_S=0 still waits" || ok "SB_MERGE_LOAD_WAIT_S=0: no wait"
ran "$rc" && ok "SB_MERGE_LOAD_WAIT_S=0: verify ran (exit 11)" || fail "SB_MERGE_LOAD_WAIT_S=0: gate exit $rc"
rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=30 gate --dry-run >"$TMP/gate5.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate5.log" && fail "--dry-run waits for the load" || ok "--dry-run: no wait"
ran "$rc" && ok "--dry-run: gate got past the wait point and verified (exit 11)" || fail "--dry-run: gate exit $rc"

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
# Ca 7b: tải không đọc được (12.5) → nói ra, không chờ, vẫn verify; poll sai → nói ra, dùng 30 s.
echo 12.5 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=60 SB_MERGE_LOAD_POLL_S=x gate >"$TMP/gate7b.log" 2>&1; rc=$?
grep -q "cannot read the machine load ('12.5')" "$TMP/gate7b.log" \
  && ok "unreadable load is reported, no wait" || fail "unreadable load not reported: $(grep merge-gate "$TMP/gate7b.log" | head -3)"
grep -q "SB_MERGE_LOAD_POLL_S='x' is not a positive number" "$TMP/gate7b.log" \
  && ok "invalid poll setting is reported" || fail "invalid poll setting dropped silently"
ran "$rc" && ok "unreadable load: verify ran (exit 11)" || fail "unreadable load: gate exit $rc"

# Ca 8: lúc chờ, mốc "at" của khoá được làm mới (không thì gate khác gỡ khoá "bỏ quên" và hai merge chạy cùng lúc).
AT="$WT/.claude/super-board/inflight/merge.lock/at"
echo 99 > "$LOADF"; rm -f "$STARTED"
SB_MERGE_LOAD_WAIT_S=8 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate8.log" 2>&1 &
gp=$!
i=0; while [ "$i" -lt 60 ] && ! grep -q "waiting for load" "$TMP/gate8.log" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
a1=$(cat "$AT" 2>/dev/null || echo 0); sleep 3; a2=$(cat "$AT" 2>/dev/null || echo 0)
wait "$gp"
[ "$a2" -gt "$a1" ] && ok "lock stamp refreshed while waiting ($a1 -> $a2)" || fail "lock stamp not refreshed while waiting ($a1 -> $a2)"

# Ca 9: head PR đổi trong lúc chờ → exit 6, không verify code cũ.
echo 99 > "$LOADF"; rm -f "$STARTED"
( when_waiting "$TMP/gate9.log"; echo 0123456789abcdef0123456789abcdef01234567 > "$TMP/pr5.head" ) &
writer=$!
SB_MERGE_LOAD_WAIT_S=3 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate9.log" 2>&1; rc=$?
wait "$writer" 2>/dev/null; echo "$H" > "$TMP/pr5.head"
[ "$rc" -eq 6 ] && ok "head moved during the wait: exit 6" || fail "head moved during the wait: gate exit $rc (want 6): $(grep merge-gate "$TMP/gate9.log" | tail -3)"
[ -f "$STARTED" ] && fail "verify ran on the old head after the PR moved" || ok "no verify on the old head"

# Ca 10: chờ quá nửa LOCK_TIMEOUT bị giới hạn và gate nói ra.
echo 3 > "$LOADF"; rm -f "$STARTED"
( cd "$WT" && SB_MERGE_LOAD_WAIT_S=999 bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" --lock-timeout 60 ) >"$TMP/gate10.log" 2>&1
grep -q "over half the lock timeout; waiting at most 30s" "$TMP/gate10.log" \
  && ok "wait cap clamped to half the lock timeout" || fail "no clamp message: $(grep merge-gate "$TMP/gate10.log" | head -3)"

# Ca 11–12: PR được merge / bị đóng trên GitHub trong lúc chờ → exit 0 / 3, không verify.
for pair in "MERGED 0" "CLOSED 3"; do
  st=${pair% *}; want=${pair#* }
  echo 99 > "$LOADF"; rm -f "$STARTED" "$TMP/pr5.state"
  ( when_waiting "$TMP/gate-$st.log"; echo "$st" > "$TMP/pr5.state" ) &
  writer=$!
  SB_MERGE_LOAD_WAIT_S=3 SB_MERGE_LOAD_POLL_S=1 gate >"$TMP/gate-$st.log" 2>&1; rc=$?
  wait "$writer" 2>/dev/null; rm -f "$TMP/pr5.state"
  [ "$rc" -eq "$want" ] && [ ! -f "$STARTED" ] && ok "PR ${st} during the wait: exit ${want}, no verify" \
    || fail "PR ${st} during the wait: gate exit $rc (want ${want}), verify ran: $([ -f "$STARTED" ] && echo yes || echo no)"
done

# Ca 13–15: ngưỡng tải đọc được từ config board `merge_load_max` (người dùng 20/10: "dưới 100 thì cho chạy" — máy này tải 45–86 cả
# ngày, ngưỡng mặc định 2 × số core = 24 không bao giờ đạt nên PR nào cũng chờ hết merge_load_wait_s). Biến SB_MERGE_LOAD_MAX vẫn thắng.
CFG_MAX="$TMP/cfg-max.json"; jq '.merge_load_wait_s = 3 | .merge_load_max = 100' "$CFG" > "$CFG_MAX"
gate_max() { ( unset SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX; cd "$WT" && SB_MERGE_LOAD_POLL_S=1 "$@" bash "$GATE" --config "$CFG_MAX" \
  --pr 5 --expect-head "$H" ); }
echo 60 > "$LOADF"; rm -f "$STARTED"
gate_max env >"$TMP/gate13.log" 2>&1; rc=$?
grep -q "waiting for load" "$TMP/gate13.log" && fail "config merge_load_max=100, load 60: the gate still waits" \
  || ok "config merge_load_max=100, load 60: no wait"
ran "$rc" && ok "config merge_load_max=100, load 60: verify ran (exit 11)" || fail "config merge_load_max=100, load 60: gate exit $rc"
echo 120 > "$LOADF"; rm -f "$STARTED"
gate_max env >"$TMP/gate14.log" 2>&1; rc=$?
grep -q "waiting for load 120 to drop below 100 before verify (at most 3s)" "$TMP/gate14.log" \
  && ok "config merge_load_max=100, load 120: the gate waits" || fail "config merge_load_max=100, load 120: $(grep merge-gate "$TMP/gate14.log" | head -3)"
echo 60 > "$LOADF"; rm -f "$STARTED"
gate_max env SB_MERGE_LOAD_MAX=50 >"$TMP/gate15.log" 2>&1; rc=$?
grep -q "waiting for load 60 to drop below 50 before verify" "$TMP/gate15.log" \
  && ok "SB_MERGE_LOAD_MAX=50 overrides config merge_load_max=100" || fail "env did not override the config: $(grep merge-gate "$TMP/gate15.log" | head -3)"

# Ca 16: lệnh verify chạy với DEVKIT_SLOT_PRIORITY=merge (bin/heavy_slot.py: merge đứng đầu hàng đợi khoá Unity;
# post-fix-gate không chạy sentinel hằng ngày trong merge gate) và DEVKIT_SLOT_LOAD_WAIT_S=0 (tải đã được chờ ở trên, bên trong không
# chờ lần nữa). Biến đã đặt sẵn thì giữ nguyên.
PRIOF="$TMP/prio"; CFG_PRIO="$TMP/cfg-prio.json"
jq --arg f "$PRIOF" '.verify_commands = ["printf \"%s %s\" \"${DEVKIT_SLOT_PRIORITY:-}\" \"${DEVKIT_SLOT_LOAD_WAIT_S:-}\" > \($f); exit 3"]' "$CFG" > "$CFG_PRIO"
echo 3 > "$LOADF"; rm -f "$PRIOF"
( unset DEVKIT_SLOT_PRIORITY DEVKIT_SLOT_LOAD_WAIT_S; cd "$WT" && SB_MERGE_LOAD_WAIT_S=0 bash "$GATE" --config "$CFG_PRIO" --pr 5 --expect-head "$H" ) >"$TMP/gate16.log" 2>&1
[ "$(cat "$PRIOF" 2>/dev/null)" = "merge 0" ] && ok "verify runs with DEVKIT_SLOT_PRIORITY=merge and DEVKIT_SLOT_LOAD_WAIT_S=0" \
  || fail "verify env: '$(cat "$PRIOF" 2>/dev/null)' (want 'merge 0')"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_load_wait: PASS"; exit 0; } || { echo "test_merge_gate_load_wait: FAIL ($FAILS)"; exit 1; }
