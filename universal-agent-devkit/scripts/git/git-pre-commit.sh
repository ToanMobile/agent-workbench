#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# git-pre-commit.sh — body of the git pre-commit hook written by
# `agent-kit githooks install`. The hook file in .git/hooks only execs this
# script, so the logic updates together with the DevKit.
#
# Runs `post-fix-gate.py --staged`: the gate's static checks (secrets and
# forbidden files, lazy placeholders, floating / http:// dependencies, perf,
# swallowed errors, raw logging) on the STAGED content — also for commits made
# outside any agent (terminal, IDE). No suite runs by default (DEVKIT_PRECOMMIT_TESTS=0):
# the task gate and merge gate run them. =light runs the matrix suites the staged files
# touch, when quick: not Gradle/Unity/xcodebuild, last recorded run ≤ 30 s, 120 s in all, a
# hang (> 60 s) warns instead of blocking; =all adds heavy ones (DEVKIT_PRECOMMIT_MAX_S,
# _BUDGET_S, _TEST_TIMEOUT). Acceptance stays `postfix-gate --run-tests --scoped`.
#
# Blocks (exit 1) on a REJECT, and fails closed when the gate cannot give a
# verdict (no python3, crash, git error): an unchecked commit is not a clean one.
# Skip once: git commit --no-verify    Disable: DEVKIT_PRECOMMIT=0
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u
[ "${DEVKIT_PRECOMMIT:-1}" = "0" ] && exit 0

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[ -d "$DEVKIT_ROOT/profiles" ] || DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$DEVKIT_ROOT/scripts/governance/i18n.sh" 2>/dev/null || source "$DEVKIT_ROOT/scripts/i18n.sh"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$PWD"
DEVKIT_LANG="$(devkit_resolve_lang "" "$ROOT")"; export DEVKIT_LANG

blocked() {
  echo "✖ DevKit pre-commit: $1" >&2
  echo "  $(L "Bỏ qua 1 lần: git commit --no-verify" "Skip once: git commit --no-verify")" >&2
  exit 1
}

# #365: chỉ CẢNH BÁO (stderr, luôn exit 0) — danh sách chỉ gợi ý thứ tự chạy test, thiếu dòng không bao giờ chặn commit
[ ! -f "$DEVKIT_ROOT/scripts/git/check-test-durations.sh" ] || bash "$DEVKIT_ROOT/scripts/git/check-test-durations.sh"

command -v python3 >/dev/null 2>&1 \
  || blocked "$(L "không có python3 — không quét được secret, commit bị chặn." "python3 not found — cannot scan for secrets, commit blocked.")"

# Gate speed v26 item 2: no suite at commit unless asked (the task gate and merge gate run them).
export DEVKIT_PRECOMMIT_TESTS="${DEVKIT_PRECOMMIT_TESTS:-0}"
# #828: a pathspec commit runs this hook on a temp index; suite_env drops GIT_INDEX_FILE, so hand it to agent-health under its own name.
unset DEVKIT_PRECOMMIT_INDEX   # R3: never inherit a stale value from the caller
if [ -n "${GIT_INDEX_FILE:-}" ] && _idir="$(cd "$(dirname "$GIT_INDEX_FILE")" 2>/dev/null && pwd -P)"; then
  export DEVKIT_PRECOMMIT_INDEX="$_idir/$(basename "$GIT_INDEX_FILE")"
fi
OUT="$(CLAUDE_PROJECT_DIR="$ROOT" python3 "$DEVKIT_ROOT/bin/post-fix-gate.py" --staged --json 2>&1)"
RC=$?
LAST="$(printf '%s\n' "$OUT" | tail -n 1)"
# The verdict comes from the gate's JSON line, not the exit code alone: exit 2 also
# means "bad arguments / git failed", which must not let a commit through.
STATE="$(printf '%s' "$LAST" | python3 -I -c 'import json,sys
try: d = json.load(sys.stdin)
except ValueError: sys.exit(0)
if d.get("mode") != "staged": sys.exit(0)
print("reject" if d.get("static_ok") is not True or d.get("tests_ok") is False
      else "unreadable" if d.get("unreadable") else "clean")' 2>/dev/null)"

REPORT="$(printf '%s\n' "$OUT" | sed '$d')"
case "$RC:$STATE" in
  3:clean)
    exit 0 ;;  # nothing of the user's staged (only DevKit links)
  2:clean)
    case "$DEVKIT_PRECOMMIT_TESTS" in
      light|all|1)   # 1 = light (post-fix-gate run_precommit_tests)
        printf '%s\n' "$REPORT" | grep -E "Suite (nhẹ|không)|Light suites|Suites (not|that)" || true
        echo "✔ DevKit pre-commit: $(L "kiểm tĩnh sạch + suite của file đã stage XANH (còn lại: gate của task / merge gate / heavy gate)" "static checks clean + suites of the staged files green (the rest: task gate / merge gate / heavy gate)")" ;;
      *)
        echo "✔ DevKit pre-commit: $(L "kiểm tĩnh sạch, không chạy suite (no suites run; DEVKIT_PRECOMMIT_TESTS=light để chạy)" "static clean, no suites run (DEVKIT_PRECOMMIT_TESTS=light to run them)")" ;;
    esac
    exit 0 ;;
  2:unreadable)
    printf '%s\n' "$REPORT" >&2
    blocked "$(L "có file đã stage không đọc được để quét." "some staged files could not be read for scanning.")" ;;
  1:reject)
    printf '%s\n' "$REPORT" >&2
    blocked "$(L "gate REJECT — sửa các điểm trên rồi commit lại." "gate REJECT — fix the findings above and commit again.")" ;;
  *)
    printf '%s\n' "$OUT" >&2
    blocked "$(L "gate không đưa ra kết luận (exit $RC) — commit bị chặn." "the gate gave no verdict (exit $RC) — commit blocked.")" ;;
esac
