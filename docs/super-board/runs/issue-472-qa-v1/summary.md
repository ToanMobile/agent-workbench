# QA #472 v1

- AC4: test_gate_per_test_cache_hit_rate.sh exit 0, 3 ca (ptc_reuse/ptc_ran vào runs.jsonl; không bật sổ thì không in dòng).
- AC2, AC5: test_gate_speed_next_untested_early.sh và test_gate_speed_next_run_log_fields.sh exit 0, có và không có GATE_SPEED_NEXT=1.
- AC1: test_gate_speed_next_full_merge_point.sh exit 0.
- AC3: test_gate_approval_content_hash.sh đã có trên main.
- AC6: chỉ có 3 file test_gate_speed_next_*.sh (không phải 5), không file nào còn skip.
- Gate post-fix-gate --run-tests --brief --auto-approve-tests, nhánh đã merge origin/main: exit 0, 12/12.
- Lần đầu đỏ 1 suite: test_gate_stop_reuse_race.sh ca K1 (setup went wrong), flaky: chạy lại 3 lần pass/fail/pass trên cùng cây, file không nằm trong diff; gate sau xanh.
- Không có UI: không cần ảnh.
