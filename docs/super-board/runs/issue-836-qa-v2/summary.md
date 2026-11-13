# QA #836 v2 — PR #1089 @ 434a604a

Lệnh: bash universal-agent-devkit/tests/gates/<test>.sh (từng file)
- test_gate_since_renamed_weakened.sh: exit 0, 3/3 (đổi tên + bỏ assertion bị liệt kê, exit 2; R100 và đổi tên + nối thêm không bị liệt kê)
- test_gate_renamed_test_edit.sh: exit 0
- test_gate_since_test_edit.sh: exit 0
- test_gate_since_new_test.sh: exit 0
- test_gate_since_trunk_merge.sh: exit 0

Gate: post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh
- Kết quả: pass, exit 0 (đã merge origin/main: Already up to date)

ĐỎ trước sửa: lấy từ QA v1 (post-fix-gate.py của origin/main ĐỎ, exit 1, flagged=no); lần này không chạy lại vì hook chặn git checkout --.
Ảnh: không cần (backend gate).
