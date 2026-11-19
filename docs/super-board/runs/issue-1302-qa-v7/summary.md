# QA #1302 v7 @ b1583607

- `bash tests/super-board/test_qa_head_settle_1302.sh` → exit 0 (PASS, cases 1-14)
- `bash tests/super-board/test_setup_bin_list.sh` → exit 0 (63 script)
- Đột biến: bỏ kiểm `extra` trong `super-board-qa-sync.sh` → test exit 1 (ĐỎ), đã khôi phục
- Gate `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` → `pass`
- Sửa major của reviewer: run.md 5b gọi `super-board-qa-sync.sh`, không còn reset --hard / branch -f; case 13 chạy qua hook
