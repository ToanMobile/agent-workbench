#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# git-pre-commit.sh — body of the git pre-commit hook written by
# `agent-kit githooks install`. The hook file in .git/hooks only execs this
# script, so the logic updates together with the DevKit.
#
# Runs `post-fix-gate.py --staged`: the gate's static checks (secrets and
# forbidden files, lazy placeholders, floating / http:// dependencies, perf,
# swallowed errors, raw logging) on the STAGED content — also for commits made
# outside any agent (terminal, IDE). Then the matrix suites the staged files touch,
# when quick: not Gradle/Unity/xcodebuild, last recorded run ≤ 30 s, 120 s in all, a
# hang (> 60 s) warns instead of blocking (DEVKIT_PRECOMMIT_TESTS=all | 0,
# DEVKIT_PRECOMMIT_MAX_S, _BUDGET_S, _TEST_TIMEOUT). The rest stays `postfix-gate --run-tests`.
#
# Blocks (exit 1) on a REJECT, and fails closed when the gate cannot give a
# verdict (no python3, crash, git error): an unchecked commit is not a clean one.
# Skip once: git commit --no-verify    Disable: DEVKIT_PRECOMMIT=0
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u
[ "${DEVKIT_PRECOMMIT:-1}" = "0" ] && exit 0

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$DEVKIT_ROOT/scripts/i18n.sh"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$PWD"
DEVKIT_LANG="$(devkit_resolve_lang "" "$ROOT")"; export DEVKIT_LANG

blocked() {
  echo "✖ DevKit pre-commit: $1" >&2
  echo "  $(L "Bỏ qua 1 lần: git commit --no-verify" "Skip once: git commit --no-verify")" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 \
  || blocked "$(L "không có python3 — không quét được secret, commit bị chặn." "python3 not found — cannot scan for secrets, commit blocked.")"

OUT="$(CLAUDE_PROJECT_DIR="$ROOT" python3 "$DEVKIT_ROOT/bin/post-fix-gate.py" --staged --json 2>&1)"
RC=$?
LAST="$(printf '%s\n' "$OUT" | tail -n 1)"
# The verdict comes from the gate's JSON line, not the exit code alone: exit 2 also
# means "bad arguments / git failed", which must not let a commit through.
STATE="$(printf '%s' "$LAST" | python3 -c 'import json,sys
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
    printf '%s\n' "$REPORT" | grep -E "Suite (nhẹ|không)|Light suites|Suites (not|that)" || true
    echo "✔ DevKit pre-commit: $(L "kiểm tĩnh sạch + suite nhẹ của file đã stage XANH (suite nặng: cổng Stop / nightly)" "static checks clean + light suites of the staged files green (heavy suites: Stop gate / nightly)")"
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
