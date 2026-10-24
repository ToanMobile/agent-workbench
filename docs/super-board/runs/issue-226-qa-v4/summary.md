# QA v4 — #226 gap 7 (PR #340), head c2f48f36 gộp origin/main 073760fe

- Lệnh: `bash tests/super-board/test_merge_gate_verified_tree.sh` → exit 0, 13/13 ✔ (R4/R5 đã có).
- Đột biến: tắt đọc biên nhận trong merge gate → 7 ✖ (ĐỎ); khôi phục → xanh.
- Gate: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 82/82.
- Biên nhận: `super-board-verify-cmd.sh --record` ghi trên cây gộp sạch (88da6969…), sau gate xanh.
- Thread `[builder]`/`[qa]` mở: 0 (R1 đã resolve).
- Chưa kiểm: R4 (kit thiếu cả hai nơi) chưa có test riêng; số đo AC7 chưa đo.
