#!/usr/bin/env bash
# Test P3 (cờ dependency_unblock_v1): đường giao Ready của worker_backend claude-p (dispatch_ready_tick → dispatch_lane build) chưa
# từng gọi super-board-deps.sh, nên thẻ Ready có `## Blocked by` còn issue MỞ vẫn tới tay builder, builder viết Block rồi đẩy thẻ vào
# Blocked (Humans-vs.-UFOs #61, 25/10). Cờ bật: dependency_gate đọc deps trước preflight/claim; còn blocker mở → mark waiting-on,
# thẻ ở lại Ready, không claim, không Building/Blocked, không spawn. Luật ở đây:
#  T1  cờ tắt: test đòi file ghi lời gọi deps/mark vắng, worker spawn; writes/log (đường dẫn tmp chuẩn hoá) bằng đúng lần chạy
#      của runner GỐC (b235c84b, trước PR) đặt trong bản sao scratch; log cờ tắt không có dòng nào chứa "dependency".
#  T2  cờ bật + openBlockers [34,59] → mark --on 34,59; không claim/Building/Blocked/blocked-by, không spawn, preflight không chạy,
#      PREFLIGHT_SKIP có thẻ, cache có nhãn.
#  T3  openBlockers [] → không mark, preflight chạy, claim + Building + spawn.
#  T4  deps exit 79 và ghi $SB_GITHUB_HALT_FILE → giao như cũ; file halt chung không có, stub thấy đường dẫn halt riêng (đã dọn).
#  T5  deps in rác / thiếu khoá thẻ / thiếu openBlockers → giao như cũ.
#  T6  mark trả labels [] → giao như cũ.
#  T7  mark exit 69/79 hoặc in rác → không claim, thẻ ở Ready, dispatch_lane trả 0. Exit 64 (đầu vào sai, thử lại vô ích) →
#      ⚠ log, giao như cũ.
#  T12 ## Blocked by của #7 ghi chính #7: [7] → bỏ mục đó, không mark, giao như cũ (⚠ log); [7,34] → mark --on 34, giữ.
#  T8  đọc cờ: flags.json true → bật, thiếu → tắt, hỏng → tắt, false → tắt, env 0 thắng file true, env 1 thắng file thiếu;
#      worktree đọc flags.json của checkout chính (git common dir).
#  T10 dispatch_ready_tick: #7 bị giữ, #8 rảnh → #8 được giao trong cùng tick.
#  T11 thẻ Ready nhãn `qa` (lane qa): test đòi file deps-calls vắng.
# Chạy offline: runner source ở lib mode, gh/claude/preflight/deps/helper là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-dep-unblock.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# git không được leo lên checkout thật phía trên $TMP (cờ đọc flags.json thật sẽ làm test phụ thuộc máy)
export GIT_CEILING_DIRECTORIES="$TMP"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SB_DEPENDENCY_UNBLOCK_V1 SB_DEPS
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board/runs" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cat > "$TMP/path/gh" <<'SH'
#!/bin/sh
echo "OPEN https://github.com/acme/widgets/issues/$3"
SH
# preflight stub: in $STUB_PREFLIGHT_JSON, ghi lời gọi
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit "${STUB_PREFLIGHT_RC:-0}"
SH
# deps stub: ghi lời gọi + đường dẫn halt nó nhận; STUB_DEPS_OUT (thô) hoặc STUB_DEPS_MAP {"N":[blockers]} theo --issues; exit STUB_DEPS_RC
cat > "$TMP/bin/super-board-deps.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/deps-calls"
echo "${SB_GITHUB_HALT_FILE:-}" >> "$STUB_DIR/deps-halt"
[ "${STUB_DEPS_WRITE_HALT:-0}" != 1 ] || echo '{"halted":true}' > "$SB_GITHUB_HALT_FILE"
n=""
while [ $# -gt 0 ]; do [ "$1" = --issues ] && n="$2"; shift; done
if [ -n "${STUB_DEPS_OUT+x}" ]; then
  printf '%s\n' "$STUB_DEPS_OUT"
else
  jq -nc --argjson m "${STUB_DEPS_MAP:-{\}}" --arg n "$n" \
    'if $m[$n] == null then {} else {($n): {number: ($n | tonumber), openBlockers: $m[$n], runnable: (($m[$n] | length) == 0)}} end'
fi
exit "${STUB_DEPS_RC:-0}"
SH
cat > "$TMP/bin/super-board-waiting-on.py" <<'PY'
import os, sys
with open(os.path.join(os.environ["STUB_DIR"], "wo-calls"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
print(os.environ.get("STUB_WO_OUT", ""))
sys.exit(int(os.environ.get("STUB_WO_RC", "0")))
PY
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude" "$TMP/path/gh"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_WAITING_ON SB_WAITING_SWEEP_EVERY
# Biến + stub đặt SAU mỗi lần source runner (source đè log/gh_write_once…); T1 gọi lại sau khi source runner gốc.
install_stubs() {
  set +e
  SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
  printf 'import sys\nsys.exit(0)\n' > "$TMP/bin/super-board-needs-you.py"
  CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$CONFIG_PATH"
  INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
  WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
  BOT_LOGIN="bot"; PROJECT_OWNER="acme"; PROJECT_NUMBER=1   # Building chỉ ghi khi có project: đối chứng T3 phải thấy nó
  export SB_GITHUB_HALT_FILE="$TMP/halt.json"
  gh_checkpoint() { :; }
  gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
  set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
  log() { echo "$*" >> "$TMP/log"; }
  issue_is_open() { return 0; }
  issue_locked() { [ -e "$INFLIGHT_DIR/$1" ]; }
  early_backoff() { return 1; }
  ready_card_held() { return 1; }
  resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
  note_worker_limit() { :; }
  cd "$TMP/repo" || exit 1
}
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
install_stubs
card() { printf '{"id":"PVTI_%s","status":"Ready","labels":[%s],"content":{"type":"Issue","number":%s,"title":"card %s","assignees":[]}}' "$1" "${2:-}" "$1" "$1"; }
GO='{"verdict":"proceed","tag":"","reason":"ok"}'
reset() {
  : > "$TMP/writes"; : > "$TMP/log"
  rm -f "$TMP/spawned" "$TMP/preflight-calls" "$TMP/wo-calls" "$TMP/deps-calls" "$TMP/deps-halt" "$TMP/halt.json" "$INFLIGHT_DIR"/*
  PROJECT_ITEMS_JSON="{\"items\":[$(card 7)]}"
  SB_READY_TICK=1; PREFLIGHT_SKIP=""; CARD_WRITE_BLOCKED=""; BUILD_FREE=1; QA_FREE=0; ACTIVE_WORKERS=0
  unset STUB_DEPS_OUT STUB_DEPS_RC STUB_DEPS_WRITE_HALT SB_DEPS
  export STUB_DEPS_MAP='{"7":[34,59]}' STUB_WO_RC=0 STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#34","waiting-on:#59"],"commented":true}'
  export STUB_PREFLIGHT_RC=0 STUB_PREFLIGHT_JSON="{\"7\":$GO,\"8\":$GO}"
  export SB_DEPENDENCY_UNBLOCK_V1=1
}
labels_of() { printf '%s' "$PROJECT_ITEMS_JSON" | jq -c --argjson n "$1" '[.items[] | select(.content.number == $n) | .labels][0]'; }
locked() { [ -e "$INFLIGHT_DIR/$1" ]; }
# bằng chứng "giao như hôm nay": deps đã được hỏi, rồi claim + Building + lock
dispatched() { locked "$1" && grep -q -- "--add-assignee" "$TMP/writes" && grep -q "move PVTI_$1 Building" "$TMP/writes"; }
held() { ! locked "$1" && ! grep -q -- "--add-assignee" "$TMP/writes" && ! grep -q "move PVTI_$1 " "$TMP/writes" && ! grep -q "blocked-by:" "$TMP/writes"; }
BASE_SHA=b235c84b   # main ngay trước PR #927: runner chưa có dependency_gate
BASE_BIN="$TMP/base/.claude/bin"
norm() {
  sed -E "s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z/<ts>/g; s/pid=[0-9]+/pid=<n>/g; s#${BASE_BIN}#<bin>#g; s#${ROOT}/.claude/bin#<bin>#g; s#${TMP}#<tmp>#g" "$1"
}

# ── T1. cờ tắt (không env, không flags.json): đòi deps-calls/wo-calls vắng, có spawn; so writes/log với runner gốc
reset; unset SB_DEPENDENCY_UNBLOCK_V1
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/deps-calls" ] && [ ! -e "$TMP/wo-calls" ] && dispatched 7 && [ -s "$TMP/preflight-calls" ] \
  && ok "T1 flag off: deps and mark not called, preflight ran, card claimed, moved to Building, worker spawned" \
  || fail "T1 flag off wrong: rc=$rc deps=$(cat "$TMP/deps-calls" 2>/dev/null) wo=$(cat "$TMP/wo-calls" 2>/dev/null) writes=$(tr '\n' '|' < "$TMP/writes")"
norm "$TMP/writes" > "$TMP/t1-writes-a"; norm "$TMP/log" > "$TMP/t1-log-a"
! grep -qi "dependency" "$TMP/log" && ok "  … flag-off log has no dependency line" \
  || fail "  flag-off log mentions dependency: $(grep -i dependency "$TMP/log" | head -2 | tr '\n' '|')"
# Runner gốc trong bản sao scratch: file cạnh nó là symlink tới .claude/bin thật, chỉ super-board-run.sh là bản $BASE_SHA.
mkdir -p "$BASE_BIN"
for f in "$ROOT/.claude/bin/"*; do ln -s "$f" "$BASE_BIN/"; done
rm -f "$BASE_BIN/super-board-run.sh"
if git -C "$ROOT" show "$BASE_SHA:.claude/bin/super-board-run.sh" > "$BASE_BIN/super-board-run.sh" 2>/dev/null \
   && ! grep -q "dependency_gate" "$BASE_BIN/super-board-run.sh"; then
  # reset NGAY sau source: source đặt lại PROJECT_ITEMS_JSON và các biến khác của runner
  ( SB_LIB_ONLY=1 . "$BASE_BIN/super-board-run.sh" || exit 1; install_stubs; reset; unset SB_DEPENDENCY_UNBLOCK_V1
    dispatch_lane build 7 ) >/dev/null 2>&1; brc=$?
  norm "$TMP/writes" > "$TMP/t1-writes-base"; norm "$TMP/log" > "$TMP/t1-log-base"
  [ "$brc" = 0 ] && [ -s "$TMP/t1-writes-a" ] && cmp -s "$TMP/t1-writes-a" "$TMP/t1-writes-base" && cmp -s "$TMP/t1-log-a" "$TMP/t1-log-base" \
    && ok "  … writes and log identical to the base runner ($BASE_SHA, before the PR)" \
    || fail "  flag-off run differs from the base runner (rc=$brc): $(diff "$TMP/t1-writes-a" "$TMP/t1-writes-base" | head -3 | tr '\n' '|') $(diff "$TMP/t1-log-a" "$TMP/t1-log-base" | head -3 | tr '\n' '|')"
else
  fail "  could not read the base runner $BASE_SHA:.claude/bin/super-board-run.sh (or it already has dependency_gate)"
fi

# ── T2. cờ bật + openBlockers [34,59] → giữ ở Ready (waiting-on)
reset; dc0=${DISPATCH_COUNT:-0}
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
grep -q -- "^--repo acme/widgets --config $CONFIG_PATH --issues 7$" "$TMP/deps-calls" 2>/dev/null \
  && ok "T2 deps called with --repo acme/widgets --config <cfg> --issues 7" || fail "T2 deps call: $(cat "$TMP/deps-calls" 2>/dev/null)"
grep -q -- "^mark --config $CONFIG_PATH --issue 7 --on 34,59 --why=## Blocked by: #34, #59 still open$" "$TMP/wo-calls" 2>/dev/null \
  && ok "  … mark called with --on 34,59 and the ## Blocked by reason" || fail "  mark call: $(cat "$TMP/wo-calls" 2>/dev/null)"
[ "$rc" = 0 ] && held 7 && ok "  … no claim, no Building/Blocked move, no blocked-by, no lock (rc=0)" \
  || fail "  card not held: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes") lock=$(locked 7 && echo yes || echo no)"
[ ! -e "$TMP/preflight-calls" ] && ok "  … preflight not called" || fail "  preflight ran: $(cat "$TMP/preflight-calls")"
case " $PREFLIGHT_SKIP " in *" 7 "*) ok "  … PREFLIGHT_SKIP has #7 ('$PREFLIGHT_SKIP')" ;; *) fail "  PREFLIGHT_SKIP='$PREFLIGHT_SKIP'" ;; esac
[ "$(labels_of 7)" = '["waiting-on:#34","waiting-on:#59"]' ] && ok "  … cache carries the waiting-on labels" || fail "  cache labels: $(labels_of 7)"
grep -q "held in Ready (waiting-on), not dispatched" "$TMP/log" && ok "  … logged held in Ready (waiting-on)" || fail "  log: $(tr '\n' '|' < "$TMP/log")"
# Đo bằng DISPATCH_COUNT (runner tăng nó ngay sau `pid=$!` trong dispatch_lane). File `spawned` của stub nền từng làm ca này đỏ
# dưới tải trong gate 03/11 (worker của T1 ghi muộn, sau reset).
[ "${DISPATCH_COUNT:-0}" = "$dc0" ] && ok "  … no worker spawned (DISPATCH_COUNT unchanged)" || fail "  worker spawned (DISPATCH_COUNT $dc0 → ${DISPATCH_COUNT:-})"

# ── T3. openBlockers [] → không mark, preflight chạy, giao
reset; export STUB_DEPS_MAP='{"7":[]}'
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/deps-calls" ] && [ ! -e "$TMP/wo-calls" ] && [ -s "$TMP/preflight-calls" ] && dispatched 7 \
  && ok "T3 openBlockers []: no mark, preflight ran, claimed, Building, spawned" \
  || fail "T3 wrong: rc=$rc deps=$([ -s "$TMP/deps-calls" ] && echo y) wo=$(cat "$TMP/wo-calls" 2>/dev/null) writes=$(tr '\n' '|' < "$TMP/writes")"

# ── T4. deps exit 79 + ghi file halt → giao như cũ, file halt chung không bị đụng, thư mục halt riêng đã dọn
reset; export STUB_DEPS_RC=79 STUB_DEPS_WRITE_HALT=1
( dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
seen=$(head -1 "$TMP/deps-halt" 2>/dev/null)
[ "$rc" = 0 ] && dispatched 7 && [ ! -e "$TMP/wo-calls" ] && ok "T4 deps exit 79: dispatched as today (rc=0)" \
  || fail "T4 not dispatched: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes")"
[ ! -e "$TMP/halt.json" ] && [ -n "$seen" ] && [ "$seen" != "$TMP/halt.json" ] && [ ! -e "$(dirname "$seen")" ] \
  && ok "  … shared halt file absent; deps saw a private halt path ($seen), removed after" \
  || fail "  halt handling: shared=$([ -e "$TMP/halt.json" ] && echo present || echo absent) seen=[$seen] dir=$([ -e "$(dirname "${seen:-/nonexistent/x}")" ] && echo kept || echo gone)"
grep -q "⚠ dependency gate #7" "$TMP/log" && ok "  … ⚠ line logged" || fail "  no ⚠ line: $(tr '\n' '|' < "$TMP/log")"

# ── T5. deps in rác / thiếu khoá / thiếu openBlockers → giao
for out in 'not json' '{"8":{"number":8,"openBlockers":[3]}}' '{"7":{"number":7}}' '{"7":{"number":7,"openBlockers":"34"}}'; do
  reset; export STUB_DEPS_OUT="$out"
  dispatch_lane build 7 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -s "$TMP/deps-calls" ] && [ ! -e "$TMP/wo-calls" ] && dispatched 7 && grep -q "⚠ dependency gate #7" "$TMP/log" \
    && ok "T5 deps output '$out': ⚠ logged, dispatched" \
    || fail "T5 deps output '$out': rc=$rc deps=$([ -s "$TMP/deps-calls" ] && echo y) writes=$(tr '\n' '|' < "$TMP/writes")"
done

# ── T6. mark trả labels [] → giao
reset; export STUB_WO_OUT='{"issue":7,"labels":[],"commented":false}'
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/wo-calls" ] && [ -s "$TMP/preflight-calls" ] && dispatched 7 && [ "$(labels_of 7)" = '[]' ] \
  && ok "T6 mark labels []: preflight ran, dispatched, no label cached" || fail "T6 wrong: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes") labels=$(labels_of 7)"

# ── T7. mark exit 64 (đầu vào sai: thử lại mỗi tick vô ích) → ⚠ log, giao như cũ
reset; export STUB_WO_RC=64 STUB_WO_OUT=''
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/wo-calls" ] && [ -s "$TMP/preflight-calls" ] && dispatched 7 && grep -q "⚠ dependency gate #7: .*exit 64" "$TMP/log" \
  && ok "T7 mark exit 64: ⚠ logged, preflight ran, dispatched as today" \
  || fail "T7 mark exit 64: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes") log=$(tr '\n' '|' < "$TMP/log")"
# ── T7. mark hỏng tạm thời (69/79) → không claim, ở Ready, dispatch_lane trả 0
for mrc in 69 79; do
  reset; export STUB_WO_RC=$mrc STUB_WO_OUT=''
  dispatch_lane build 7 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -s "$TMP/wo-calls" ] && held 7 && [ ! -e "$TMP/preflight-calls" ] && [ "$(labels_of 7)" = '[]' ] && [ ! -e "$TMP/halt.json" ] \
    && ok "T7 mark exit $mrc: not claimed, left in Ready, no halt, dispatch_lane returns 0" \
    || fail "T7 mark exit $mrc: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes") labels=$(labels_of 7)"
done
reset; export STUB_WO_OUT='garbage'
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && held 7 && ok "T7 mark output not JSON: held, not claimed" || fail "T7 mark garbage: rc=$rc writes=$(tr '\n' '|' < "$TMP/writes")"

# ── T12. ## Blocked by tự tham chiếu (#7 ghi `- #7`): deps đếm #7 là mở; helper mark từ chối (64) → trước đây kẹt Ready mãi
reset; export STUB_DEPS_MAP='{"7":[7]}' STUB_WO_RC=64 STUB_WO_OUT=''
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wo-calls" ] && [ -s "$TMP/preflight-calls" ] && dispatched 7 && grep -q "⚠ dependency gate #7: .*itself" "$TMP/log" \
  && ok "T12 openBlockers [7] on #7: self entry dropped, mark not called, ⚠ logged, dispatched" \
  || fail "T12 self-blocker: rc=$rc wo=$(cat "$TMP/wo-calls" 2>/dev/null) writes=$(tr '\n' '|' < "$TMP/writes") log=$(tr '\n' '|' < "$TMP/log")"
reset; export STUB_DEPS_MAP='{"7":[7,34]}' STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#34"],"commented":true}'
dispatch_lane build 7 >/dev/null 2>&1; rc=$?
grep -q -- "^mark --config $CONFIG_PATH --issue 7 --on 34 --why=## Blocked by: #34 still open$" "$TMP/wo-calls" 2>/dev/null && [ "$rc" = 0 ] && held 7 \
  && ok "T12 openBlockers [7,34] on #7: mark --on 34 only, held in Ready" \
  || fail "T12 self + #34: rc=$rc wo=$(cat "$TMP/wo-calls" 2>/dev/null) writes=$(tr '\n' '|' < "$TMP/writes")"

# ── T8. bộ đọc cờ
flag() { dependency_unblock_v1_on && echo on || echo off; }
if type dependency_unblock_v1_on >/dev/null 2>&1; then
  FR="$TMP/flagrepo"; mkdir -p "$FR/.agents/local"; git -C "$FR" init -q 2>/dev/null
  git -C "$FR" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>/dev/null
  SAVED_ROOT="$REPO_ROOT"; REPO_ROOT="$FR"; unset SB_DEPENDENCY_UNBLOCK_V1
  r_missing=$(flag)
  echo '{"dependency_unblock_v1": true}' > "$FR/.agents/local/flags.json"; r_true=$(flag)
  r_env0=$(export SB_DEPENDENCY_UNBLOCK_V1=0; flag)
  echo '{"dependency_unblock_v1": false}' > "$FR/.agents/local/flags.json"; r_false=$(flag)
  echo '{"dependency_unblock_v1": tr' > "$FR/.agents/local/flags.json"; r_broken=$(flag)
  rm -f "$FR/.agents/local/flags.json"; r_env1=$(export SB_DEPENDENCY_UNBLOCK_V1=1; flag)
  r_after=$(flag)   # các lần đặt env ở trên chỉ sống trong subshell của chúng
  echo '{"dependency_unblock_v1": true}' > "$FR/.agents/local/flags.json"
  r_wt=skip
  if git -C "$FR" worktree add -q --detach "$TMP/flagwt" >/dev/null 2>&1; then REPO_ROOT="$TMP/flagwt"; r_wt=$(flag); fi
  REPO_ROOT="$TMP/not-a-repo"; mkdir -p "$REPO_ROOT"; r_norepo=$(flag)
  REPO_ROOT="$SAVED_ROOT"
  [ "$r_true" = on ] && ok "T8 flags.json true → on" || fail "T8 flags.json true → $r_true"
  [ "$r_missing" = off ] && ok "T8 flags.json missing → off" || fail "T8 missing → $r_missing"
  [ "$r_broken" = off ] && ok "T8 flags.json broken → off" || fail "T8 broken → $r_broken"
  [ "$r_false" = off ] && ok "T8 flags.json false → off" || fail "T8 false → $r_false"
  [ "$r_env0" = off ] && ok "T8 env 0 beats file true → off" || fail "T8 env 0 → $r_env0"
  [ "$r_env1" = on ] && ok "T8 env 1 beats a missing file → on" || fail "T8 env 1 → $r_env1"
  [ "$r_after" = off ] && ok "T8 env unset again, file missing → off" || fail "T8 env leaked → $r_after"
  [ "$r_wt" = on ] && ok "T8 a linked worktree reads the main checkout's flags.json → on" || fail "T8 worktree → $r_wt"
  [ "$r_norepo" = off ] && ok "T8 REPO_ROOT not a git repo → off" || fail "T8 not a repo → $r_norepo"
else
  fail "T8 dependency_unblock_v1_on is not defined in the runner"
fi

# ── T10. dispatch_ready_tick: #7 giữ, #8 rảnh → #8 giao cùng tick
reset
PROJECT_ITEMS_JSON="{\"items\":[$(card 7 '"priority:high"'),$(card 8)]}"
export STUB_DEPS_MAP='{"7":[34],"8":[]}' STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#34"],"commented":true}'
dispatch_ready_tick >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && locked 8 && ! locked 7 && grep -q "move PVTI_8 Building" "$TMP/writes" && ! grep -q "move PVTI_7 " "$TMP/writes" \
  && [ "$(grep -c '^mark ' "$TMP/wo-calls" 2>/dev/null)" = 1 ] && [ "${ACTIVE_WORKERS:-0}" = 1 ] \
  && ok "T10 #7 held (waiting-on), #8 dispatched in the same tick, ACTIVE_WORKERS=1" \
  || fail "T10 rc=$rc lock7=$(locked 7 && echo y || echo n) lock8=$(locked 8 && echo y || echo n) writes=$(tr '\n' '|' < "$TMP/writes") active=${ACTIVE_WORKERS:-}"
grep -q -- "--issues 7$" "$TMP/deps-calls" 2>/dev/null && grep -q -- "--issues 8$" "$TMP/deps-calls" 2>/dev/null \
  && ok "  … deps asked for #7 then #8" || fail "  deps calls: $(cat "$TMP/deps-calls" 2>/dev/null)"

# ── T11. thẻ Ready nhãn qa: đòi deps-calls vắng
reset; PROJECT_ITEMS_JSON="{\"items\":[$(card 7 '"qa"')]}"; QA_FREE=1
dispatch_ready_tick >/dev/null 2>&1
( dispatch_lane qa 7 ) >/dev/null 2>&1
[ ! -e "$TMP/deps-calls" ] && [ ! -e "$TMP/wo-calls" ] && ok "T11 qa-labelled Ready card (qa lane): deps never called" \
  || fail "T11 deps called for a qa card: $(cat "$TMP/deps-calls" 2>/dev/null)"

sleep 0.3
[ "$FAILS" -eq 0 ] && { echo "PASS test_dependency_unblock_v1"; exit 0; }
echo "FAIL test_dependency_unblock_v1 ($FAILS)"; exit 1
