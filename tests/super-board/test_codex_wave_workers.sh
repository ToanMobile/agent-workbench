#!/usr/bin/env bash
# Test (T0052, H2): số worker của super-board-codex-wave.sh lấy từ nguồn sức chứa chung (super-board-capacity.py build_workers):
#  - max_workers 0 (hoặc vắng) → đúng trần capacity; max_workers > 0 → min(max_workers, capacity) (throttle vẫn hạ được);
#  - capacity vắng / lỗi / in rác / in số ≤ 0 → hành vi cũ: max_workers 0 = max(1, min(16, cpu − 2)), max_workers > 0 dùng nguyên
#    (không kẹp về công thức cũ), exit 0, KHÔNG thành lỗi argparse (exit 2); cảnh báo nêu mã thoát của capacity;
#  - không đặt SB_CAPACITY: dùng super-board-capacity.py nằm cạnh script, với SB_REPO_PATH = gốc repo của wave.
# Chạy offline: bản sao script trong thư mục tạm cạnh các stub (verification-ready, skills-ready, codex-lane); stub lane ghi số lane
# đang chạy cùng lúc. Thẻ ở cột QA: hàm grade() của wave trả ngay khi status khác Ready (xem grade() trong super-board-codex-wave.sh).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_* / DEVKIT_CAPACITY* của người gọi
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-codex-wave.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/caps"
cp "$ROOT/.claude/bin/super-board-codex-wave.sh" "$TMP/bin/"
printf 'import sys\nsys.exit(0)\n' > "$TMP/bin/super-board-verification-ready.py"
cat > "$TMP/bin/super-board-skills-ready.py" <<'PY'
def hydrate(cards, root):
    return cards


def report(*args, **kwargs):
    return {"ready": True, "entries": []}
PY
# lane giả: hàng rào thay cho ngủ cố định (OCR 23/10: máy tải 45–100 thì lane khởi động trễ quá 0,6 s, đỉnh đo ra thấp hơn thật) —
# chờ tới khi số lane đang chạy đạt EXPECT (tối đa ~10 s), ghi số lane lúc vào, sau hàng rào và trước khi ra (bắt cả lane thừa).
cat > "$TMP/bin/super-board-codex-lane.sh" <<'SH'
mkdir "$CONC_DIR/$$"
count() { ls "$CONC_DIR" | wc -l | tr -d ' '; }
count >> "$RUN_LOG"
i=0
while [ "$(count)" -lt "${EXPECT:-1}" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
count >> "$RUN_LOG"
sleep 0.3
count >> "$RUN_LOG"
rmdir "$CONC_DIR/$$"
printf '{"status":"blocked","column":"QA","detail":"t"}\n'
SH
mk_cap() { printf '#!/bin/sh\n%s\n' "$2" > "$TMP/caps/$1"; chmod +x "$TMP/caps/$1"; }
mk_cap two 'echo 2'
mk_cap fail 'exit 3'
mk_cap junk 'echo abc'
mk_cap zero 'echo 0'
mk_cap neg 'echo -2'
git -C "$TMP/repo" init -q . 2>/dev/null
CARDS='[{"number":1,"status":"QA"},{"number":2,"status":"QA"},{"number":3,"status":"QA"},{"number":4,"status":"QA"},{"number":5,"status":"QA"},{"number":6,"status":"QA"}]'
RUN_N=0
wave() { # wave <max_workers> [VAR=giá trị]... → RC, PEAK, ERR
  local mw="$1"; shift
  RUN_N=$((RUN_N + 1))
  export RUN_LOG="$TMP/run.$RUN_N.log" CONC_DIR="$TMP/conc.$RUN_N"; mkdir -p "$CONC_DIR"; : > "$RUN_LOG"
  printf '{"max_workers": %s}\n' "$mw" > "$TMP/cfg.json"
  ( cd "$TMP/repo" && env "$@" bash "$TMP/bin/super-board-codex-wave.sh" --config "$TMP/cfg.json" --cards "$CARDS" --codex \
      >"$TMP/out.$RUN_N" 2>"$TMP/err.$RUN_N" ); RC=$?
  PEAK="$(sort -n "$RUN_LOG" | tail -1)"; ERR="$(tail -3 "$TMP/err.$RUN_N" | tr '\n' '|')"
}

wave 0 EXPECT=2 SB_CAPACITY="$TMP/caps/two"
[ "$RC" = 0 ] && [ "$PEAK" = 2 ] && ok "max_workers 0: số worker = capacity build_workers (2)" || fail "max_workers 0, capacity 2: rc=$RC peak=$PEAK err=$ERR"
wave 3 EXPECT=2 SB_CAPACITY="$TMP/caps/two"
[ "$RC" = 0 ] && [ "$PEAK" = 2 ] && ok "max_workers 3 > capacity 2: kẹp xuống 2 (min)" || fail "max_workers 3, capacity 2: rc=$RC peak=$PEAK err=$ERR"
wave 1 EXPECT=1 SB_CAPACITY="$TMP/caps/two"
[ "$RC" = 0 ] && [ "$PEAK" = 1 ] && ok "max_workers 1 < capacity 2: throttle vẫn hạ được (1)" || fail "max_workers 1, capacity 2: rc=$RC peak=$PEAK err=$ERR"
wave 0 EXPECT=3 SB_CAPACITY="$ROOT/.claude/bin/super-board-capacity.py" DEVKIT_CAPACITY_CORES=4 DEVKIT_CAPACITY_LOAD=0
[ "$RC" = 0 ] && [ "$PEAK" = 3 ] && ok "wrapper thật, 4 lõi: build_workers 3 → 3 worker" || fail "wrapper thật 4 lõi: rc=$RC peak=$PEAK err=$ERR"

# capacity hỏng: công thức cũ, không bao giờ thành lỗi argparse
FB="$(python3 -c 'import os; print(max(1, min(16, (os.cpu_count() or 2) - 2)))')"
WANT=$(( FB < 6 ? FB : 6 ))
cards_n() { python3 -c "import json,sys; print(json.dumps([{'number': i, 'status': 'QA'} for i in range(1, int(sys.argv[1]) + 1)]))" "$1"; }
# đúng WANT thẻ: một đợt duy nhất, hàng rào không bao giờ chờ một đợt cuối ít lane hơn EXPECT (OCR 23/10: 6 thẻ trên máy 6 lõi, FB 4,
# đợt cuối 2 lane chờ hết 10 s ở mỗi ca)
CARDS_SAVE="$CARDS"; CARDS="$(cards_n "$WANT")"; FAIL_RUN=""
for c in /nonexistent "$TMP/caps/fail" "$TMP/caps/junk" "$TMP/caps/zero" "$TMP/caps/neg"; do
  wave 0 EXPECT="$WANT" SB_CAPACITY="$c"
  [ "$c" = "$TMP/caps/fail" ] && FAIL_RUN="$RUN_N"
  if [ "$RC" = 0 ] && [ "$PEAK" = "$WANT" ] && ! grep -q 'error:' "$TMP/err.$RUN_N"; then ok "capacity $(basename "$c"): rơi về công thức cũ ($WANT worker), exit 0"
  else fail "capacity $(basename "$c"): rc=$RC peak=$PEAK (muốn $WANT) err=$ERR"; fi
done
CARDS="$CARDS_SAVE"
grep -q 'exit 3' "$TMP/err.$FAIL_RUN" && ok "capacity exit 3: cảnh báo nêu mã thoát (không phải lỗi int(''))" \
  || fail "capacity exit 3: cảnh báo không nêu mã thoát: $(tail -2 "$TMP/err.$FAIL_RUN" | tr '\n' '|')"

# capacity hỏng mà max_workers đã đặt (> công thức cũ): dùng nguyên max_workers như trước T0052, không kẹp về công thức cũ (OCR 23/10)
MW=$((FB + 2)); CARDS_SAVE="$CARDS"
CARDS="$(cards_n "$MW")"
wave "$MW" EXPECT="$MW" SB_CAPACITY=/nonexistent
[ "$RC" = 0 ] && [ "$PEAK" = "$MW" ] && ok "capacity vắng, max_workers $MW (> công thức cũ $FB): chạy đủ $MW worker" \
  || fail "capacity vắng, max_workers $MW: rc=$RC peak=$PEAK (muốn $MW) err=$ERR"
CARDS="$CARDS_SAVE"

# không đặt SB_CAPACITY: wrapper cạnh script, SB_REPO_PATH = gốc repo của wave (repo tạm có capacity.py của worktree này)
cp "$ROOT/.claude/bin/super-board-capacity.py" "$TMP/bin/"
mkdir -p "$TMP/repo/universal-agent-devkit/bin"; cp "$ROOT/universal-agent-devkit/bin/capacity.py" "$TMP/repo/universal-agent-devkit/bin/"
wave 0 -u SB_CAPACITY EXPECT=3 DEVKIT_CAPACITY_CORES=4 DEVKIT_CAPACITY_LOAD=0   # -u: SB_CAPACITY của người gọi không được lọt vào ca "vắng"
[ "$RC" = 0 ] && [ "$PEAK" = 3 ] && ok "không đặt SB_CAPACITY: dùng super-board-capacity.py cạnh script, dò capacity.py trong repo của wave" \
  || fail "SB_CAPACITY vắng: rc=$RC peak=$PEAK err=$ERR"

# max_workers sai vẫn bị từ chối như cũ (exit 2 của argparse)
wave '"x"' SB_CAPACITY="$TMP/caps/two"
[ "$RC" = 2 ] && grep -q 'max_workers must be a non-negative integer' "$TMP/err.$RUN_N" && ok "max_workers sai vẫn bị từ chối (exit 2)" || fail "max_workers sai: rc=$RC err=$ERR"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
