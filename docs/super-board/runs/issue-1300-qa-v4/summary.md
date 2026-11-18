# QA v4 · issue #1300 · PR #1307 · đầu a4cbe95f (đã gộp origin/main, AC_ID dùng `\s{0,3}` của main)

Lệnh: `bash tests/super-board/<test>.sh` (3 file), rồi `post-fix-gate.py --run-tests --scoped --brief`.

- test_qa_report_redos_timeout.sh: ALL PASS (`a.` x 32000 = 0 s, vẫn exit 1 khi nêu AC; checker treo thì gate exit 7 + `qa-report: timeout` sau 3 s; 3000 AC x 30000 vế = 1 s; `AC` + 32000 dấu cách = 0 s; AC2 / AC 2 / AC - 2 / AC-#2 / ac  -  3 vẫn exit 1)
- test_qa_report_cross_repo_ac.sh: PASS
- test_merge_gate_qa_report.sh: ALL PASS
- Đo độc lập: CROSS_REPO_REF trên `a.` x 32000 = 0,02 s; AC_ID `\s{0,3}` trên `AC`/`AC-`/`AC#` + 32000 dấu cách = 0,0 s (tự đo).
- Gate scoped: exit 0, 3/3 test hồi quy, core-touched (merge-gate.sh, qa-report.py).
