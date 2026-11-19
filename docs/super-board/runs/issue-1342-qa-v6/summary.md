# QA #1342 v6 @ e522dec5
- test_evidence_readonly_turn.sh: exit 0 (cả ca ghi -nOsh, -On, -inOsh bị chặn; ca đọc vẫn qua)
- test_evidence_gate_linear.sh: exit 0
- Probe thêm 12 lệnh ghi/chạy chương trình (sort --compress-program, rg --hostname-bin, git log --output f, git -nOsh, blame/cat-file --textconv...): đều bị chặn; wc --files0-from chỉ đọc nên được qua (đúng).
