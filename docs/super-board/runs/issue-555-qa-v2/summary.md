# QA #555 v2 (head 7a085626, origin/main đã nằm trong nhánh)
Lệnh: `bash universal-agent-devkit/tests/verification/test_instincts_file_context.sh` → exit 0 (PASS)
Lệnh: `bash universal-agent-devkit/hooks/tests/hook_contract_test.sh` → 692 ok, 0 deviating (gồm 2 ca instincts_file_context)
ĐỎ trên base: `hooks/instincts_file_context.py` không có ở origin/main nên test không chạy được trước PR.
Lệnh: `super-board-qa-report.py --meta <PR 610>` → exit 0 (4/4 AC có dòng bằng chứng; lỗi merge-queue vòng 1 đã hết).
Đăng ký hook: hooks.json, templates/claude_settings.json, .claude/settings.json đều Read|Edit, timeout 5, .sh có +x.
AC1-AC4: PASS. Gate `post-fix-gate.py --run-tests --brief` → exit 0 (4/4).
