# QA #1300 v5 — PR #1307 @ 0be5b009 (đã chứa origin/main 0db083c9)
- test_qa_report_redos_timeout.sh: exit 0, ALL PASS (`a.` x 32000 = 0 s, vẫn exit 1 khi nêu AC; checker treo -> gate exit 7 + `qa-report: timeout` sau 3 s; names_ac 3000x30000 = 1 s)
- test_qa_report_cross_repo_ac.sh: exit 0, PASS
- test_merge_gate_qa_report.sh: exit 0, ALL PASS
- Gate scoped: xem comment [qa] [report] (exit ghi ở đó)
