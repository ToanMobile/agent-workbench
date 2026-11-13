# QA #873 v1 (PR #1095)
- Test mới `test_guard_secrets_residual.sh` trên hook của main: 20 ca ĐỎ. Trên head: XANH, exit 0.
- `test_guard_secrets.sh` (cũ, không bị sửa): XANH.
- Đối chiếu 24 lệnh (tiền tố+dotenv+hậu tố, comment, heredoc): head không lỏng hơn main (looser: 0).
- Không còn fnmatch trên mẫu người dùng; glob 64 KB phán < 3 s.
- Gate scoped trên head đã merge main: pass (exit 0).
