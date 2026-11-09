# QA #889 v1 — PR #1075 (head c07bb4a5)
- Test mới test_merge_policy_upper_case_sensitive_delete.sh: bản main ĐỎ (FAILS=5: .ENV, app.KEYSTORE, Google-Services.json, .Env.local, Release.JKS lọt cổng); head XANH (PASS), exit 0.
- Đối chứng: docs/keystore-notes.md vẫn auto; protected_paths tự khai vẫn phân biệt hoa thường; protected_paths=[] vẫn tắt cổng.
- 7 test test_merge_policy_*.sh cũ: ok cả 7, không bị sửa.
- Gate post-fix-gate.py --run-tests --scoped --brief --json trên head đã merge origin/main (đã up to date): pass, exit 0.
- Security pass: diff 3 dòng, chỉ thêm khớp (fail-closed), không có lỗ hổng khai thác được.
- Test gap: không có gap High; Medium: chưa test đường dẫn C-quoted viết hoa (đã được #872 phủ riêng).
