# QA #1127 v4 (PR #1157, head 1bfc3252 + merge origin/main)
- test_import_lazy_regex.sh: main -> rc=1 (import compile 62 regex); PR -> rc=0 (8 regex). ĐỎ→XANH.
- test_linked_memo.sh, test_mentions_no_compile.sh: rc=0.
- test_budgets.sh (load ~34): prompt hook 105 ms CPU (trần 110, không đổi), rc=0.
- Rà diff: 44 regex -> _lazy(); không chỗ nào dùng .pattern/re.*(RE) trực tiếp. Security pass: không có bề mặt mới.
- AC1 (3 lần CI macOS liên tiếp): chưa có CI; chỉ đo cục bộ.
