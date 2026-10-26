#!/usr/bin/env bash
# Test hồi quy T0056: hàng đợi gate toàn máy (heavy_slot pool 'gate', tối đa N = capacity gate_max; 12 lõi: 3).
# Mọi bình luận viết bằng tiếng Việt theo quy chuẩn dự án; tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
CLEAN_ENV="$DEVKIT_DIR/tests/lib/clean_git_env.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-gate-slot-queue.XXXXXX")"
HOLDERS=""
cleanup() {
  local p
  touch "$TMP/release" "$TMP/release1" "$TMP/release2" "$TMP/release3" 2>/dev/null || true
  for p in $HOLDERS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Kiểm tra hợp đồng clean_git_env.sh trước khi gỡ biến trong tiến trình test này (Bước 4)
clean_probe="$(env DEVKIT_GATE_SLOTS=9 DEVKIT_GATE_SLOT_WAIT_S=99 DEVKIT_GATE_SLOT_HELD=0 \
  bash -c '. "$1"; printf "%s|%s|%s" "${DEVKIT_GATE_SLOT_HELD:-}" "${DEVKIT_GATE_SLOTS-unset}" "${DEVKIT_GATE_SLOT_WAIT_S-unset}"' _ "$CLEAN_ENV")"
if [ "$clean_probe" = "1|unset|unset" ]; then
  ok "clean_git_env.sh: đặt DEVKIT_GATE_SLOT_HELD=1 và gỡ DEVKIT_GATE_SLOTS / DEVKIT_GATE_SLOT_WAIT_S"
else
  fail "clean_git_env.sh: nhận '$clean_probe', kỳ vọng '1|unset|unset'"
fi

# Gỡ mọi biến giữ hộ và biến sức chứa để test trực tiếp hàng đợi pool 'gate' trên thư mục khoá riêng
unset CLAUDE_PROJECT_DIR TARGET_DIR SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOTS DEVKIT_GATE_SLOT_WAIT_S \
      DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD DEVKIT_SLOT_ADVISORY_HELD
export WORKTREE_TRUNK_MODE=0
export VACUITY_REVERT=0
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
printf '0\n' > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_POLL_S=0.05
export DEVKIT_GATE_SLOTS=1
export DEVKIT_SENTINEL_MAX_S=999999999

# Tiện ích giữ khoá flock độc quyền trên file bất kỳ tới khi xuất hiện file tín hiệu nhả hoặc hết thời gian
hold_flock() {
  local lock_file="$1" ready_file="$2" rel_file="$3" max_s="${4:-30}"
  rm -f "$ready_file" "$rel_file"
  python3 - "$lock_file" "$ready_file" "$rel_file" "$max_s" <<'PY' &
import fcntl, os, sys, time
lock_file, ready_file, rel_file, max_s = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
os.makedirs(os.path.dirname(lock_file), exist_ok=True)
with open(lock_file, "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(ready_file, "w").close()
    end = time.monotonic() + max_s
    while time.monotonic() < end:
        if os.path.exists(rel_file):
            break
        time.sleep(0.03)
PY
  LAST_HOLDER=$!
  HOLDERS="$HOLDERS $LAST_HOLDER"
  local i=0
  while [ ! -f "$ready_file" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$ready_file" ] || { fail "thiết lập: không giữ được khoá $lock_file"; exit 1; }
}

release_flock() {
  local rel_file="$1" pid="${2:-}"
  touch "$rel_file"
  if [ -n "$pid" ]; then wait "$pid" 2>/dev/null || true; fi
}

R="$TMP/repo"
make_repo() {
  rm -rf "$R" && mkdir -p "$R/src" "$R/.agents"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  printf '.claude/\n' > "$R/.gitignore"
  printf '{"profile":"backend","lang":"vi"}\n' > "$R/.agents/active-profile.json"
  printf 'x = 1\n' > "$R/src/app.py"
  cat > "$R/run_suite.sh" <<SH
#!/usr/bin/env bash
echo ran >> "$TMP/ran"
exit 0
SH
  chmod +x "$R/run_suite.sh"
  cat > "$R/.agents/regression_matrix.active.json" <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-CORE","name":"core","command":"bash run_suite.sh"}]}]}
JSON
  git -C "$R" add -A && git -C "$R" commit -qm init
  printf 'x = 2\n' > "$R/src/app.py"
  rm -f "$TMP/ran"
}

rcpt_path() {
  echo "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
}

json_last() {
  python3 - "$1" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines() if l.startswith("{")]
if not lines:
    sys.exit(1)
d = json.loads(lines[-1])
print(json.dumps(d, ensure_ascii=False))
PY
}

# ── Ca (a): gate-1.lock đang bị giữ -> gate hết DEVKIT_GATE_SLOT_WAIT_S=1 thoát 4 BUSY, không chạy suite, không ghi/xoá biên nhận ──
make_repo
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/a1.out" 2>&1
rc=$?
if [ "$rc" -eq 4 ] && [ ! -f "$TMP/ran" ] && [ ! -e "$(rcpt_path "$R")" ]; then
  ok "ca (a1): slot gate bận quá hạn chờ -> exit 4, không chạy suite, không tạo full_pass.json"
else
  fail "ca (a1): rc=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no) rcpt=$([ -e "$(rcpt_path "$R")" ] && echo yes || echo no)"
fi
python3 - "$TMP/a1.out" <<'PY' && ok "ca (a1-json): JSON có exit_code=4, busy=true, busy_reason=gate_queue, nhãn suite BUSY và thông báo hàng đợi gate" \
  || fail "ca (a1-json): nội dung JSON/log không đúng: $(tail -6 "$TMP/a1.out")"
import json, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = [l for l in txt.splitlines() if l.startswith("{")]
assert lines, "thiếu dòng JSON"
d = json.loads(lines[-1])
assert d.get("exit_code") == 4, d
assert d.get("busy") is True, d
assert d.get("busy_reason") == "gate_queue", d
suites = d.get("regression_tests") or []
assert suites and all(t.get("status") == "UNTESTED" and t.get("label") == "BUSY" for t in suites), suites
# Phải là thông báo riêng của hàng đợi gate toàn máy, không phải câu khoá dự án TEST_RUN_LOCK_WAIT_S
assert "DEVKIT_GATE_SLOT_WAIT_S" in txt and "TEST_RUN_LOCK_WAIT_S" not in d.get("verdict", ""), d.get("verdict")
PY

# Ca (a1b): nếu trước đó đã có biên nhận hợp lệ (hoặc cũ), BUSY do hết giờ chờ slot gate giữ nguyên biên nhận từng byte
mkdir -p "$(dirname "$(rcpt_path "$R")")"
printf '{"exit":0,"fingerprint":"stale-fp","tested_at":1}\n' > "$(rcpt_path "$R")"
before_rcpt="$(cat "$(rcpt_path "$R")")"
DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/a1b.out" 2>&1
rc=$?
release_flock "$TMP/release" "$LAST_HOLDER"
if [ "$rc" -eq 4 ] && [ -f "$(rcpt_path "$R")" ] && [ "$(cat "$(rcpt_path "$R")")" = "$before_rcpt" ]; then
  ok "ca (a1b): BUSY do hàng đợi gate không xoá hay ghi đè full_pass.json sẵn có"
else
  fail "ca (a1b): rc=$rc biên nhận bị mất hoặc bị đổi"
fi
rm -f "$(rcpt_path "$R")"

# Ca (a3) (audit T0056 #1): slot hết hạn chờ ĐỒNG THỜI gate ra exit 2 (một file code ngoài mọi rule: "chưa có test hồi quy", nhánh
# exit 2 đứng trước nhánh BUSY) -> lock_busy từng chỉ bật ở nhánh BUSY, nên lượt không giữ khoá, không chạy suite nào vẫn ghi
# full_pass.json. Không lượt nào thiếu khoá được ghi biên nhận.
make_repo
mkdir -p "$R/lib" && printf 'y = 1\n' > "$R/lib/other.py"
git -C "$R" add -A && git -C "$R" commit -qm other
printf 'y = 2\n' > "$R/lib/other.py"
printf 'x = 3\n' > "$R/src/app.py"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/a3.out" 2>&1
rc=$?
release_flock "$TMP/release" "$LAST_HOLDER"
if [ "$rc" -ne 0 ] && [ ! -f "$TMP/ran" ] && [ ! -e "$(rcpt_path "$R")" ]; then
  ok "ca (a3): slot hết hạn chờ kèm exit $rc (file code chưa có test) -> không chạy suite, không tạo full_pass.json"
else
  fail "ca (a3): rc=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no) rcpt=$([ -e "$(rcpt_path "$R")" ] && echo yes || echo no)"
fi
make_repo   # ca (a2) cần repo sạch như sau ca (a1b)

# Ca (a2): tiến trình giữ nhả slot trước khi hết DEVKIT_GATE_SLOT_WAIT_S -> gate thứ N+1 xếp hàng chờ rồi chạy XANH
rm -f "$TMP/ran"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 0.45
DEVKIT_GATE_SLOT_WAIT_S=6 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/a2.out" 2>&1
rc=$?
wait "$LAST_HOLDER" 2>/dev/null || true
if [ "$rc" -eq 0 ] && [ -f "$TMP/ran" ] && [ -f "$(rcpt_path "$R")" ]; then
  ok "ca (a2): slot nhả trong thời gian chờ -> gate xếp hàng lấy được slot, chạy suite và ghi biên nhận (exit 0)"
else
  fail "ca (a2): rc=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no) log=$(tail -4 "$TMP/a2.out")"
fi

# ── Ca (b): không còn ai giữ slot -> gate chạy ngay và sau khi xong đã nhả khoá (try/finally) ──
make_repo
DEVKIT_GATE_SLOT_WAIT_S=2 CLAUDE_PROJECT_DIR="$R" \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/b.out" 2>&1
rc=$?
# Kiểm tra gate-1.lock hiện rảnh ngay lập tức (không rò khoá sau khi gate kết thúc)
python3 - "$SB_HEAVY_SLOT_DIR/gate-1.lock" <<'PY'
import fcntl, sys
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
PY
free_rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/ran" ] && [ -f "$(rcpt_path "$R")" ] && [ "$free_rc" -eq 0 ]; then
  ok "ca (b): không có tiến trình giữ -> gate chạy suite, ghi biên nhận và nhả gate-1.lock trong finally"
else
  fail "ca (b): rc=$rc free_rc=$free_rc"
fi

# Ca (b2): mặc định N lấy từ capacity.gate_max (12 lõi = 3) khi gỡ DEVKIT_GATE_SLOTS
make_repo
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/h1" "$TMP/release1" 30; H1=$LAST_HOLDER
hold_flock "$SB_HEAVY_SLOT_DIR/gate-2.lock" "$TMP/h2" "$TMP/release2" 30; H2=$LAST_HOLDER
( unset DEVKIT_GATE_SLOTS; DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0 DEVKIT_GATE_SLOT_WAIT_S=1 \
    CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 python3 "$GATE" --run-tests --full --no-checklist ) >"$TMP/b2_ok.out" 2>&1
rc_2of3=$?
rm -f "$TMP/ran" "$(rcpt_path "$R")"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-3.lock" "$TMP/h3" "$TMP/release3" 30; H3=$LAST_HOLDER
( unset DEVKIT_GATE_SLOTS; DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0 DEVKIT_GATE_SLOT_WAIT_S=1 \
    CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 python3 "$GATE" --run-tests --full --json --no-checklist ) >"$TMP/b2_busy.out" 2>&1
rc_3of3=$?
release_flock "$TMP/release1" "$H1"; release_flock "$TMP/release2" "$H2"; release_flock "$TMP/release3" "$H3"
if [ "$rc_2of3" -eq 0 ] && [ "$rc_3of3" -eq 4 ] && [ ! -f "$TMP/ran" ]; then
  ok "ca (b2): gỡ DEVKIT_GATE_SLOTS trên 12 lõi -> mặc định 3 slot (2 bận vẫn chạy ở slot 3, đủ 3 bận thì gate thứ 4 exit 4 BUSY)"
else
  fail "ca (b2): rc_2of3=$rc_2of3 (muốn 0), rc_3of3=$rc_3of3 (muốn 4)"
fi

# ── Ca (c): DEVKIT_GATE_SLOT_HELD=1 -> gate lồng không chờ slot kể cả khi gate-1.lock đang khoá ──
make_repo
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
DEVKIT_GATE_SLOT_HELD=1 DEVKIT_GATE_SLOT_WAIT_S=0.2 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/c1.out" 2>&1
rc=$?
release_flock "$TMP/release" "$LAST_HOLDER"
if [ "$rc" -eq 0 ] && [ -f "$TMP/ran" ]; then
  ok "ca (c1): DEVKIT_GATE_SLOT_HELD=1 -> bỏ qua hàng đợi slot, chạy ngay (exit 0)"
else
  fail "ca (c1): rc=$rc log=$(tail -4 "$TMP/c1.out")"
fi

# Ca (c2): gate cha giữ slot duy nhất (DEVKIT_GATE_SLOTS=1) và chạy suite gọi gate con -> gate con kế thừa DEVKIT_GATE_SLOT_HELD=1 qua suite_env(), không tự khoá cứng chính mình; đồng thời run_brief khôi phục os.environ sau khi xong
R_CHILD="$TMP/repo_child"
mkdir -p "$R_CHILD/src" "$R_CHILD/.agents"
git -C "$R_CHILD" init -q -b main && git -C "$R_CHILD" config user.email t@example.invalid && git -C "$R_CHILD" config user.name t
printf '{"profile":"backend","lang":"vi"}\n' > "$R_CHILD/.agents/active-profile.json"
printf 'y = 1\n' > "$R_CHILD/src/c.py"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R_CHILD/ok.sh" && chmod +x "$R_CHILD/ok.sh"
cat > "$R_CHILD/.agents/regression_matrix.active.json" <<'JSON'
{"project":"child","rules":[{"component":"C","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-CHILD","name":"child","command":"bash ok.sh"}]}]}
JSON
git -C "$R_CHILD" add -A && git -C "$R_CHILD" commit -qm init
printf 'y = 2\n' > "$R_CHILD/src/c.py"

make_repo
cat > "$R/run_suite.sh" <<SH
#!/usr/bin/env bash
printf '%s' "\${DEVKIT_GATE_SLOT_HELD:-unset}" > "$TMP/child_held_seen"
CLAUDE_PROJECT_DIR="$R_CHILD" DEVKIT_GATE_SLOT_WAIT_S=0.3 python3 "$GATE" --run-tests --full --no-checklist
SH
chmod +x "$R/run_suite.sh"
git -C "$R" add run_suite.sh && git -C "$R" commit -qm "nested suite"
printf 'x = 3\n' > "$R/src/app.py"
DEVKIT_GATE_SLOT_WAIT_S=2 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/c2.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$TMP/child_held_seen" 2>/dev/null)" = "1" ]; then
  ok "ca (c2): suite con nhận DEVKIT_GATE_SLOT_HELD=1 từ gate cha và chạy gate lồng không bị tự chặn trên DEVKIT_GATE_SLOTS=1"
else
  fail "ca (c2): rc=$rc child_held='$(cat "$TMP/child_held_seen" 2>/dev/null)' log=$(tail -6 "$TMP/c2.out")"
fi

# ── Ca (d): DEVKIT_GATE_SLOTS=0 tắt hàng đợi, không lấy slot và không tạo gate-*.lock ──
make_repo
EMPTY_SLOTS="$TMP/empty_slots"; mkdir -p "$EMPTY_SLOTS"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
DEVKIT_GATE_SLOTS=0 DEVKIT_GATE_SLOT_WAIT_S=0.2 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/d1.out" 2>&1
rc1=$?
release_flock "$TMP/release" "$LAST_HOLDER"
rm -f "$TMP/ran" "$(rcpt_path "$R")"
SB_HEAVY_SLOT_DIR="$EMPTY_SLOTS" DEVKIT_GATE_SLOTS=0 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/d2.out" 2>&1
rc2=$?
gate_locks="$(ls "$EMPTY_SLOTS"/gate-*.lock 2>/dev/null || true)"
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -z "$gate_locks" ]; then
  ok "ca (d): DEVKIT_GATE_SLOTS=0 tắt hàng đợi (chạy qua khi slot bận, không tạo file gate-*.lock)"
else
  fail "ca (d): rc1=$rc1 rc2=$rc2 locks='$gate_locks'"
fi

# ── Ca (e): không có suite cần chạy (dùng lại biên nhận full_pass.json, hoặc dry-run không --run-tests) -> không lấy slot ──
make_repo
CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --full --no-checklist >"$TMP/e_seed.out" 2>&1
rm -f "$TMP/ran"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
DEVKIT_GATE_SLOT_WAIT_S=0.2 CLAUDE_PROJECT_DIR="$R" \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/e_reuse.out" 2>&1
rc_reuse=$?
DEVKIT_GATE_SLOT_WAIT_S=0.2 CLAUDE_PROJECT_DIR="$R" \
  python3 "$GATE" --json --no-checklist >"$TMP/e_dry.out" 2>&1
rc_dry=$?
release_flock "$TMP/release" "$LAST_HOLDER"
if [ "$rc_reuse" -eq 0 ] && [ ! -f "$TMP/ran" ] && [ "$rc_dry" -eq 2 ]; then
  ok "ca (e): dùng lại biên nhận (exit 0) và dry-run không --run-tests (exit 2) không xin slot khi gate-1.lock đang bận"
else
  fail "ca (e): rc_reuse=$rc_reuse rc_dry=$rc_dry ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
fi

# ── Ca (e2, phản biện vòng 2 mục 1): kiểm lại biên nhận & suite_cache SAU khi chờ lấy được slot ──
# (e2.1) Trong lúc gate B chờ gate-1.lock, một lượt khác ghi xong full_pass.json của đúng cây đó -> B lấy được slot thì dùng lại biên nhận, không chạy suite; nhưng nếu B có --no-cache thì B PHẢI chạy suite
make_repo
# Tạo sẵn bản sao biên nhận thật của cây hiện tại rồi xoá để cấy lại trong lúc B đang xếp hàng
CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 python3 "$GATE" --run-tests --full --no-checklist >/dev/null 2>&1
cp "$(rcpt_path "$R")" "$TMP/saved_rcpt.json"
rm -f "$(rcpt_path "$R")" "$TMP/ran"

hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
(
  sleep 0.25
  mkdir -p "$(dirname "$(rcpt_path "$R")")"
  cp "$TMP/saved_rcpt.json" "$(rcpt_path "$R")"
  sleep 0.1
  touch "$TMP/release"
) &
PLANTER=$!
DEVKIT_GATE_SLOT_WAIT_S=6 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/e2_rcpt.out" 2>&1
rc_recheck=$?
wait "$PLANTER" 2>/dev/null || true; wait "$LAST_HOLDER" 2>/dev/null || true
if [ "$rc_recheck" -eq 0 ] && [ ! -f "$TMP/ran" ]; then
  ok "ca (e2.1a): biên nhận xuất hiện trong lúc chờ slot -> lấy được slot thì dùng lại ngay, không chạy lại suite"
else
  fail "ca (e2.1a): rc=$rc_recheck ran=$([ -f "$TMP/ran" ] && echo yes || echo no) log=$(tail -5 "$TMP/e2_rcpt.out")"
fi

# Cùng kịch bản nhưng có --no-cache: không được lén dùng lại biên nhận (phải chắn if use_cache)
rm -f "$(rcpt_path "$R")" "$TMP/ran"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
(
  sleep 0.25
  mkdir -p "$(dirname "$(rcpt_path "$R")")"
  cp "$TMP/saved_rcpt.json" "$(rcpt_path "$R")"
  sleep 0.1
  touch "$TMP/release"
) &
PLANTER=$!
DEVKIT_GATE_SLOT_WAIT_S=6 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --no-cache --no-checklist >"$TMP/e2_nocache.out" 2>&1
rc_nocache=$?
wait "$PLANTER" 2>/dev/null || true; wait "$LAST_HOLDER" 2>/dev/null || true
if [ "$rc_nocache" -eq 0 ] && [ -f "$TMP/ran" ]; then
  ok "ca (e2.1b): --no-cache chắn reuse_full_pass sau khi chờ slot -> vẫn chạy thật suite (exit 0)"
else
  fail "ca (e2.1b): rc=$rc_nocache ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
fi

# (e2.2) Trong lúc worktree B (đã từng chạy gate nên không mượn biên nhận anh em) chờ gate-1.lock, worktree A chạy xong và ghi suite_cache -> B lấy được slot thì gọi mark_keyed, không chạy suite lần 2 và ra exit 0 (không bị NOT_RUN -> exit 1)
R_SC="$TMP/repo_sc"
WT_B="$TMP/wt_b"
mkdir -p "$R_SC/src" "$R_SC/.agents"
git -C "$R_SC" init -q -b main && git -C "$R_SC" config user.email t@example.invalid && git -C "$R_SC" config user.name t
printf '.claude/\n' > "$R_SC/.gitignore"
printf '{"profile":"backend","lang":"vi"}\n' > "$R_SC/.agents/active-profile.json"
printf 'v = 1\n' > "$R_SC/src/m.py"
cat > "$R_SC/suite_sc.sh" <<SH
#!/usr/bin/env bash
echo run >> "\$PWD/.claude/sc_ran"
exit 0
SH
chmod +x "$R_SC/suite_sc.sh"
cat > "$R_SC/.agents/regression_matrix.active.json" <<'JSON'
{"project":"sc","rules":[{"component":"M","watch_files":["src/m.py"],
 "mandatory_regression_tests":[{"id":"REG-SC","name":"sc","command":"bash suite_sc.sh"}]}]}
JSON
git -C "$R_SC" add -A && git -C "$R_SC" commit -qm init
git -C "$R_SC" worktree add -q --detach "$WT_B" HEAD
# Cho WT_B từng chạy gate một lần trên nội dung khác để _ever_gated(WT_B) == True (tắt mượn sibling receipt, chỉ còn suite_cache)
printf 'v = 99\n' > "$WT_B/src/m.py"
DEVKIT_GATE_SLOT_HELD=1 DEVKIT_SUITE_CACHE=0 CLAUDE_PROJECT_DIR="$WT_B" \
  python3 "$GATE" --run-tests --full --no-checklist >/dev/null 2>&1
rm -f "$(rcpt_path "$WT_B")" "$WT_B/.claude/sc_ran"
# Đặt cả R_SC và WT_B về cùng nội dung mới v = 2 (chưa có trong suite_cache)
printf 'v = 2\n' > "$R_SC/src/m.py"
printf 'v = 2\n' > "$WT_B/src/m.py"

hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
# Khởi chạy gate trên WT_B trong nền: lúc này suite_cache lạnh nên B sẽ xếp hàng chờ gate-1.lock
(
  DEVKIT_GATE_SLOT_WAIT_S=10 DEVKIT_SUITE_CACHE=1 CLAUDE_PROJECT_DIR="$WT_B" \
    python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/e2_wtb.out" 2>&1
  echo $? > "$TMP/e2_wtb.rc"
) &
WTB_PID=$!
sleep 0.35
# Trong lúc WT_B đang chờ slot, R_SC chạy thật (với DEVKIT_GATE_SLOT_HELD=1) để nạp khoá nội dung vào suite_cache chung
DEVKIT_GATE_SLOT_HELD=1 DEVKIT_SUITE_CACHE=1 CLAUDE_PROJECT_DIR="$R_SC" \
  python3 "$GATE" --run-tests --full --no-checklist >"$TMP/e2_rsc.out" 2>&1
rc_rsc=$?
release_flock "$TMP/release" "$LAST_HOLDER"
wait "$WTB_PID" 2>/dev/null || true
rc_wtb="$(cat "$TMP/e2_wtb.rc" 2>/dev/null || echo 99)"
if [ "$rc_rsc" -eq 0 ] && [ "$rc_wtb" -eq 0 ] && [ -f "$R_SC/.claude/sc_ran" ] && [ ! -f "$WT_B/.claude/sc_ran" ]; then
  ok "ca (e2.2): suite_cache được nạp trong lúc chờ slot -> WT_B gọi mark_keyed, không chạy lại suite và trả exit 0"
else
  fail "ca (e2.2): rc_rsc=$rc_rsc rc_wtb=$rc_wtb wtb_ran=$([ -f "$WT_B/.claude/sc_ran" ] && echo yes || echo no) log=$(tail -6 "$TMP/e2_wtb.out")"
fi

# ── Ca (f): thông báo BUSY của khoá dự án (test_run.lock) giữ nguyên từng chữ (cả vi và en), busy_reason == project_lock ──
make_repo
hold_flock "$R/.claude/audit-gate/test_run.lock" "$TMP/p_held" "$TMP/p_release" 30
TEST_RUN_LOCK_WAIT_S=0.4 DEVKIT_LANG=vi CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/f_vi.out" 2>&1
rc_vi=$?
TEST_RUN_LOCK_WAIT_S=0.4 DEVKIT_LANG=en CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/f_en.out" 2>&1
rc_en=$?
release_flock "$TMP/p_release" "$LAST_HOLDER"
python3 - "$TMP/f_vi.out" "$TMP/f_en.out" "$rc_vi" "$rc_en" <<'PY' \
  && ok "ca (f): thông báo BUSY của khoá dự án (vi + en) giữ nguyên từng chữ và busy_reason == project_lock" \
  || fail "ca (f): thông báo khoá dự án bị lệch"
import json, sys
vi_txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
en_txt = open(sys.argv[2], encoding="utf-8", errors="replace").read()
assert int(sys.argv[3]) == 4 and int(sys.argv[4]) == 4
d_vi = json.loads([l for l in vi_txt.splitlines() if l.startswith("{")][-1])
d_en = json.loads([l for l in en_txt.splitlines() if l.startswith("{")][-1])
assert d_vi["verdict"] == "UNTESTED — một lượt chạy test khác đang giữ khoá dự án (TEST_RUN_LOCK_WAIT_S) — chạy lại sau; KHÔNG phải PASS", d_vi["verdict"]
assert d_en["verdict"] == "UNTESTED — another test run holds the project lock (TEST_RUN_LOCK_WAIT_S) — run again later; NOT a PASS", d_en["verdict"]
assert d_vi["regression_tests"][0]["output_tail"] == "Một lượt chạy test khác giữ khoá dự án quá TEST_RUN_LOCK_WAIT_S — không chạy song song (Gradle ghi đè build/test-results)"
assert d_en["regression_tests"][0]["output_tail"] == "Another test run held the project lock past TEST_RUN_LOCK_WAIT_S — not run side by side (Gradle corrupts build/test-results)"
assert d_vi.get("busy_reason") == "project_lock" and d_en.get("busy_reason") == "project_lock", (d_vi.get("busy_reason"), d_en.get("busy_reason"))
PY

# ── Ca (g): suite_env() giữ nguyên DEVKIT_GATE_SLOT_HELD và khối try/finally khôi phục biến môi trường trong cùng tiến trình ──
python3 - "$GATE" "$R" <<'PY' \
  && ok "ca (g): suite_env() giữ DEVKIT_GATE_SLOT_HELD và main() khôi phục biến này về giá trị cũ trong finally" \
  || fail "ca (g): suite_env() hoặc khôi phục DEVKIT_GATE_SLOT_HELD bị lỗi"
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
os.environ["DEVKIT_GATE_SLOT_HELD"] = "1"
env = mod.suite_env()
assert env.get("DEVKIT_GATE_SLOT_HELD") == "1", env.get("DEVKIT_GATE_SLOT_HELD")
del os.environ["DEVKIT_GATE_SLOT_HELD"]
assert "DEVKIT_GATE_SLOT_HELD" not in mod.suite_env()
# audit T0056 (INSTINCT-046): núm của MỘT lần gate (số slot, thời gian chờ — Stop hook đặt 45 s) không lọt xuống suite
os.environ["DEVKIT_GATE_SLOTS"] = "0"; os.environ["DEVKIT_GATE_SLOT_WAIT_S"] = "45"
env = mod.suite_env()
assert "DEVKIT_GATE_SLOTS" not in env and "DEVKIT_GATE_SLOT_WAIT_S" not in env, (env.get("DEVKIT_GATE_SLOTS"), env.get("DEVKIT_GATE_SLOT_WAIT_S"))
PY

# ── Ca (h): Stop hook (hooks/regression_gate.sh) truyền DEVKIT_GATE_SLOT_WAIT_S=45, BUSY giữ exit 0 UNTESTED và đúng 1 dòng JSON ──
H_REPO="$TMP/hook_repo"
mkdir -p "$H_REPO/src" "$H_REPO/.agents"
git -C "$H_REPO" init -q -b main && git -C "$H_REPO" config user.email t@example.invalid && git -C "$H_REPO" config user.name t
printf '.claude/\n' > "$H_REPO/.gitignore"
printf 'z = 1\n' > "$H_REPO/src/Core.kt"
cat > "$H_REPO/probe_wait.sh" <<SH
#!/usr/bin/env bash
printf '%s' "\${DEVKIT_GATE_SLOT_WAIT_S:-unset}" > "$TMP/hook_wait_seen"
exit 0
SH
chmod +x "$H_REPO/probe_wait.sh"
cat > "$H_REPO/.agents/regression_matrix.active.json" <<'JSON'
{"project":"h","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-H","name":"core","command":"bash probe_wait.sh"}]}]}
JSON
git -C "$H_REPO" add -A && git -C "$H_REPO" commit -qm init
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix"},"uuid":"u1","sessionId":"s-h1"}' > "$TMP/h.jsonl"
PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"session_id":"s-h1","hook_event_name":"Stop","transcript_path":sys.argv[1]}))' "$TMP/h.jsonl")"

# (h1) Khi slot rảnh và không truyền DEVKIT_GATE_SLOT_WAIT_S -> hook truyền mặc định 45 xuống gate. Quan sát ở CHÍNH gate (suite_env
# bỏ biến này khỏi suite, INSTINCT-046): bản chép của hook trong một kit tạm tìm gate ở <kit>/bin/post-fix-gate.py = trình bọc ghi
# biến rồi exec gate thật.
mkdir -p "$TMP/kit/hooks" "$TMP/kit/bin"
cp "$HOOK" "$TMP/kit/hooks/regression_gate.sh"
[ -f "$DEVKIT_DIR/hooks/devkit_harness.py" ] && cp "$DEVKIT_DIR/hooks/devkit_harness.py" "$TMP/kit/hooks/"
cat > "$TMP/kit/bin/post-fix-gate.py" <<PY
import os, sys
open("$TMP/hook_wait_gate", "w").write(os.environ.get("DEVKIT_GATE_SLOT_WAIT_S", "unset"))
os.execv(sys.executable, [sys.executable, "$GATE"] + sys.argv[1:])
PY
printf 'z = 2\n' > "$H_REPO/src/Core.kt"
rm -f "$TMP/hook_wait_seen" "$TMP/hook_wait_gate"
printf '%s' "$PAYLOAD" | ( unset DEVKIT_GATE_SLOT_WAIT_S; CLAUDE_PROJECT_DIR="$H_REPO" bash "$TMP/kit/hooks/regression_gate.sh" ) >"$TMP/h1.out" 2>"$TMP/h1.err"
h1_rc=$?
if [ "$h1_rc" -eq 0 ] && [ "$(cat "$TMP/hook_wait_gate" 2>/dev/null)" = "45" ] && [ "$(cat "$TMP/hook_wait_seen" 2>/dev/null)" = "unset" ]; then
  ok "ca (h1): Stop hook truyền mặc định DEVKIT_GATE_SLOT_WAIT_S=45 xuống gate, và biến không lọt xuống suite"
else
  fail "ca (h1): rc=$h1_rc gate='$(cat "$TMP/hook_wait_gate" 2>/dev/null)' suite='$(cat "$TMP/hook_wait_seen" 2>/dev/null)' err='$(cat "$TMP/h1.err")'"
fi

# (h2) Khi hàng đợi gate bận (busy_reason == gate_queue) -> exit 0, không cache pass_fp/untested_fp, stdout đúng 1 JSON object chứa nguyên văn câu gốc + dòng nối thêm
printf 'z = 3\n' > "$H_REPO/src/Core.kt"
rm -f "$TMP/hook_wait_seen"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" 30
printf '%s' "$PAYLOAD" | DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$H_REPO" bash "$HOOK" >"$TMP/h2.out" 2>"$TMP/h2.err"
h2_rc=$?
release_flock "$TMP/release" "$LAST_HOLDER"
python3 - "$TMP/h2.out" "$TMP/h2.err" "$H_REPO/.claude/audit-gate/regression_gate.state.json" "$h2_rc" <<'PY' \
  && [ ! -f "$TMP/hook_wait_seen" ] \
  && ok "ca (h2): Stop hook gặp gate_queue -> exit 0, đúng 1 JSON object, giữ nguyên câu gốc + dòng hàng đợi, không cache PASS giả" \
  || fail "ca (h2): rc=$h2_rc out='$(cat "$TMP/h2.out")' err='$(cat "$TMP/h2.err")'"
import json, os, sys
raw_out = open(sys.argv[1], encoding="utf-8").read()
raw_err = open(sys.argv[2], encoding="utf-8").read()
state_path = sys.argv[3]
rc = int(sys.argv[4])
assert rc == 0 and raw_err == "", (rc, raw_err)
non_empty = [l for l in raw_out.splitlines() if l.strip()]
assert len(non_empty) == 1, f"stdout phải là đúng 1 dòng JSON, nhận {len(non_empty)}: {non_empty!r}"
obj = json.loads(non_empty[0])
msg = obj.get("systemMessage", "")
orig = ("Regression gate UNTESTED — một lượt chạy test khác đang giữ khoá dự án — chạy lại sau "
        "(.claude/audit-gate/test_run.lock); test hồi quy CHƯA chạy, KHÔNG phải PASS.")
assert msg.startswith(orig + "\n"), f"systemMessage thiếu câu gốc hoặc dòng nối: {msg!r}"
extra_line = msg[len(orig) + 1:]
assert extra_line and "\n" not in extra_line and ("gate" in extra_line.lower()), f"dòng nối thêm không hợp lệ: {extra_line!r}"
if os.path.exists(state_path):
    st = json.load(open(state_path, encoding="utf-8"))
    # Cây z=3 mới sửa chưa được phép lưu vào pass_fp hay untested_fp
    sess = (st.get("sessions") or {}).get("s-h1") or {}
    assert sess.get("result") not in ("pass", "untested"), st
PY

# (h3) Đối chứng: khi khoá dự án test_run.lock bận (busy_reason == project_lock) -> systemMessage giữ nguyên đúng câu gốc 1 dòng (không nối dòng hàng đợi)
printf 'z = 4\n' > "$H_REPO/src/Core.kt"
hold_flock "$H_REPO/.claude/audit-gate/test_run.lock" "$TMP/hp_held" "$TMP/hp_release" 30
printf '%s' "$PAYLOAD" | TEST_RUN_LOCK_WAIT_S=0.5 CLAUDE_PROJECT_DIR="$H_REPO" bash "$HOOK" >"$TMP/h3.out" 2>"$TMP/h3.err"
h3_rc=$?
release_flock "$TMP/hp_release" "$LAST_HOLDER"
python3 - "$TMP/h3.out" "$h3_rc" <<'PY' \
  && ok "ca (h3): Stop hook gặp project_lock -> systemMessage đúng nguyên bản không thêm dòng hàng đợi" \
  || fail "ca (h3): rc=$h3_rc out='$(cat "$TMP/h3.out")'"
import json, sys
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
assert int(sys.argv[2]) == 0 and len(lines) == 1
orig = ("Regression gate UNTESTED — một lượt chạy test khác đang giữ khoá dự án — chạy lại sau "
        "(.claude/audit-gate/test_run.lock); test hồi quy CHƯA chạy, KHÔNG phải PASS.")
assert json.loads(lines[0]).get("systemMessage") == orig, lines[0]
PY

echo
if [ "$FAILS" -eq 0 ]; then
  echo "✅ test_gate_slot_queue: tất cả PASS"
  exit 0
fi
echo "❌ test_gate_slot_queue: $FAILS lỗi"
exit 1
