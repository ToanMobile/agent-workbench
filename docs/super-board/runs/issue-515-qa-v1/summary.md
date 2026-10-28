# QA #515 v1 — agent-health: file kit bị ghi đè/xoá

Nhánh `issue-515-health-kit-overwrite` đã merge `origin/main`.

| AC | Kết quả |
|---|---|
| 1. Ghi đè qua symlink: RED trước, health đỏ nêu đúng file sau | PASS: base 4 fail, head 7/7 |
| 2. Xoá `scripts/testing/capture_3d_proof.py` thì health đỏ | PASS |
| 3. Kit sạch không báo oan; gate exit 0 | PASS: repo thật không có mục đỏ, gate 3/3 |

Lệnh: `bash universal-agent-devkit/tests/installer/test_agent_health_kit_overwritten.sh` → exit 0.
RED: `agent-health.py` của origin/main + cùng test → 4 fail (không báo, không lệnh khôi phục, không đỏ).
Gate: `post-fix-gate.py --run-tests --brief` → PASS, 3/3 hồi quy.
Giới hạn đã biết (từ builder): ghi đè đã `git add` thì không bị bắt.
