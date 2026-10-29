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
# Chuẩn hoá TMPDIR tương đối thành đường dẫn tuyệt đối trước khi đổi thư mục làm việc sang $DK
if [ -n "${TMPDIR:-}" ]; then
  case "$TMPDIR" in
    /*) ;;
    *) [ -d "$TMPDIR" ] && TMPDIR="$(CDPATH= cd -P -- "$TMPDIR" >/dev/null 2>&1 && pwd -P)" && export TMPDIR ;;
  esac
fi
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
  # 28/10 (#614): a skill's SKILL.md selects the tests that name its skill (the folder, as a whole word), else one skill's edit
  # selected every test naming any SKILL.md (16 tests, none about it). The skill name, not "<skill>/SKILL.md": tests read it
  # through variables (SKILL=…/skills/devkit-audit; "$d/SKILL.md"; OCR 29/10). The readers of every SKILL.md are in
  # tests/impact_map.txt (skills/*/SKILL.md). Only SKILL.md: profiles/*/DESIGN.md, RULES.md, instincts.md and hooks.json keep
  # their bare name (read as "$GAME/DESIGN.md" by tests the map does not list; review 28/10).
  case "$f" in
    */SKILL.md) tests="$tests $(grep -l -w -F -- "$(basename "$(dirname "$f")")" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')" ;;
    *) tests="$tests $(grep -l -F -- "$(basename "$f")" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')" ;;
  esac
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
# #616 B: DEVKIT_IMPACTED_DIRS="a,b,!c" narrows the selection to a shard by the directory under tests/ (a = only a, b; !c = not c): REG-DK-ALL-01
# alone hit its 900 s ceiling at load 80-130, so the matrix also lists the shards (GATES, WORKTREE, REST). Unset or empty: the whole selection.
# A test outside tests/<dir>/ (hooks/tests) has no directory: no include token matches it, no exclude token drops it. Names are compared, never globbed.
# The variable rides in the matrix command as a leading `DEVKIT_IMPACTED_DIRS=<value> ` (bin/suite_cache.py SELECTION_CMD reads it, so the key store still applies).
if [ -n "${DEVKIT_IMPACTED_DIRS:-}" ]; then
  inc=""; exc=""
  for tok in $(printf '%s' "$DEVKIT_IMPACTED_DIRS" | tr ',' ' '); do
    case "$tok" in '!'*) exc="$exc ${tok#!}" ;; *) inc="$inc $tok" ;; esac
  done
  keep=""
  for t in $selected; do
    top=""; case "$t" in tests/*/*) top="${t#tests/}"; top="${top%%/*}" ;; esac
    if [ -n "$inc" ]; then
      hit=0; for x in $inc; do [ "$top" = "$x" ] && hit=1; done
      [ "$hit" = 1 ] || continue
    fi
    for x in $exc; do [ "$top" = "$x" ] && continue 2; done
    keep="$keep $t"
  done
  selected="$keep"
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
# the pool at load ~70 on 25/10, 3/3 alone; test_agent_kit_test_order's pool/SIGTERM windows — D2 then D1 failed in the pool at
# load 100+ on 26/10, all checks passed alone at load 106; #430: test_run_impacted "not parallel: 6 s", test_relink "slow",
# test_worktree_merge_gate_owner's 6 s wait) run alone afterwards, so the others cannot slow them. Output keeps list order.
JOBS="$(jobs_now)"
# `agent-kit test` runs its earlier suites beside the parallel phase and names a file that appears when they have ended: the
# timing tests below wait for it, so they still run alone (15 minutes at most: a file that never comes must not hang the run; and not
# at all once the process that started this run is gone: a SIGKILLed `agent-kit test` leaves no trap to stop its pool).
# Not set: no wait. Read once and unset, so no test started below (some run their own copy of this runner) sees it.
after="${DEVKIT_ALONE_AFTER_FILE:-}"; unset DEVKIT_ALONE_AFTER_FILE
parent="$PPID"   # whoever started this run (agent-kit): the wait below ends when that process is gone, a SIGKILL leaves no trap to tell us
out="$(mktemp -d "${TMPDIR:-/tmp}/dk-run-XXXXXX" 2>/dev/null)" && [ -n "$out" ] && [ -d "$out" ] \
  || { echo "run_impacted.sh: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$out"' EXIT
trap 'rm -rf "$out"; trap - INT EXIT; kill -INT $$' INT
trap 'rm -rf "$out"; trap - TERM EXIT; kill -TERM $$' TERM
trap 'rm -rf "$out"; trap - HUP EXIT; kill -HUP $$' HUP
run_one() { # <test> <out dir>
  local o
  o="$2/$(printf '%s' "$1" | tr '/' '_')"
  # #473: `· start` before the test runs, `· done` after: the gate names a hung suite's RUNNING tests (started, not done), not the last one
  # that ended. Same line rules as `· done` below. A reader that is already gone: SIGPIPE here, the test is not started (nobody wants it).
  printf '· start %s\n' "$1" >&2
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
  # #546: cấp TMPDIR riêng đường dẫn ngắn /tmp/dk-XXXXXX (< 25 byte để không chạm trần 104 byte sun_path của AF_UNIX socket trên macOS),
  # chuyển luôn PYTHONPYCACHEPREFIX vào trong đó để python3 không đẻ __pycache__ làm bẩn cây nguồn khi chạy song song,
  # kèm shim mktemp cho trường hợp BSD mktemp trên macOS bỏ qua TMPDIR khi gọi mktemp -d trần, rồi dọn sạch ngay sau khi run_bounded.py kết thúc.
  # Cả $parallel lẫn $alone đều gọi run_one trong bash -c riêng, nên _dk_tdir giữ ở phạm vi worker (tránh local bash 3.2 bị gỡ trước trap EXIT).
  local rc=0 t0=$SECONDS
  _dk_tdir="$(mktemp -d /tmp/dk-XXXXXX 2>/dev/null)" || _dk_tdir=""
  case "$_dk_tdir" in
    /tmp/dk-?*/*|/tmp/dk-) _dk_tdir="" ;;
    /tmp/dk-?*) [ -d "$_dk_tdir" ] && [ ! -L "$_dk_tdir" ] || _dk_tdir="" ;;
    *) _dk_tdir="" ;;
  esac
  _dk_clean_tdir() {
    case "${_dk_tdir:-}" in
      /tmp/dk-?*/*|/tmp/dk-|'') return 0 ;;
      /tmp/dk-?*) [ -d "$_dk_tdir" ] && [ ! -L "$_dk_tdir" ] || return 0 ;;
      *) return 0 ;;
    esac
    rm -rf "$_dk_tdir" 2>/dev/null || {
      chmod -R u+rwX "$_dk_tdir" 2>/dev/null
      chflags -R nouchg "$_dk_tdir" 2>/dev/null
      chmod -R u+rwX "$_dk_tdir" 2>/dev/null
      rm -rf "$_dk_tdir" 2>/dev/null || true
    }
  }
  trap '_dk_clean_tdir' EXIT
  trap '_dk_clean_tdir; trap - INT EXIT; kill -INT $$' INT
  trap '_dk_clean_tdir; trap - TERM EXIT; kill -TERM $$' TERM
  trap '_dk_clean_tdir; trap - HUP EXIT; kill -HUP $$' HUP
  env -u GROK_HOOK_EVENT -u GROK_HOOK_NAME -u GROK_SESSION_ID -u DEVKIT_AGENT -u HOOK_PPID \
       -u DEVKIT_PER_TEST_CACHE -u DEVKIT_PTC -u _DEVKIT_IN_MKTEMP_SHIM -u DEVKIT_IMPACTED_DIRS \
       ${_dk_tdir:+TMPDIR="$_dk_tdir" PYTHONPYCACHEPREFIX="$_dk_tdir/pyc" PATH="$2/mkbin:$PATH"} \
       SB_HEAVY_SLOT_DIR="$o.slots" \
       ${DEVKIT_RUN_BOUNDED:+python3 -I "$DEVKIT_RUN_BOUNDED" "$DEVKIT_TEST_TIMEOUT_S" --} \
       bash "$1" >"$o.log" 2>&1 || rc=$?
  _dk_clean_tdir
  trap - EXIT INT TERM HUP
  echo "$rc" >"$o.rc"
  # B2 (audit 25/10): kết quả ghi NGAY khi test xong — một TIMEOUT của cả suite (gate giết nhóm) không còn xoá PASS đã có
  [ -n "${DEVKIT_PTC:-}" ] && python3 -I "$DEVKIT_PTC" record "$2" "$1" "$rc" >"$o.ptc" 2>&1
  # #427 / log trống khi quá 900 s (27/10): ✔/✖ chỉ in ở vòng cuối, gate giết suite thì log rỗng. Một dòng tiến độ ra stderr ngay khi
  # test xong, một printf (worker xargs song song không xé dòng); không mở đầu ✔/✖/↺, không khớp FAIL_LINE của gate, có đường dẫn test.
  # In SAU bước ghi B2: người đọc stderr đã chết (gate bị SIGKILL) thì printf nhận SIGPIPE và worker chết — PASS đã ghi trước đó.
  printf '· done rc=%s %ss %s\n' "$rc" "$((SECONDS - t0))" "$1" >&2
  return 0
}
export -f run_one
# #546: BSD mktemp trên macOS dùng _CS_DARWIN_USER_TEMP_DIR thay vì TMPDIR khi gọi mktemp / mktemp -d / mktemp -t không kèm đường dẫn;
# shim đặt trong $out/mkbin chuyển các lời gọi đó vào $TMPDIR tuyệt đối của bài test và chặn đệ quy vô hạn khi runner chạy lồng nhau.
case "${DEVKIT_REAL_MKTEMP:-}" in
  ""|*/mkbin/mktemp) DEVKIT_REAL_MKTEMP="$(PATH=/usr/bin:/bin command -v mktemp || echo /usr/bin/mktemp)" ;;
esac
if [ ! -f "$DEVKIT_REAL_MKTEMP" ] || [ ! -x "$DEVKIT_REAL_MKTEMP" ]; then
  DEVKIT_REAL_MKTEMP="$(PATH=/usr/bin:/bin command -v mktemp || echo /usr/bin/mktemp)"
fi
export DEVKIT_REAL_MKTEMP
mkdir -p "$out/mkbin"
cat >"$out/mkbin/mktemp" <<'SH'
#!/bin/sh
unset IFS
real="${DEVKIT_REAL_MKTEMP:-/usr/bin/mktemp}"
if [ "${_DEVKIT_IN_MKTEMP_SHIM:-}" = 1 ] || [ "$real" -ef "$0" ] || [ ! -f "$real" ] || [ ! -x "$real" ]; then
  for cand in /usr/bin/mktemp /bin/mktemp; do
    if [ -f "$cand" ] && [ -x "$cand" ] && [ ! "$cand" -ef "$0" ]; then
      real="$cand"
      break
    fi
  done
fi
if [ "${_DEVKIT_IN_MKTEMP_SHIM:-}" = 1 ]; then
  exec "$real" "$@"
fi
export _DEVKIT_IN_MKTEMP_SHIM=1
if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
  flags=""; prefix=""; ok=1; saw_t=0
  for a in "$@"; do
    if [ "$saw_t" = 1 ]; then
      case "$a" in ""|*/*|-*) ok=0; break ;; *) prefix="$a"; saw_t=2 ;; esac
    else
      case "$a" in
        -?*)
          rest="${a#-}"
          while [ -n "$rest" ]; do
            ch="${rest%"${rest#?}"}"
            rest="${rest#?}"
            case "$ch" in
              d|q|u) flags="$flags -$ch" ;;
              t)
                if [ "$saw_t" != 0 ]; then ok=0; break; fi
                if [ -n "$rest" ]; then
                  case "$rest" in */*|-*) ok=0 ;; *) prefix="$rest"; saw_t=2 ;; esac
                  rest=""
                else
                  saw_t=1
                fi
                ;;
              *) ok=0; break ;;
            esac
          done
          [ "$ok" = 1 ] || break
          ;;
        *) ok=0; break ;;
      esac
    fi
  done
  if [ "$ok" = 1 ] && [ "$saw_t" != 1 ]; then
    tbase="$TMPDIR"
    case "$tbase" in
      /*) ;;
      *) tbase="$(CDPATH= cd -P -- "$tbase" >/dev/null 2>&1 && pwd -P || printf '%s/%s' "$(pwd -P)" "$tbase")" ;;
    esac
    while [ "${tbase%/}" != "$tbase" ] && [ -n "${tbase%/}" ]; do
      tbase="${tbase%/}"
    done
    case "${prefix:-tmp}" in
      *XXX) tpl="${prefix:-tmp}" ;;
      *) tpl="${prefix:-tmp}.XXXXXXXXXX" ;;
    esac
    exec "$real" $flags "${tbase:-/}/$tpl"
  fi
fi
exec "$real" "$@"
SH
chmod +x "$out/mkbin/mktemp"
# helper vắng (bản kit cũ) hay không có python3: chạy trần như trước, không chặn cả lượt test
DEVKIT_RUN_BOUNDED=""
[ -f "$DK/tests/lib/run_bounded.py" ] && command -v python3 >/dev/null 2>&1 && DEVKIT_RUN_BOUNDED="$DK/tests/lib/run_bounded.py"
DEVKIT_TEST_TIMEOUT_S="${DEVKIT_TEST_TIMEOUT_S:-1800}"
case "$DEVKIT_TEST_TIMEOUT_S" in *[!0-9]*) echo "run_impacted.sh: DEVKIT_TEST_TIMEOUT_S must be whole seconds; using 1800" >&2; DEVKIT_TEST_TIMEOUT_S=1800 ;; esac
export DEVKIT_RUN_BOUNDED DEVKIT_TEST_TIMEOUT_S
# B2 (audit 25/10): sổ PASS theo từng test (tests/lib/per_test_cache.py, kho của bin/suite_cache.py, khoá = cả cây + đường dẫn test). Chỉ khi
# gate bật (DEVKIT_PER_TEST_CACHE=1: dùng lại + ghi; record: chỉ ghi — lượt sentinel / --no-cache); `agent-kit test` không đặt biến: chạy hết.
# `--list` ở trên không đổi (khoá của gate và lần kiểm lại R3 cần tập chọn đầy đủ). Helper vắng / lỗi: mọi test chạy như trước.
DEVKIT_PTC=""; reused=""
case "${DEVKIT_PER_TEST_CACHE:-}" in
  1|record) [ -f "$DK/tests/lib/per_test_cache.py" ] && command -v python3 >/dev/null 2>&1 && DEVKIT_PTC="$DK/tests/lib/per_test_cache.py" ;;
esac
export DEVKIT_PTC
if [ -n "$DEVKIT_PTC" ] && [ -n "$(printf '%s' $selected)" ]; then
  # in "reuse<TAB><test><TAB><tuổi giây>" cho test có PASS trên đúng khoá; ghi ảnh khoá cho test phải chạy (bước record của run_one)
  python3 -I "$DEVKIT_PTC" plan "$DK" "$out" $selected >"$out/ptc.plan" 2>"$out/ptc.err" \
    || echo "run_impacted.sh: per_test_cache plan exit $? — mọi test chạy" >&2
  [ -s "$out/ptc.err" ] && tail -n 5 "$out/ptc.err" | sed 's/^/run_impacted.sh: /' >&2
  reused="$(awk -F'\t' '$1 == "reuse" { print $2 }' "$out/ptc.plan" 2>/dev/null)"
fi
is_reused() { printf '%s\n' "$reused" | grep -qxF -- "$1"; }
parallel="" alone=""
for t in $selected; do
  [ -f "$t" ] || continue
  is_reused "$t" && continue
  case "$t" in */test_budgets.sh|*/test_session_context.sh|*/test_gate_lock_receipt_gap.sh|*/test_agent_kit_test_order.sh|*/test_run_impacted.sh|*/test_relink.sh|*/test_worktree_merge_gate_owner.sh) alone="$alone $t" ;; *) parallel="$parallel $t" ;; esac
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
for t in $alone; do bash -c 'run_one "$1" "$2"' _ "$t" "$out"; done
rc=0; n_reuse=0; n_ran=0
for t in $selected; do
  [ -f "$t" ] || continue
  o="$out/$(printf '%s' "$t" | tr '/' '_')"
  if is_reused "$t"; then
    age="$(awk -F'\t' -v t="$t" '$1 == "reuse" && $2 == t { print $3; exit }' "$out/ptc.plan")"
    echo "↺ $t (PASS dùng lại trên cùng cây, chạy thật $((${age:-0} / 60)) phút trước)"
    n_reuse=$((n_reuse + 1))
    continue
  fi
  n_ran=$((n_ran + 1))
  [ -s "$o.ptc" ] && sed 's/^/    /' "$o.ptc"
  if [ "$(cat "$o.rc" 2>/dev/null)" = 0 ]; then
    echo "✔ $t"
  else
    echo "✖ $t"; tail -n 20 "$o.log" 2>/dev/null | sed 's/^/    /'; rc=1
  fi
done
# #472 D: hit-rate của sổ per-test (post-fix-gate đọc dòng này ghi vào runs.jsonl); chỉ khi sổ bật
[ -n "$DEVKIT_PTC" ] && echo "per_test_cache: reuse=$n_reuse ran=$n_ran"
exit "$rc"
