# QA v3 · issue #1300 · PR #1307 · đầu 225a80d6 (đã gộp origin/main, không có gì mới)

Lệnh: `bash tests/super-board/<test>.sh` (3 file), rồi gate scoped.

- test_qa_report_redos_timeout.sh: ALL PASS (kể cả ca `AC` + 32000 dấu cách, AC2 / AC 2 / AC - 2 / AC-#2 / ac  -  3 vẫn exit 1)
- test_qa_report_cross_repo_ac.sh: PASS
- test_merge_gate_qa_report.sh: ALL PASS
- Đo độc lập 6 regex của checker trên chuỗi 32000 ký tự bất lợi: không regex nào quá 0,3 s;
  OTHER_REPO_AC trên `(repo:x` lặp 65k ký tự = 0,30 s (nhẹ, ghi nhận, không chặn).
- Diff merge gate: cả hai lời gọi checker bọc `timeout`, rc 124 thành exit 7 + `qa-report: timeout`.
