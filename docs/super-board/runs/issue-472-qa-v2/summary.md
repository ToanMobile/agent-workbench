# QA #472 v2 (rebuild 0847ff30, đã merge origin/main 7fda00d1)
Lệnh: bash universal-agent-devkit/tests/gates/test_gate_{per_test_cache_hit_rate,speed_next_*,approval_content_hash}.sh
Kết quả: 5/5 PASS (cả có và không có GATE_SPEED_NEXT=1).
AC1 test_gate_speed_next_full_merge_point.sh · AC2 test_gate_speed_next_untested_early.sh
AC3 test_gate_approval_content_hash.sh · AC4 test_gate_per_test_cache_hit_rate.sh
AC5 test_gate_speed_next_run_log_fields.sh · AC6: có 3 file test_gate_speed_next_*.sh (AC ghi 5), không file nào còn skip.
Gate: post-fix-gate.py --run-tests --brief --auto-approve-tests (run_impacted.sh: chỉ thêm bộ đếm, không nới assertion): 11/12, exit 1.
Suite đỏ: test_gate_stop_reuse_race.sh. Chạy riêng 6 lần: base 7fda00d1 = 0 PASS / 6 đỏ; nhánh = 5 PASS / 1 đỏ.
=> đỏ cả trên base, không nằm trong diff (thẻ #561). test_worktree_merge_gate_trunk.sh đỏ 1 lần dưới tải gate, riêng lẻ 3/3 xanh.
