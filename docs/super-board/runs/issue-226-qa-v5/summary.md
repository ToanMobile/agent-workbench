# QA v5 — #226 gap 7 (PR #340), đã gộp origin/main 4bd1d0c0

- Lệnh: `bash tests/super-board/test_merge_gate_verified_tree.sh` → exit 0, 13/13 ✔.
- Đột biến: tắt đọc biên nhận ở merge gate (dòng 460) → 7 ✖ (ĐỎ); khôi phục → xanh, cây sạch.
- Gate: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 83/83.
- Biên nhận: `super-board-verify-cmd.sh --record` ghi trên cây gộp sạch, sau gate xanh (trước commit bằng chứng).
- Chưa kiểm: lỗi exit 5 rỗng `conflicts:` của merge gate (stderr bị nuốt ~dòng 441) ngoài phạm vi gap 7; số đo AC7 chưa đo.
