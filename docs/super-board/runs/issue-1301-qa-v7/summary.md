# QA v7 · #1301 · PR #1305 · head 127b616d (đã chứa origin/main)
- Lệnh: `bash universal-agent-devkit/tests/gates/test_review_gate_round_cap.sh` → exit 0, 33 ca xanh (C1–C10), gồm C9 `OAuth2.py`, `auth0.js` giữ (bounce R9 đã đóng).
- RED: cùng test trên hook của origin/main → exit khác 0.
- 12 test `test_review_gate*.sh` còn lại: exit 0 (tự chạy).
- AC1: C1, C8.3 · AC2: C2, C4, C5, C8.2, C8.5, C9 · AC3: C3, C8.1, C10.1.
- Test gap (không viết): trần đếm theo cả phiên, chưa theo từng bộ file (ponytail R10/R11 của builder).
- Gate scoped: xem comment (chạy sau commit bằng chứng).
