# QA v8 — #1302 (PR #1304)
Head QA chạy: 2d659ef5 (khớp ls-remote; đã merge origin/main: Already up to date).
- `bash tests/super-board/test_qa_head_settle_1302.sh` → exit 0, PASS (case 1–18).
- `bash tests/super-board/test_setup_bin_list.sh` → exit 0, PASS (63 script).
- Đột biến: dòng 50 `super-board-qa-sync.sh` đổi `|| exit 11` thành `|| true` → test exit 1 (ĐỎ); đã khôi phục, cây sạch.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `pass`.
- Đọc `super-board-qa-sync.sh`: 3 major của reviewer (lỗi git không bị nuốt, merge main không tính extra, tạo nhánh khi chưa có) đều có trong mã.
