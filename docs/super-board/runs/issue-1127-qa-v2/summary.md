# QA #1127 v2 (head 43c69b4e + merge origin/main)

- Test mới: `test_linked_memo.sh` rc=0, `test_mentions_no_compile.sh` rc=0, `test_turn_start_reverse.sh` rc=0.
- AC2 ĐỎ→XANH: gỡ nhánh chuyển ngân sách qua biên giờ trong `proof_gate.sh` → hàng `[2,2,2,2]`, rc=1; bản PR → `[2,2,release,release]`, rc=0 (biên giữa giờ và 00:00 UTC).
- AC1 cục bộ (load ~19): `test_budgets.sh` prompt hook 86/76/100 ms CPU (trần 110, rc=0 cả 3 lần). Chưa có 3 lần CI macOS (PR chỉ có GitGuardian).
- Gate `--scoped`: exit 2 = `review` (test cũ `test_turn_start_reverse.sh` bị sửa, chờ duyệt chéo).
