# QA #103 v1 — preflight không sequence vì file kế hoạch
- Head: 29ceff3d
- Bản cũ (origin/main): `test_preflight_source_path.sh` exit 1, 2 ca ĐỎ (#99 sequence vì docs/plans, #804 sequence)
- Bản sửa: `test_preflight_source_path.sh` exit 0 (6/6 ca)
- Hồi quy: `test_preflight_too_big.sh` exit 0
- AC1 (#94/#99/#100 không sequence vì docs/plans): PASS
- AC2 (cùng file mã trong Where vẫn sequence): PASS (#802 sau #801)
- AC3 (ĐỎ trước, XANH sau): PASS
