# QA v4 — issue #620 (sau rebuild-2, head cfd3a1f)

- origin/main đã merge: Already up to date
- test_merge_train_single_test_retry.sh: exit 0 (một ghi chú flaky mỗi PR)
- test_instincts_archive.sh: exit 0 (archive lưu text mới dưới khoá)
- test_setup_bin_list.sh (REG-SB-SETUP-BIN-01, lỗi của train): exit 0, đã kiểm 51 script
- post-fix-gate --run-tests --scoped --brief: exit 0, hồi quy 155/155
- Chạy với env -u SB_BOARD_WORKER (#528)
