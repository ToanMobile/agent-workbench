# QA #21 v1 — agent-health không báo 100/100 khi cấu hình rỗng

Lệnh: `bash universal-agent-devkit/tests/installer/test_agent_health_score_inflation.sh`
- Bản sửa (PR #130): exit 0 — thiếu pre-commit 100→96; `"hooks": {}` 100→96.
- Bản cũ (`agent-health.py` của origin/main, thay tại chỗ rồi khôi phục): exit 1 — cả hai ca vẫn 100/100 (RED).
Hồi quy: `test_health_githook_chain.sh` exit 0, `test_agent_health.sh` exit 0, `test_agent_health_broken_tracked_link.sh` exit 0.

AC1 (thiếu pre-commit không đạt 100): ✅ · AC2 (hooks rỗng không đạt chuẩn): ✅
Ghi chú: mục (c) trong Context (`trust["problem"]` truyền `True` cố định) không nằm trong AC, PR không đổi; không chặn.
