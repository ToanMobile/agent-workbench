#!/usr/bin/env bash
# Runs the DevKit tests that name a changed DevKit code file, every changed test script itself,
# and the fast repo-consistency check. "Changed" = working tree vs HEAD, new files, and commits
# not pushed yet (no upstream: a linked worktree's commits since its merge-base with the main checkout, else the last 6 hours;
# DEVKIT_IMPACTED_SINCE=<git date> sets that window; =0 none: a RED-proof sandbox), so committing
# inside a turn does not leave the gate testing nothing. A helper under tests/ selects the tests that source it by name.
# The full suite (`agent-kit test`) runs far longer than post-fix-gate's 900 s per command,
# so a regression matrix that watches the DevKit (agent-workbench's) uses this instead.
# ponytail: a changed file that no test names gets repo-consistency only, add a test when such a file breaks
# devkit-selection-list: `--list` only prints the selection and runs nothing: post-fix-gate's suite cache (bin/suite_cache.py) asks it, by this marker.
# Usage: run_impacted.sh [--list | --all | --jobs]   (--list prints the selection and runs nothing; --all runs the whole
# suite, whatever changed: what `agent-kit test` calls, in parallel — one test after another took ~19 min;
# --jobs prints how many tests a run starts at once and exits)
# bash 3.2 compatible.
set -u
DK="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DK" || exit 2

# Tests started at once: DEVKIT_TEST_JOBS when it is a positive integer, else bin/capacity.py test_jobs (T0052, below), else min(cores + cores/3, 16) with a floor of 4, the old default (3 cores or fewer keep 4; only 12 cores was measured) (cores
# from nproc, sysctl hw.ncpu or python3; none answers: 4, the old default). 2026-10-04: `--all` took 301 s for 102 tests at 4 jobs on 12 cores (bound by the job count: about 20 min of
# tests / 4). 2026-10-23, 12 cores, the same 127 tests: at 10 jobs the pool kept about 7 cores busy (1822 s CPU in 272 s), so more jobs fill the time the tests wait; 2 runs per
# setting, alternating: 272/326 s at 10 jobs, 240/263 s at 16, 0 red tests in 6 runs (tests/verification/test_run_impacted_order.sh (f)).
# DEVKIT_TEST_CORES pretends a core count (tests only). `--jobs` prints the number a run would use.
# T0052: mặc định lấy từ nguồn sức chứa chung bin/capacity.py test_jobs = max(4, ⌊lõi × 4/3 × DEVKIT_CAPACITY⌋), không còn trần 16
# (13 lõi: 17, 64 lõi: 85), không co theo tải (người dùng 23/10: máy bận thì chờ trước khi chạy); DEVKIT_TEST_CORES đi vào capacity
# dưới tên DEVKIT_CAPACITY_CORES.
# ponytail: không còn trần trên — số job chỉ đo trên một máy 12 lõi (16 job); máy lớn (64 lõi: 85, DEVKIT_CAPACITY=4: 341) chưa đo,
# thêm trần vào capacity.test_jobs khi máy lớn báo hết fd/tiến trình hoặc test quá giờ.
# capacity.py vắng / hỏng / không có python3: công thức shell cũ bên dưới.
pint() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ $((10#$1)) -gt 0 ]; }   # 10# so 08 is eight, 00 is not "unlimited"
default_jobs() {
  local c="${DEVKIT_TEST_CORES:-}" j
  if pint "$c"; then j="$(DEVKIT_CAPACITY_CORES=$((10#$c)) python3 "$DK/bin/capacity.py" test_jobs 2>/dev/null)"
  else j="$(python3 "$DK/bin/capacity.py" test_jobs 2>/dev/null)"; fi
  pint "$j" && { echo $((10#$j)); return; }
  pint "$c" || c="$(nproc 2>/dev/null)"
  pint "$c" || c="$(sysctl -n hw.ncpu 2>/dev/null)"
  pint "$c" || c="$(python3 -c 'import os; print(os.cpu_count() or 0)' 2>/dev/null)"
  pint "$c" || { echo 4; return; }
  c=$((10#$c + 10#$c / 3)); [ "$c" -gt 16 ] && c=16; [ "$c" -lt 4 ] && c=4
  echo "$c"
}
jobs_now() { # what a run uses: the override when valid, else the default
  if pint "${DEVKIT_TEST_JOBS:-}"; then echo $((10#$DEVKIT_TEST_JOBS)); else default_jobs; fi
}
[ "${1:-}" = "--jobs" ] && { jobs_now; exit 0; }

trunk_ref=""
for t in "$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master origin/trunk; do
  # only a trunk HEAD shares history with: no merge-base (shallow clone, rewritten trunk) would empty the change set silently
  [ -n "$t" ] && git rev-parse -q --verify "$t^{commit}" >/dev/null 2>&1 && git merge-base "$t" HEAD >/dev/null 2>&1 \
    && { trunk_ref="$t"; break; }
done
if git rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
  # a diff from the merge-base, not `git log --name-only`: that prints no file for a merge commit, so a conflict resolution that
  # changed another file went untested (W1 R4, 14/10). Measured against origin/<trunk> when it exists: a branch whose upstream
  # is an OLD branch selected everything the trunk changed since (#319 TIMEOUT x4, #240 "331 tests", 24/10).
  base_ref="$trunk_ref"; [ -n "$base_ref" ] || base_ref='@{u}'   # not ${x:-@{u}}: its `}` ends the expansion
  unpushed="$(git diff --name-only --relative "$base_ref...HEAD" -- . 2>/dev/null)"
elif [ "${DEVKIT_IMPACTED_SINCE:-}" = 0 ]; then
  unpushed=""   # a RED-proof sandbox (no upstream, a detached worktree): only the file it reverted is a change, not every commit of the last hours
elif [ -z "${DEVKIT_IMPACTED_SINCE:-}" ] \
  && [ "$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)" != "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" ] \
  && base="$(git merge-base HEAD "$(git worktree list --porcelain 2>/dev/null | sed -n '1,/^$/s/^HEAD //p')" 2>/dev/null)" && [ -n "$base" ]; then
  # a linked worktree (`agent-kit worktree add`, detached): what it holds that the main checkout's HEAD does not. The last 6 hours
  # were other sessions' commits already in main (13/10: 157 tests instead of 11). A diff, not `git log`: that skips a merge's files.
  unpushed="$(git diff --name-only --relative "$base" HEAD -- . 2>/dev/null)"
else
  unpushed="$(git log --since="${DEVKIT_IMPACTED_SINCE:-6.hours}" --name-only --relative --format= -- . 2>/dev/null)"
fi
changed="$( { git diff HEAD --name-only --relative -- . ; git ls-files -o --exclude-standard -- . ; printf '%s\n' "$unpushed"; } 2>/dev/null \
  | grep -vE '(^|/)(CHANGELOG|README[^/]*)\.md$' | sort -u)"   # templates and rules are read by tests too
# Only tests/verification/test_impact_map.sh sets this, and only for --list (which runs nothing): it pretends these
# files changed (newline separated). A run that executes tests ignores it, so nobody can shrink the gate's selection.
[ "${1:-}" = "--list" ] && [ -n "${DEVKIT_IMPACT_TEST_CHANGED:-}" ] && changed="$DEVKIT_IMPACT_TEST_CHANGED"
tests="tests/verification/test_repo_consistency.sh"
for f in $changed; do
  case "$f" in
    tests/*/test_*.sh|hooks/tests/*.sh) tests="$tests $f"; continue ;;
  esac   # a helper under tests/ falls through: every test that sources it names it
  tests="$tests $(grep -l -F -- "$(basename "$f")" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')"
  # …or its stem as a whole word: tests reach scripts through commands ("agent-kit githooks
  # install" → scripts/githooks.sh; test_githooks went unrun on 2026-09-26).
  # 25/10: chỉ file CODE (.sh .py .bash .mjs .js; file không đuôi thì stem = tên, đã khớp ở trên). Stem của tài liệu là chữ thường:
  # commands/test.md chọn 273 test qua "test", commands/fix.md 202 qua "fix", hooks/hooks.json 198 qua "hooks" — người đọc thật của
  # tài liệu khai trong tests/impact_map.txt.
  case "$f" in
    *.sh|*.py|*.bash|*.mjs|*.js)
      stem="$(basename "$f")"; stem="${stem%.*}"
      [ -n "$stem" ] && tests="$tests $(grep -l -w -F -- "$stem" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')" ;;
  esac
  # …and the tests tests/impact_map.txt declares for a file they exercise without naming it.
  while read -r glob rest; do
    case "$glob" in ''|'#'*) continue ;; esac
    case "$f" in $glob) tests="$tests $rest" ;; esac
  done < tests/impact_map.txt
done
selected="$(printf '%s\n' $tests | sort -u)"
# --all: every test. Finding none is an error — a glob that matches nothing must not pass. hooks/tests/test_*.sh too (5 of them ran
# nowhere, 13/10); its *_test.sh contract files are not: `agent-kit test` runs them itself before this pool.
if [ "${1:-}" = "--all" ]; then
  selected="$(ls tests/*/test_*.sh 2>/dev/null)"   # checked alone: the hooks tests must not hide a suite that vanished
  [ -n "$selected" ] || { echo "run_impacted --all: no tests found under tests/*/test_*.sh" >&2; exit 2; }
  selected="$selected $(ls hooks/tests/test_*.sh 2>/dev/null)"
fi
# post-fix-gate lists the test scripts it already ran in this gate (O2): not run twice.
if [ -n "${DEVKIT_GATE_DONE:-}" ]; then
  DKP="$(pwd -P)"; keep=""
  for t in $selected; do
    printf '%s\n' "$DEVKIT_GATE_DONE" | grep -qxF "$DKP/$t" && continue
    keep="$keep $t"
  done
  selected="$keep"
fi

if [ "${1:-}" = "--list" ]; then
  for t in $selected; do [ -f "$t" ] && echo "$t"; done
  exit 0
fi

# Parallel, $JOBS at a time (jobs_now above): run one after another the suite took 740 s of
# the gate's 900 s (2026-09-26). Every test works in its own mktemp dir. Timing tests
# (test_budgets, test_session_context's bounded fetch, test_gate_lock_receipt_gap's 1.5 s race between two gates — failed rep 3 in
# the pool at load ~70 on 25/10, 3/3 alone) run alone afterwards, so the others cannot slow them. Output keeps list order.
JOBS="$(jobs_now)"
# `agent-kit test` runs its earlier suites beside the parallel phase and names a file that appears when they have ended: the
# timing tests below wait for it, so they still run alone (15 minutes at most: a file that never comes must not hang the run; and not
# at all once the process that started this run is gone: a SIGKILLed `agent-kit test` leaves no trap to stop its pool).
# Not set: no wait. Read once and unset, so no test started below (some run their own copy of this runner) sees it.
after="${DEVKIT_ALONE_AFTER_FILE:-}"; unset DEVKIT_ALONE_AFTER_FILE
parent="$PPID"   # whoever started this run (agent-kit): the wait below ends when that process is gone, a SIGKILL leaves no trap to tell us
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
run_one() { # <test> <out dir>
  local o
  o="$2/$(printf '%s' "$1" | tr '/' '_')"
  # Stop của Grok export GROK_HOOK_*; detect() coi mọi hook con là Grok và nhả phiên sau 3 lần chặn (exit 0).
  # Bài thử nào cần Grok thì tự gán các biến đó. Không gỡ DEVKIT_GATE_DONE: gate truyền danh sách suite đã chạy.
  # Slot riêng từng bài: --full của `sh`/`echo` không được chờ 2 slot Gradle/Unity của máy (Stop ngắt ở 600s).
  # Bài nào tự export SB_HEAVY_SLOT_DIR thì dùng dir của nó (test_heavy_slot.sh).
  # 24/10: mỗi bài chạy qua tests/lib/run_bounded.py: cả nhóm tiến trình của bài bị giết khi quá DEVKIT_TEST_TIMEOUT_S (mặc định
  # 1800 = gấp đôi trần 900 s của cả suite REG-DK-ALL-01: khi gate còn sống, TIMEOUT của suite luôn tới trước và giữ nguyên nghĩa
  # TIMEOUT mà merge gate / KNOWN-RED xử lý riêng — đo 24/10, tải 96–100: hạn 600 s cắt 7 bài chỉ chậm, biến TIMEOUT thành FAIL; hạn
  # này chặn mồ côi khi gate đã chết; 0 = không hạn), khi tiến trình gọi helper chết, khi Ctrl-C / SIGTERM tới nhóm này, hay khi
  # chính helper bị SIGKILL (watchdog). Runner này bị SIGKILL riêng thì xargs vẫn chạy nốt, nhưng mỗi bài vẫn dừng ở hạn của nó.
  # Trước đó `bash "$1"` trần: ca FIFO của test_gate_robustness.sh kẹt trong open(), runner phía trên mất, hai post-fix-gate.py
  # sống 18h và các gate khác báo BUSY.
  mkdir -p "$o.slots"
  if env -u GROK_HOOK_EVENT -u GROK_HOOK_NAME -u GROK_SESSION_ID -u DEVKIT_AGENT -u HOOK_PPID \
       SB_HEAVY_SLOT_DIR="$o.slots" \
       ${DEVKIT_RUN_BOUNDED:+python3 -I "$DEVKIT_RUN_BOUNDED" "$DEVKIT_TEST_TIMEOUT_S" --} \
       bash "$1" >"$o.log" 2>&1; then echo 0 >"$o.rc"; else echo 1 >"$o.rc"; fi
}
export -f run_one
# helper vắng (bản kit cũ) hay không có python3: chạy trần như trước, không chặn cả lượt test
DEVKIT_RUN_BOUNDED=""
[ -f "$DK/tests/lib/run_bounded.py" ] && command -v python3 >/dev/null 2>&1 && DEVKIT_RUN_BOUNDED="$DK/tests/lib/run_bounded.py"
DEVKIT_TEST_TIMEOUT_S="${DEVKIT_TEST_TIMEOUT_S:-1800}"
case "$DEVKIT_TEST_TIMEOUT_S" in *[!0-9]*) echo "run_impacted.sh: DEVKIT_TEST_TIMEOUT_S must be whole seconds; using 1800" >&2; DEVKIT_TEST_TIMEOUT_S=1800 ;; esac
export DEVKIT_RUN_BOUNDED DEVKIT_TEST_TIMEOUT_S
parallel="" alone=""
for t in $selected; do
  [ -f "$t" ] || continue
  case "$t" in */test_budgets.sh|*/test_session_context.sh|*/test_gate_lock_receipt_gap.sh) alone="$alone $t" ;; *) parallel="$parallel $t" ;; esac
done
# Start the longest tests first (tests/lib/test_durations.txt: `<seconds> <path>`; a test it does not list starts first, as it
# may be slow): a 137 s test that starts last becomes the tail of the whole run. ONLY the start order of $parallel changes: $selected
# (what runs, what is printed, in which order) is untouched, and the reordered list is used only if it holds exactly the same tests.
dur="tests/lib/test_durations.txt"
if [ -n "$parallel" ] && [ -r "$dur" ]; then
  ordered="$(printf '%s\n' $parallel | LC_ALL=C awk -v F="$dur" '
    BEGIN { while ((getline l < F) > 0) { n = split(l, a, /[ \t]+/); if (n >= 2 && a[1] ~ /^[0-9]+(\.[0-9]+)?$/) d[a[2]] = a[1] + 0 } }
    { print (($0 in d) ? d[$0] : 1000000000), NR, $0 }' 2>/dev/null | LC_ALL=C sort -k1,1nr -k2,2n 2>/dev/null | cut -d' ' -f3- 2>/dev/null)"
  [ "$(printf '%s\n' $ordered | LC_ALL=C sort)" = "$(printf '%s\n' $parallel | LC_ALL=C sort)" ] && parallel="$ordered"
fi
[ -n "$parallel" ] && printf '%s\n' $parallel | xargs -P "$JOBS" -I{} bash -c 'run_one "$1" "$2"' _ {} "$out"
# ponytail: the parallel phase above still runs to its end after a kill of the parent (~3 min, bounded), and only a changed parent pid is
# seen (no ps answer: it keeps waiting); upgrade (poll between tests) if that ever hurts.
w=0; while [ -n "$after" ] && [ -n "$alone" ] && [ ! -e "$after" ] && [ "$w" -lt 900 ]; do
  now="$(ps -o ppid= -p $$ 2>/dev/null)"; now="${now// /}"
  if [ -n "$now" ] && [ "$now" != "$parent" ]; then echo "run_impacted.sh: the process that started this run ($parent) is gone: stopping, the timing tests are not run" >&2; exit 1; fi
  sleep 1; w=$((w + 1))
done
for t in $alone; do run_one "$t" "$out"; done
rc=0
for t in $selected; do
  [ -f "$t" ] || continue
  o="$out/$(printf '%s' "$t" | tr '/' '_')"
  if [ "$(cat "$o.rc" 2>/dev/null)" = 0 ]; then
    echo "✔ $t"
  else
    echo "✖ $t"; tail -n 20 "$o.log" 2>/dev/null | sed 's/^/    /'; rc=1
  fi
done
exit "$rc"
