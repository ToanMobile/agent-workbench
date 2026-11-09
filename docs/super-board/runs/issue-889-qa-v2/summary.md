# QA #889 v2 — PR #1075 (head af0b5563, rebuild 1)
- Test mới test_merge_policy_upper_case_sensitive_delete.sh: bản main ĐỎ (FAILS=6: .ENV, app.KEYSTORE, Google-Services.json, .Env.local, Release.JKS, tự khai **/.env* vs .ENV); head XANH (PASS), exit 0.
- Sửa R1/R2: protected_paths tự khai THAY mặc định (.ENV vẫn auto khi tự khai docs/Keep/**); tự khai **/.env* chặn .ENV; docs/Keep/a.md bị chặn; [] vẫn tắt cổng.
- Đối chứng: docs/keystore-notes.md vẫn auto. 7 test test_merge_policy_*.sh cũ: OK cả 7, không bị sửa.
- Gate post-fix-gate.py --run-tests --scoped --brief --json trên head (origin/main đã up to date): qa-exit2 = pass, exit 0.
- Security: diff nhỏ, chỉ thu hẹp phần nhạy cảm theo protected, fail-closed khi mặc định; không lỗ hổng khai thác được.
- Giao diện: không đổi, không cần ảnh.
