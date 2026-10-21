#!/usr/bin/env bash
# #146: một lần verify dài hơn --stale-after không được làm gate khác reap khoá merge. Gate làm mới mốc "at" bằng heartbeat nền
# trong lúc verify chạy; heartbeat dừng khi verify xong và không ghi vào khoá đã bị gate khác chiếm (pid khác).
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-heartbeat-test.XXXXXX")"
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
# Tải mà heavy_slot.py (bọc lệnh verify) đọc: file riêng, tải thấp — không bao giờ tải thật của máy.
export DEVKIT_SLOT_LOAD_FILE="$TMP/slot-load"; echo 1 > "$DEVKIT_SLOT_LOAD_FILE"
LOCK="$WT/.claude/super-board/inflight/merge.lock"
CFG="$TMP/cfg.json"; CFG2="$TMP/cfg2.json"
# Verify đỏ (exit 3) để gate không merge; sleep 14 dài hơn --stale-after 5.
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo \\"KẾT LUẬN: FAIL\\"; sleep 14; exit 3"]}' > "$CFG"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo \\"KẾT LUẬN: FAIL\\"; exit 3"]}' > "$CFG2"
gate() { local cfg="$1"; shift; ( cd "$WT" && bash "$GATE" --config "$cfg" --pr 5 --expect-head "$H" "$@" ); }

# Ca 1: gate A verify 8 s với --stale-after 5; gate B vào lúc A đang verify và chờ tối đa 12 s → B không reap khoá của A.
gate "$CFG" --stale-after 5 >"$TMP/a.log" 2>&1 &
A=$!
i=0; while [ "$i" -lt 40 ] && ! grep -q "verify:" "$TMP/a.log" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
gate "$CFG2" --stale-after 5 --lock-timeout 25 >"$TMP/b.log" 2>&1; rcb=$?
wait "$A"; rca=$?
grep -q "reaping" "$TMP/b.log" && fail "gate B reaped the lock of a live verify: $(grep merge-gate "$TMP/b.log" | head -3)" \
  || ok "a verify longer than --stale-after keeps its lock (no reap)"
[ "$rca" -eq 11 ] && ok "gate A finished its verify (exit 11)" || fail "gate A exit $rca: $(tail -3 "$TMP/a.log")"
[ "$rcb" -eq 11 ] && ok "gate B took the lock after A released it (exit 11)" || fail "gate B exit $rcb: $(tail -3 "$TMP/b.log")"

# Ca 2: heartbeat dừng khi gate xong: pid heartbeat gate in ra không còn sống.
hb=$(sed -n 's/.*heartbeat pid \([0-9][0-9]*\).*/\1/p' "$TMP/a.log" | head -1)
if [ -n "$hb" ]; then
  sleep 1
  kill -0 "$hb" 2>/dev/null && fail "heartbeat pid $hb still alive after the gate exited" || ok "heartbeat stopped with the verify (no orphan)"
else fail "gate did not report a heartbeat pid: $(grep merge-gate "$TMP/a.log" | head -4)"; fi

# Ca 3: khoá đã bị gate khác chiếm (pid khác) thì heartbeat không làm mới mốc "at" của khoá đó.
# Lệnh verify tự đổi pid trong khoá, ghi mốc trước/sau 4 s (heartbeat 1 s sẽ làm mốc nhảy nếu nó vẫn ghi).
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo 999999 > %s/pid; echo 1 > %s/at; sleep 4; cp %s/at %s/at.after; exit 3"]}' "$LOCK" "$LOCK" "$LOCK" "$TMP" > "$CFG"
gate "$CFG" --stale-after 5 >"$TMP/c.log" 2>&1
[ "$(cat "$TMP/at.after" 2>/dev/null)" = "1" ] && ok "a lock taken by another pid is not refreshed by the heartbeat" \
  || fail "heartbeat wrote into a lock it no longer owns (at=$(cat "$TMP/at.after" 2>/dev/null || echo none))"

[ "$FAILS" -eq 0 ]
