# QA #880 v1 — guard push residual
- Lệnh: bash universal-agent-devkit/tests/gates/test_guard_protected_push_residual.sh
- Trên hook của origin/main: exit 1, 5 ca ✖ (a, b×3, c); 2 đối chứng ALLOW ✔
- Trên đầu PR (đã merge origin/main): exit 0, 8/8 ✔
- test_guard_protected_push, test_guard_protected_push_wrappers: 0 ca ✖
- Log thô: /tmp (ngoài nhánh)
