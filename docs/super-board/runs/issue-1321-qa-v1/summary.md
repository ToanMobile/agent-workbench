# QA #1321 v1 — PASS
Test: bash tests/super-board/test_preflight_session_no_ac.sh
- Runner cũ (origin/main): exit 1, pass=2 fail=3 (RED: không Backlog, có comment [blocker], Blocked)
- Runner PR: exit 0, pass=5 fail=0 (GREEN)
Gate: post-fix-gate --run-tests --scoped --brief --json | qa-exit2.sh => pass (exit 0), sau khi merge origin/main
AC1: thẻ session thiếu AC → không dispatch, về Backlog, không comment (A x4 GREEN, RED trên runner cũ)
AC2: thẻ không nhãn session → vẫn Blocked + comment (B GREEN)
Security pass: diff 11 dòng, issue qua --argjson, không đường injection.
