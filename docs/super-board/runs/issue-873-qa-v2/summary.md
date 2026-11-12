# QA v2 #873 — head 70dde1a2 (đã merge origin/main)

- `bash universal-agent-devkit/tests/gates/test_guard_secrets_residual.sh` → exit 0 (XANH, gồm 2 ca R1 mới: `{` không đóng 64 KB < 3 s, bí mật sau chữ chậm vẫn deny)
- `bash universal-agent-devkit/tests/gates/test_guard_secrets.sh` (cũ, không bị sửa) → exit 0
- Cùng file residual chạy trên hook của main (biến GUARD trỏ về bản main) → exit 1 (ĐỎ)
- Thăm dò hiệu năng thủ công (hook của PR): 20k từ `{a,`, 20k glob, 10k ANSI-C, 5k `find -name` kèm `-exec`, một từ 60 KB rồi tên bí mật → mỗi lệnh < 0,1 s; bí mật sau chữ chậm vẫn deny
- Lệnh thường ngày (`grep -rn 'foo.*bar' | sed`) vẫn allow
- Gate scoped: xem `[qa] [report]` trên PR
