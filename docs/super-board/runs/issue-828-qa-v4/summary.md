# QA #828 v4 — head b57a7ba5 + origin/main 5e9118d5

- Lệnh: `bash universal-agent-devkit/tests/installer/test_agent_health_kit_overwritten.sh` → exit 0, 15/15 ✔
- ĐỎ: đặt lại `agent-health.py` của origin/main → exit 1, 2 ca ✖ (`a kit file staged in the commit's temp index is reported (#828)`, `real pathspec commit: the committed kit file was reported (R2)`); khôi phục → XANH
- Đột biến: xoá dòng `export DEVKIT_PRECOMMIT_INDEX=` trong git-pre-commit.sh → exit 1 (hook lỗi cú pháp, ca R2 đỏ); khôi phục → XANH
- AC1 (pathspec không REJECT oan) ✔ · AC2 (file kit ngoài commit vẫn đỏ, giữ #462) ✔ · AC3 gate scoped: xem comment [qa] [report]
- Không phải UI, không có ảnh.
