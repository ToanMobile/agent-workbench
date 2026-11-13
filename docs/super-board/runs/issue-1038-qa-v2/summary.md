# QA #1038 v2 — head ff2744ae (đã up-to-date với origin/main)
- `bash tests/super-board/test_github_read_auto_reconcile.sh` → exit 0, 7/7 ca (AC1–AC3)
- `python3 tests/super-board/test_super_board_all_slots.py` → exit 0, PASS (AC4: banner theo len(REPOS))
- `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `pass`, exit 0
- `super-board-ac-check.py --branch issue-1038-halt-reconcile` → exit 0, issue_ac 4 / pr_ac 4 (sb:ac đủ 4 dòng)
- Test cũ không bị sửa; mã không đổi so với v1.
