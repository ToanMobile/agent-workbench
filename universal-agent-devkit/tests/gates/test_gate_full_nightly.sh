#!/usr/bin/env bash
# Test hồi quy (#644): lượt --full đêm tách khỏi merge/push — bin/gate_full.py chạy gate full trên origin/main trong scratch tách rời,
# bin/gate-full-schedule.sh cài LaunchAgent 00:00. Repo giả có remote giả, gate giả (DEVKIT_GATE_FULL_CMD), lệnh tạo thẻ giả
# (DEVKIT_GATE_FULL_CARD_CMD), gh giả đầu PATH, launchctl giả (DEVKIT_LAUNCHCTL): không chạm GitHub, launchd hay ~/Library.
#   a. gate xanh ⇒ nightly/full_pass.json + last_full_green_sha = sha của ref + summary-latest.md + history.jsonl;
#   b. gate đỏ ⇒ bisect trên chuỗi merge first-parent last_green..ref ra ĐÚNG merge làm vỡ test, lệnh tạo thẻ nhận sha đó;
#      last_full_green_sha giữ nguyên;
#   c. khoá do pid còn sống giữ ⇒ "skip", exit 0, gate không chạy; pid đã chết ⇒ chiếm lại khoá và chạy;
#   d. tải giả cao hơn hold_load ⇒ chờ tới --max-wait-s rồi vẫn chạy, summary ghi lý do;
#   e. schedule install vào thư mục tạm ⇒ plist hợp lệ (plutil -lint), Hour 0, /usr/bin/nice -n 10, python3 tuyệt đối,
#      TZ Asia/Ho_Chi_Minh, launchctl giả nhận bootout rồi bootstrap gui/<uid>; uninstall gỡ plist;
#      mỗi repo một lịch: install repo A rồi repo B (cùng tên thư mục) ⇒ hai plist, hai label, hai thư mục log, không bootout lịch A;
#      uninstall --repo A chỉ gỡ A.
# Mọi ca: scratch gate-full-scratch-* đã gỡ (thư mục lẫn `git worktree list`), khoá đã nhả.
# Chưa có bin/gate_full.py / bin/gate-full-schedule.sh thì ĐỎ. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
SCHED="$DEVKIT_DIR/bin/gate-full-schedule.sh"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-nightly.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"   # TMPDIR có "/" cuối thì mktemp cho "//": so chuỗi đường dẫn với `cd && pwd` của script
SLEEP_PID=""
cleanup() { [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

for f in "$GF" "$SCHED"; do
  [ -f "$f" ] || { echo "✖ không có ${f#$DEVKIT_DIR/}: chưa có lượt --full đêm"; exit 1; }
done

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# --- repo giả: base (xanh) rồi 6 merge --no-ff; merge của f4 làm vỡ tests/check.sh -------------------------------------------
g init -q --bare "$T/origin.git"
g init -q "$T/seed"
mkdir -p "$T/seed/tests"
printf 'ok\n' >"$T/seed/src.txt"
printf '#!/bin/sh\n! grep -q BROKEN src.txt\n' >"$T/seed/tests/check.sh"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
BASE="$(git -C "$T/seed" rev-parse HEAD)"
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main:main main:green
for i in 1 2 3 4 5 6; do
  g -C "$T/seed" checkout -qb "f$i" main
  printf '%s\n' "$i" >"$T/seed/f$i.txt"
  [ "$i" = 4 ] && printf 'BROKEN\n' >>"$T/seed/src.txt"
  g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "feat f$i"
  g -C "$T/seed" checkout -q main
  g -C "$T/seed" merge -q --no-ff -m "Merge branch 'f$i'" "f$i"
done
g -C "$T/seed" push -q origin main
BAD_MERGE="$(git -C "$T/seed" log --first-parent --merges --format='%H %s' | awk '/f4/ {print $1}')"
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"

# --- gate giả / thẻ giả / gh giả -------------------------------------------------------------------------------------------
cat >"$T/fakegate.sh" <<'SH'
#!/bin/sh
# gate giả: chạy tests/check.sh trên cây scratch; xanh ghi full_pass.json vào git dir của scratch như post-fix-gate
echo "$(pwd -P)" >>"$FAKE_CALLS"
case "${FAKE_MODE:-}" in
  timeout) echo '{"verdict": "UNTESTED", "exit_code": 2, "busy": false, "regression_tests": [{"id": "REG-SLOW-01", "status": "TIMEOUT", "command": "sleep 5"}]}'; exit 2 ;;
  slowred) echo '{"verdict": "FAIL", "exit_code": 1, "regression_tests": [{"id": "REG-SLOW-01", "status": "FAIL", "command": "sleep 5"}]}'; exit 1 ;;
esac
if sh tests/check.sh; then
  d="$(git rev-parse --absolute-git-dir)/postfix-gate"; mkdir -p "$d"
  echo '{"fake": "pass"}' >"$d/full_pass.json"
  echo '{"verdict": "PASS", "exit_code": 0, "regression_tests": [{"id": "REG-FAKE-01", "status": "PASS", "command": "sh tests/check.sh"}]}'
  exit 0
fi
echo "✖ REG-FAKE-01 đỏ"
echo '{"verdict": "FAIL", "exit_code": 1, "regression_tests": [{"id": "REG-FAKE-01", "status": "FAIL", "command": "sh tests/check.sh"}]}'
exit 1
SH
cat >"$T/fakecard.sh" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"$FAKE_CARD_ARGS"
echo "Created https://github.com/fake/repo/issues/99"
SH
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "$@" >>"%s/gh.calls"\necho "[]"\n' "$T" >"$T/bin/gh"
chmod +x "$T/fakegate.sh" "$T/fakecard.sh" "$T/bin/gh"

export PATH="$T/bin:$PATH" FAKE_CALLS="$T/gate.calls" FAKE_CARD_ARGS="$T/card.args"
export DEVKIT_GATE_FULL_CMD="sh $T/fakegate.sh" DEVKIT_GATE_FULL_CARD_CMD="sh $T/fakecard.sh"
export DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0

no_scratch() {   # scratch đã gỡ: không thư mục, không mục worktree, không khoá
  ! ls -d "$COMMON"/postfix-gate/gate-full-scratch-* >/dev/null 2>&1 \
    && ! git -C "$T/repo" worktree list --porcelain | grep -q gate-full-scratch \
    && [ ! -e "$COMMON/postfix-gate/gate-full.lock" ]
}
run_gf() { python3 "$GF" run --repo "$T/repo" "$@" >"$T/out" 2>&1; echo $?; }

# a. xanh -------------------------------------------------------------------------------------------------------------------
t0=$(date +%s)
rc=$(run_gf --ref origin/green)
GREEN_SHA="$(git -C "$T/repo" rev-parse origin/green)"
chk "a1. gate xanh: exit 0" '[ "$rc" = 0 ]' "rc=$rc $(tail -5 "$T/out")"
chk "a2. gate chạy trong scratch gate-full-scratch-* dưới postfix-gate/" 'grep -q "postfix-gate/gate-full-scratch-" "$T/gate.calls" 2>/dev/null'
chk "a3. nightly/full_pass.json là bản chép của scratch" 'grep -q fake "$COMMON/postfix-gate/nightly/full_pass.json" 2>/dev/null'
chk "a4. last_full_green_sha = sha của ref" '[ "$(cat "$COMMON/postfix-gate/last_full_green_sha" 2>/dev/null)" = "$GREEN_SHA" ]'
chk "a5. summary-latest.md + summary-<ngày>.md ghi XANH và sha" \
  'grep -qi "xanh" "$T/logs/summary-latest.md" 2>/dev/null && grep -q "${GREEN_SHA:0:12}" "$T/logs/summary-latest.md" && ls "$T"/logs/summary-2*.md >/dev/null 2>&1'
chk "a6. nightly/history.jsonl có một dòng" '[ "$(wc -l <"$COMMON/postfix-gate/nightly/history.jsonl" 2>/dev/null | tr -d " ")" = 1 ]'
chk "a7. log chạy <yyyymmdd-HHMMSS>.log trong thư mục log" 'ls "$T"/logs/2*-*.log >/dev/null 2>&1'
chk "a8. scratch đã gỡ, khoá đã nhả" 'no_scratch'

# b. đỏ + bisect --------------------------------------------------------------------------------------------------------------
rm -f "$T/card.args"
rc=$(run_gf)
chk "b1. gate đỏ: exit khác 0" '[ "$rc" != 0 ]' "rc=$rc"
chk "b2. lệnh tạo thẻ được gọi với commit nghi vấn = merge làm vỡ (f4)" 'grep -q "$BAD_MERGE" "$T/card.args" 2>/dev/null' \
  "muốn $BAD_MERGE; args: $(tr '\n' ' ' <"$T/card.args" 2>/dev/null) | $(tail -8 "$T/out")"
chk "b3. thẻ: nhãn bug, tiêu đề P1 gate-full đêm + suite đỏ" \
  'grep -qx bug "$T/card.args" && grep -q "P1 gate-full đêm .*REG-FAKE-01" "$T/card.args"'
chk "b4. thẻ: --new-card, risk High" 'grep -qx -- --new-card "$T/card.args" && grep -q "High" "$T/card.args"'
chk "b5. summary ghi ĐỎ, suite đỏ, commit nghi vấn, link thẻ" \
  'grep -q REG-FAKE-01 "$T/logs/summary-latest.md" && grep -q "${BAD_MERGE:0:12}" "$T/logs/summary-latest.md" && grep -q "issues/99" "$T/logs/summary-latest.md"' \
  "$(tr '\n' ' ' <"$T/logs/summary-latest.md" 2>/dev/null)"
chk "b6. last_full_green_sha giữ nguyên khi đỏ" '[ "$(cat "$COMMON/postfix-gate/last_full_green_sha")" = "$GREEN_SHA" ]'
chk "b7. scratch đã gỡ, khoá đã nhả" 'no_scratch'

# b'. issue mở cùng tiêu đề ⇒ không tạo trùng (gh giả trả lại đúng tiêu đề)
TITLE="$(grep -m1 'P1 gate-full đêm' "$T/card.args" 2>/dev/null)"
python3 - "$T/bin/gh" "$T" "$TITLE" <<'PY'
import json, sys
open(sys.argv[1], "w").write('#!/bin/sh\necho "$@" >>"%s/gh.calls"\necho %s\n'
                             % (sys.argv[2], "'" + json.dumps([{"title": sys.argv[3], "url": "https://github.com/fake/repo/issues/7"}]) + "'"))
PY
chmod +x "$T/bin/gh"
rm -f "$T/card.args"
rc=$(run_gf --slug fake/repo)
chk "b8. đã có issue mở cùng tiêu đề: không gọi lệnh tạo thẻ, summary dẫn issue cũ" \
  '[ ! -e "$T/card.args" ] && grep -q "issues/7" "$T/logs/summary-latest.md"' "$(tail -5 "$T/out")"
printf '#!/bin/sh\necho "$@" >>"%s/gh.calls"\necho "[]"\n' "$T" >"$T/bin/gh"

# c. khoá ---------------------------------------------------------------------------------------------------------------------
sleep 30 &
SLEEP_PID=$!
mkdir -p "$COMMON/postfix-gate"
printf '{"pid": %s, "started": "x"}\n' "$SLEEP_PID" >"$COMMON/postfix-gate/gate-full.lock"
: >"$T/gate.calls"
cp "$T/logs/summary-latest.md" "$T/summary.before"
rc=$(run_gf --ref origin/green)
chk "c1. pid sống giữ khoá: skip, exit 0" '[ "$rc" = 0 ] && grep -qi "skip" "$T/out"' "rc=$rc $(tail -3 "$T/out")"
chk "c1b. lượt skip không ghi đè summary-latest.md (vẫn là kết quả lượt chạy thật trước)" 'cmp -s "$T/summary.before" "$T/logs/summary-latest.md"' \
  "$(head -3 "$T/logs/summary-latest.md")"
chk "c2. gate không chạy, khoá của lượt kia còn nguyên" \
  '[ ! -s "$T/gate.calls" ] && grep -q "$SLEEP_PID" "$COMMON/postfix-gate/gate-full.lock"'
kill "$SLEEP_PID" 2>/dev/null; wait "$SLEEP_PID" 2>/dev/null; DEAD="$SLEEP_PID"; SLEEP_PID=""
printf '{"pid": %s, "started": "x"}\n' "$DEAD" >"$COMMON/postfix-gate/gate-full.lock"
rc=$(run_gf --ref origin/green)
chk "c3. pid đã chết: chiếm lại khoá, gate chạy, exit 0" '[ "$rc" = 0 ] && [ -s "$T/gate.calls" ]' "rc=$rc $(tail -3 "$T/out")"
chk "c4. scratch đã gỡ, khoá đã nhả" 'no_scratch'
# c5. file khoá RỖNG mà một tiến trình sống đang giữ (flock, khe giữa tạo file và ghi pid) ⇒ skip, không gỡ khoá của lượt kia
python3 -c 'import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o644); fcntl.flock(fd, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(30)' \
  "$COMMON/postfix-gate/gate-full.lock" "$T/flock.ready" &
SLEEP_PID=$!
i=0; while [ ! -e "$T/flock.ready" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
: >"$T/gate.calls"
rc=$(run_gf --ref origin/green)
chk "c5. khoá rỗng do tiến trình sống giữ (flock): skip, gate không chạy, file khoá còn" \
  '[ "$rc" = 0 ] && grep -qi "skip" "$T/out" && [ ! -s "$T/gate.calls" ] && [ -e "$COMMON/postfix-gate/gate-full.lock" ]' "rc=$rc $(tail -3 "$T/out")"
kill "$SLEEP_PID" 2>/dev/null; wait "$SLEEP_PID" 2>/dev/null; SLEEP_PID=""
rm -f "$COMMON/postfix-gate/gate-full.lock"

# d. tải cao ⇒ chờ tới hạn rồi chạy ----------------------------------------------------------------------------------------
: >"$T/gate.calls"
t0=$(date +%s)
rc=$(DEVKIT_CAPACITY_LOAD=999 DEVKIT_CAPACITY_CORES=1 run_gf --ref origin/green --max-wait-s 2)
dt=$(( $(date +%s) - t0 ))
chk "d1. tải 999 > hold_load 8: chờ ≥ 2 s rồi vẫn chạy (exit 0)" '[ "$rc" = 0 ] && [ "$dt" -ge 2 ] && [ -s "$T/gate.calls" ]' "rc=$rc dt=$dt"
chk "d2. summary ghi đã chờ tải và lý do chạy luôn" 'grep -qi "chờ" "$T/logs/summary-latest.md" && grep -q "999" "$T/logs/summary-latest.md"'
chk "d3. scratch đã gỡ, khoá đã nhả" 'no_scratch'

# f. chưa kết luận: gate exit 2 với suite TIMEOUT ⇒ exit 3, không thẻ, last_full_green_sha giữ nguyên ---------------------------
rm -f "$T/card.args"
rc=$(FAKE_MODE=timeout run_gf)
chk "f1. TIMEOUT không phải đỏ: exit 3, không gọi lệnh tạo thẻ, last_full_green_sha giữ nguyên" \
  '[ "$rc" = 3 ] && [ ! -e "$T/card.args" ] && [ "$(cat "$COMMON/postfix-gate/last_full_green_sha")" = "$GREEN_SHA" ]' "rc=$rc"
chk "f2. summary ghi CHƯA KẾT LUẬN; scratch đã gỡ" 'grep -q "CHƯA KẾT LUẬN" "$T/logs/summary-latest.md" && no_scratch'
# g. suite đỏ nhưng chạy lại hết giờ khi chia đôi ⇒ không đổ cho merge nào (hết giờ không phải "đỏ")
rc=$(FAKE_MODE=slowred run_gf --timeout 1)
chk "g1. chạy lại ở đỉnh hết giờ: thẻ không mang sha merge nào, summary ghi hết giờ" \
  '[ "$rc" = 1 ] && ! grep -q "$BAD_MERGE" "$T/card.args" && grep -q "hết giờ" "$T/logs/summary-latest.md" && no_scratch' "rc=$rc"

# h. repo land bằng squash / fast-forward (first-parent không có merge): chia đôi theo commit, ra ĐÚNG commit làm vỡ (không phải đỉnh) --------
g -C "$T/seed" checkout -q -b lin "$BASE"
for i in 1 2 3 4 5 6; do
  printf '%s\n' "$i" >"$T/seed/l$i.txt"
  [ "$i" = 3 ] && printf 'BROKEN\n' >>"$T/seed/src.txt"
  g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "squash l$i"
done
BAD_SQ="$(git -C "$T/seed" log --format='%H %s' | awk '/squash l3$/ {print $1}')"
g -C "$T/seed" push -q origin lin
rm -f "$T/card.args"
rc=$(run_gf --ref origin/lin)
chk "h1. chuỗi squash thẳng: lệnh tạo thẻ nhận commit làm vỡ (l3), không phải đỉnh" \
  '[ "$rc" != 0 ] && grep -q "$BAD_SQ" "$T/card.args" 2>/dev/null' "muốn $BAD_SQ; args: $(tr '\n' ' ' <"$T/card.args" 2>/dev/null) | $(tail -8 "$T/out")"
chk "h2. scratch đã gỡ, khoá đã nhả" 'no_scratch'

# e. lịch launchd -------------------------------------------------------------------------------------------------------------
# e1–e14 chạy bản sao kit ngoài git: kit của test nằm trong linked worktree thì install luôn lấy gate_full.py của main checkout
# (e19–e21), main chưa có ⇒ exit 2. Đường dẫn vật lý: script lấy KIT bằng pwd -P
mkdir -p "$T/kit/bin" && cp "$SCHED" "$GF" "$T/kit/bin/"
SCHED="$(cd "$T/kit/bin" && pwd -P)/gate-full-schedule.sh"; GF="$(cd "$T/kit/bin" && pwd -P)/gate_full.py"
mkdir -p "$T/la"
printf '#!/bin/sh\necho "$@" >>"%s/launchctl.calls"\n' "$T" >"$T/fakelaunchctl"
chmod +x "$T/fakelaunchctl"
export DEVKIT_LAUNCH_AGENTS_DIR="$T/la" DEVKIT_LAUNCHCTL="$T/fakelaunchctl"
plists() { ls "$T/la"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null; }
# shell đăng nhập giả của người dùng: PATH của nó có thư mục công cụ suite (uv ở ~/.local/bin) mà launchd không có
printf '#!/bin/sh\nprintf %%s "%s/uvbin:/usr/bin:/bin"\n' "$T" >"$T/fakeshell"
chmod +x "$T/fakeshell"
SHELL="$T/fakeshell" bash "$SCHED" install --repo "$T/repo" >"$T/sched.out" 2>&1; rc=$?
PL="$(plists | head -1)"; PL="${PL:-$T/la/none.plist}"
LA="$(basename "$PL" .plist)"
chk "e1. install exit 0, plist com.toanmobile.devkit.gate-full.<slug>.plist hợp lệ (plutil -lint)" \
  '[ "$rc" = 0 ] && [ "$(plists | wc -l | tr -d " ")" = 1 ] && plutil -lint "$PL" >/dev/null 2>&1' "rc=$rc $(ls "$T/la") $(tail -3 "$T/sched.out")"
px() { plutil -extract "$1" raw -o - "${2:-$PL}" 2>/dev/null; }
chk "e9. Label = tên plist, slug có tên thư mục repo" \
  '[ "$(px Label)" = "$LA" ] && case "$LA" in com.toanmobile.devkit.gate-full.repo-????????) true ;; *) false ;; esac' "label=$(px Label) plist=$LA"
chk "e10. log riêng của repo: DEVKIT_GATE_FULL_LOG_DIR = <log>/<slug>, stdout vào đó" \
  'D="$(px EnvironmentVariables.DEVKIT_GATE_FULL_LOG_DIR)"; [ "$D" = "$T/logs/${LA#com.toanmobile.devkit.gate-full.}" ] && [ "$(dirname "$(px StandardOutPath)")" = "$D" ]' \
  "log=$(px EnvironmentVariables.DEVKIT_GATE_FULL_LOG_DIR) out=$(px StandardOutPath)"
chk "e8. PATH của job có PATH đăng nhập của người dùng (thư mục uv), vẫn có /usr/bin" \
  'case ":$(px EnvironmentVariables.PATH):" in *":$T/uvbin:"*) true ;; *) false ;; esac && case ":$(px EnvironmentVariables.PATH):" in *":/usr/bin:"*) true ;; *) false ;; esac' \
  "PATH=$(px EnvironmentVariables.PATH)"
chk "e2. StartCalendarInterval Hour 0 Minute 0" '[ "$(px StartCalendarInterval.Hour)" = 0 ] && [ "$(px StartCalendarInterval.Minute)" = 0 ]'
chk "e3. ProgramArguments: /usr/bin/nice -n 10 <python3 tuyệt đối> gate_full.py run --repo" \
  '[ "$(px ProgramArguments.0)" = /usr/bin/nice ] && [ "$(px ProgramArguments.1)" = -n ] && [ "$(px ProgramArguments.2)" = 10 ] \
   && case "$(px ProgramArguments.3)" in /*) [ -x "$(px ProgramArguments.3)" ] ;; *) false ;; esac \
   && [ "$(px ProgramArguments.4)" = "$GF" ] && [ "$(px ProgramArguments.5)" = run ] && [ "$(px ProgramArguments.7)" = "$T/repo" ]'
chk "e4. TZ Asia/Ho_Chi_Minh, PATH có thư mục python3, RunAtLoad false, log vào thư mục log" \
  '[ "$(px EnvironmentVariables.TZ)" = Asia/Ho_Chi_Minh ] && case ":$(px EnvironmentVariables.PATH):" in *":$(dirname "$(px ProgramArguments.3)"):"*) true ;; *) false ;; esac \
   && [ "$(px RunAtLoad)" = false ] && case "$(px StandardOutPath)" in "$T/logs/"*) true ;; *) false ;; esac'
chk "e5. launchctl giả: bootout rồi bootstrap gui/$(id -u) <plist>" \
  'grep -q "^bootout gui/$(id -u)" "$T/launchctl.calls" && grep -qx "bootstrap gui/$(id -u) $PL" "$T/launchctl.calls"'
bash "$SCHED" status --repo "$T/repo" >"$T/sched.out" 2>&1
chk "e6. status --repo gọi launchctl print đúng label và chỉ summary-latest.md" \
  'grep -qx "print gui/$(id -u)/$LA" "$T/launchctl.calls" && grep -q summary-latest.md "$T/sched.out"'
# repo B cùng tên thư mục "repo": lịch riêng, không gỡ lịch A
mkdir -p "$T/b/repo"; : >"$T/launchctl.calls"
bash "$SCHED" install --repo "$T/b/repo" >"$T/sched.out" 2>&1; rc=$?
PLB="$(plists | grep -vxF "$PL" | head -1)"; LB="$(basename "${PLB:-none.plist}" .plist)"
chk "e11. install repo B: plist + label thứ hai, plist A còn, log B khác log A" \
  '[ "$rc" = 0 ] && [ "$(plists | wc -l | tr -d " ")" = 2 ] && [ -e "$PL" ] && [ "$LB" != "$LA" ] && [ "$(px Label "$PLB")" = "$LB" ] \
   && [ "$(px EnvironmentVariables.DEVKIT_GATE_FULL_LOG_DIR "$PLB")" != "$(px EnvironmentVariables.DEVKIT_GATE_FULL_LOG_DIR)" ]' \
  "rc=$rc $(ls "$T/la") $(tail -3 "$T/sched.out")"
chk "e12. install repo B: launchctl bootstrap plist B, không bootout lịch A" \
  'grep -qx "bootstrap gui/$(id -u) $PLB" "$T/launchctl.calls" && ! grep -q "$LA\$" "$T/launchctl.calls"' "$(tr '\n' ' ' <"$T/launchctl.calls")"
: >"$T/launchctl.calls"
bash "$SCHED" uninstall --repo "$T/repo" >"$T/sched.out" 2>&1; rc=$?
chk "e7. uninstall --repo A exit 0: chỉ gỡ plist A, bootout đúng label A, plist B còn" \
  '[ "$rc" = 0 ] && [ ! -e "$PL" ] && [ -e "$PLB" ] && grep -qx "bootout gui/$(id -u)/$LA" "$T/launchctl.calls" && ! grep -q "$LB" "$T/launchctl.calls"' \
  "rc=$rc $(ls "$T/la") $(tr '\n' ' ' <"$T/launchctl.calls")"
bash "$SCHED" uninstall --repo "$T/b/repo" >/dev/null 2>&1
# e13 (OCR vòng 4): repo đã bị xoá (worktree gỡ trước lịch), nhập qua đường dẫn có symlink ⇒ uninstall vẫn tìm đúng plist đã cài và gỡ nó
mkdir -p "$T/creal/repo" && ln -s "$T/creal" "$T/clink" && git -C "$T/creal/repo" init -q 2>/dev/null
bash "$SCHED" install --repo "$T/clink/repo" >/dev/null 2>&1
PLC="$(ls "$T/la"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null | head -1)"
rm -rf "$T/creal/repo"
bash "$SCHED" uninstall --repo "$T/clink/repo" >"$T/sched.out" 2>&1; rc=$?
chk "e13. repo đã mất: uninstall --repo (đường dẫn như lúc cài) gỡ đúng plist đã cài, exit 0" \
  '[ -n "$PLC" ] && [ "$rc" = 0 ] && [ ! -e "$PLC" ]' "rc=$rc plist='$PLC' còn: $(ls "$T/la" 2>/dev/null) out: $(cat "$T/sched.out")"
# e14: uninstall một repo chưa từng cài ⇒ exit khác 0, nói không có lịch (không báo "đã gỡ" giả)
bash "$SCHED" uninstall --repo "$T/never/repo" >"$T/sched.out" 2>&1; rc=$?
chk "e14. uninstall repo chưa cài: exit khác 0, không báo đã gỡ" '[ "$rc" != 0 ] && ! grep -q "đã gỡ lịch" "$T/sched.out"' \
  "rc=$rc out: $(cat "$T/sched.out")"

# e15–e18 (audit Antigravity): install từ một LINKED worktree (trunk mode) không được neo lịch đêm vào worktree tạm — gỡ worktree là
# plist chạy script không còn. Repo nháp M có bản sao kit, worktree W chạy bản sao kit của chính W. Thư mục LaunchAgents riêng (la2).
M="$T/m"; mkdir -p "$M/universal-agent-devkit/bin"
cp "$SCHED" "$GF" "$M/universal-agent-devkit/bin/"
g -C "$M" init -q && g -C "$M" add -A && g -C "$M" commit -qm kit
WT="$T/wt"; g -C "$M" worktree add -q --detach "$WT" HEAD
MP="$(cd "$M" && pwd -P)"; WTP="$(cd "$WT" && pwd -P)"
mkdir -p "$T/la2"; : >"$T/launchctl.calls"
phys() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$1")"); }
pl2() { ls "$T/la2"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null | head -1; }
(cd "$WT" && DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$WT/universal-agent-devkit/bin/gate-full-schedule.sh" install) \
  >"$T/sched.out" 2>&1; rc=$?
P2="$(pl2)"
chk "e15. install từ linked worktree không --repo: plist neo về main checkout (cả --repo lẫn gate_full.py)" \
  '[ "$rc" = 0 ] && [ -n "$P2" ] && [ "$(phys "$(px ProgramArguments.7 "$P2")")" = "$MP" ] \
   && [ "$(phys "$(px ProgramArguments.4 "$P2")")" = "$MP/universal-agent-devkit/bin/gate_full.py" ]' \
  "rc=$rc repo=$(px ProgramArguments.7 "$P2") gf=$(px ProgramArguments.4 "$P2") out: $(tail -3 "$T/sched.out")"
rm -f "$T/la2"/*.plist "$M/universal-agent-devkit/bin/gate_full.py"; : >"$T/launchctl.calls"
(cd "$WT" && DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$WT/universal-agent-devkit/bin/gate-full-schedule.sh" install) \
  >"$T/sched.out" 2>&1; rc=$?
chk "e16. main checkout không có gate_full.py: từ chối (exit 2), không plist, không bootstrap" \
  '[ "$rc" = 2 ] && [ -z "$(pl2)" ] && ! grep -q bootstrap "$T/launchctl.calls"' "rc=$rc out: $(tail -3 "$T/sched.out")"
DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$SCHED" install --repo "$WT" >"$T/sched.out" 2>&1; rc=$?
chk "e17. --repo <linked worktree>: từ chối (exit 2), không plist" '[ "$rc" = 2 ] && [ -z "$(pl2)" ]' "rc=$rc out: $(tail -3 "$T/sched.out")"
DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$SCHED" install --repo "$WT" --allow-worktree >"$T/sched.out" 2>&1; rc=$?
P2="$(pl2)"
chk "e18. --repo <linked worktree> --allow-worktree: cài được, plist trỏ worktree" \
  '[ "$rc" = 0 ] && [ -n "$P2" ] && [ "$(phys "$(px ProgramArguments.7 "$P2")")" = "$WTP" ]' "rc=$rc out: $(tail -3 "$T/sched.out")"
# e19–e21 (OCR #644): kit nằm trong linked worktree thì gate_full.py của lịch LUÔN lấy từ main checkout, cả khi có --repo; gọi qua
# symlink tới kit thì plist ghi đường vật lý (không phải đường alias trong worktree)
cp "$GF" "$M/universal-agent-devkit/bin/"; rm -f "$T/la2"/*.plist; : >"$T/launchctl.calls"
(cd "$T" && DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$WT/universal-agent-devkit/bin/gate-full-schedule.sh" install --repo "$M") \
  >"$T/sched.out" 2>&1; rc=$?
P2="$(pl2)"
chk "e19. kit của linked worktree + --repo <main>: plist trỏ gate_full.py của main checkout" \
  '[ "$rc" = 0 ] && [ -n "$P2" ] && [ "$(px ProgramArguments.4 "$P2")" = "$MP/universal-agent-devkit/bin/gate_full.py" ] \
   && [ "$(phys "$(px ProgramArguments.7 "$P2")")" = "$MP" ]' \
  "rc=$rc gf=$(px ProgramArguments.4 "$P2") out: $(tail -3 "$T/sched.out")"
mkdir -p "$WT/.agents" && ln -s "$MP/universal-agent-devkit" "$WT/.agents/devkit"
rm -f "$T/la2"/*.plist; : >"$T/launchctl.calls"
(cd "$T" && DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$WT/.agents/devkit/bin/gate-full-schedule.sh" install --repo "$M") \
  >"$T/sched.out" 2>&1; rc=$?
P2="$(pl2)"
chk "e20. gọi qua symlink <worktree>/.agents/devkit tới kit của main: plist ghi đường vật lý dưới main, không qua worktree" \
  '[ "$rc" = 0 ] && [ -n "$P2" ] && [ "$(px ProgramArguments.4 "$P2")" = "$MP/universal-agent-devkit/bin/gate_full.py" ]' \
  "rc=$rc gf=$(px ProgramArguments.4 "$P2") out: $(tail -3 "$T/sched.out")"
rm -f "$T/la2"/*.plist "$M/universal-agent-devkit/bin/gate_full.py"; : >"$T/launchctl.calls"
(cd "$T" && DEVKIT_LAUNCH_AGENTS_DIR="$T/la2" SHELL="$T/fakeshell" bash "$WT/universal-agent-devkit/bin/gate-full-schedule.sh" install --repo "$M") \
  >"$T/sched.out" 2>&1; rc=$?
chk "e21. kit của linked worktree + --repo <main>, main không có gate_full.py: từ chối (exit 2), không plist, không bootstrap" \
  '[ "$rc" = 2 ] && [ -z "$(pl2)" ] && ! grep -q bootstrap "$T/launchctl.calls"' "rc=$rc out: $(tail -3 "$T/sched.out")"

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_full_nightly: PASS"; exit 0; fi
echo "test_gate_full_nightly: $fails FAIL"; exit 1
