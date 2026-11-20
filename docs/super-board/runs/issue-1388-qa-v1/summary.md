# QA #1388 v1 (PR #1389)
- AC1 test ĐỎ→XANH: `bash universal-agent-devkit/tests/verification/test_devkit_incident_dirty_main.sh` exit 0 (PASS); cùng assert trên devkit_incident.py của origin/main exit 1 ("base classifies it as incident").
- AC2: dòng `self-reload: ... uncommitted edits in the way` → classify_board = None; lỗi kit thật cùng luật (cannot create worktree, ff-only hỏng) vẫn thành sự cố.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `pass` (exit 0), chạy sau merge origin/main (đã up to date).
- Không sửa test cũ.
