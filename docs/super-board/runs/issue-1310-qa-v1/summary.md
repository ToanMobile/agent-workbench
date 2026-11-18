# QA #1310 / PR #1313 (v1)
- Lệnh: bash tests/super-board/test_queue_ac_autofix_1310.sh → exit 0, 10/10 ✔ (A1, A1b, A2, A3, B x4, B2 x2)
- RED trên main (2 file bin đặt về origin/main): 5 FAILED (A1, A1b, B x3)
- Gate: post-fix-gate.py --run-tests --scoped --brief --json → qa-exit2 = pass (head f07caba0 + merge origin/main: already up to date)
- Không UI: không ảnh.
