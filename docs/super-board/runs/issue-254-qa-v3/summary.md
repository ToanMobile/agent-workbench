# QA #254 vòng 3 (sau rebuild R2–R5)
- Test mới `tests/super-board/test_builder_already_met_and_model_tier.sh`: RED trên runner của main (exit 1, 3 lỗi: thiếu model_tier, thiếu --model 0/2, CLOSED→Ready), GREEN trên nhánh (exit 0).
- `test_runner_lanes.sh`, `test_runner_reclaim_dead_build.sh`: exit 0.
- Gate `--full --diff origin/main --brief`: exit 0, hồi quy 57/57 (đã merge origin/main mới nhất).
- Lần gate đầu đỏ 1 suite: REG-SB-RUNNER-WATCHDOG-01 (flake dưới tải, 84s); chạy riêng exit 0, gate chạy lại 57/57.
- Ảnh: không cần — thay đổi chỉ là script/tài liệu/test, không lên màn hình.
