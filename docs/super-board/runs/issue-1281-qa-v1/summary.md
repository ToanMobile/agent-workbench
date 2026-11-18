# QA #1281 v1 (PR #1282, head 81ab986b)
- ĐỎ trên runner của origin/main: `test_runner_self_reload_absorbed.sh` exit 1, in đúng dòng `self-reload: ... git merge --ff-only origin/main failed (uncommitted edits in the way?)`.
- XANH trên PR: `test_runner_self_reload_absorbed.sh` exit 0 (2/2); `test_runner_self_reload.sh` exit 0 (all passed).
- Ca sửa tay khác origin vẫn giữ và cảnh báo (không mất việc người).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` = `pass` (sau khi merge origin/main, đã up to date).
- Không sửa test cũ, không có ảnh (không phải UI).
