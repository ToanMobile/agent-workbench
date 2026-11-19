# QA #1342 v7 @ 4e35b706
- test_evidence_readonly_turn.sh: exit 0 (ca ghi bị chặn, ca đọc vẫn qua)
- test_evidence_gate_linear.sh: exit 0; test_platform_rules.sh: exit 0
- AC1-AC6, AC8 đọc lại trên head: Convergence có đủ, Pre-existing có, run.md có dòng trỏ, SKILL.md không đổi (19850 ký tự), REPORTED 0 bug.
- Probe 440 lệnh ghi/chạy chương trình/đọc qua khung của test_evidence_readonly_turn.sh: 188 lệnh được coi là đọc, đã rà tay từng lệnh, không có lệnh ghi hay chạy chương trình lọt qua (git/gh/rg/sort/sed/date/find/awk/tee/redirect/env/lệnh trong nháy đều bị chặn).
