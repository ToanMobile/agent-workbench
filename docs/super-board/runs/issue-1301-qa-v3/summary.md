# QA v3 — issue #1301, PR #1305, head de87fb2d

- test_review_gate_round_cap.sh: C1–C6 xanh (14 ca, exit 0), gồm 4 ca R2 mới (`P1: no P0 handling…`, `P1: thiếu kiểm tra, không có P0 nào khác`, `P0: auth bypass; không P1`, `P1: x=0 P0 path`) vẫn bị giữ.
- RED: cùng test trên hook của origin/main thì 4 ca đỏ.
- 13 test `test_review_gate*.sh` đều exit 0; post-fix-gate --scoped: exit 0.
- AC1 (C1), AC2 (C2, C4, C5), AC3 (C3); phủ định đúng nhãn vẫn sạch (C6). Bounce R2 đã đóng.
- Test gap (không viết): trần đếm theo cả phiên, chưa theo từng bộ file (ponytail của builder).
