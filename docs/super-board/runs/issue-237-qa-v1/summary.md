# QA #237 v1 — worker chết im lặng (PR #244)

Kết quả: PASS. Không có ảnh (thay đổi backend/runner, không lên màn hình).

## Lệnh và kết quả
- `bash tests/super-board/test_worker_death_record.sh` → exit 0, ALL PASS (A, B, C, D, E, F, G1, G2).
- `test_runner_build_workers.sh`, `test_runner_lane_workers.sh`, `test_runner_lanes.sh` → exit 0, all passed.
- `post-fix-gate.py --run-tests --full --brief --diff origin/main` (sau khi gộp origin/main) → exit 0, 57/57.

## AC
- [x] SIGKILL giữa chừng → log có `worker_exit: exit=137 signal=KILL elapsed=…s`; reap ghi runner.log + đúng 1 comment thẻ (A, C).
- [x] Hết hạn mức trong stream-json → ghi usage account, dòng `worker_exit` cuối log không che mẫu hết hạn mức (E).
- [x] Lượt giao lại có prompt "Resume…" chỉ khi lần trước chết bất thường hoặc không có bản ghi (F).
- [x] Worker thoát 0 không comment, mã thoát giữ nguyên (B, D).
- [x] Ân hạn trước khi kill zombie: lần thấy đầu không kill, quá `SB_ZOMBIE_GRACE` mới kill (G1, G2).
- [x] Gate --full exit 0.

## Mutation (chống test tautology)
- Bỏ dòng ân hạn trong `check_lane_zombie` → G1 ĐỎ.
- Bỏ dòng `printf worker_exit` trong wrapper → A, B ĐỎ.

## Ghi chú
- Nhánh cũ hơn main 3 lần: đã gộp origin/main, 1 conflict ở danh sách `BIN` của `super-board-setup.py` (giữ cả `verify-*` của #251 và `worker-wrap.sh`).
- 3 test cũ chỉ thêm `export SB_ZOMBIE_GRACE=0` (test kill trực tiếp, không chờ ân hạn): chấp nhận.
- `REG-SB-RUNNER-WATCHDOG-01` đỏ 1 lần trong gate khi máy tải cao (99 s, "give-up lines: 0"); chạy riêng xanh cả trên nhánh lẫn main, lượt gate sau xanh: flake do tải, không do PR.
- Rủi ro còn lại chưa đo: `--output-format stream-json --verbose` với `claude -p` thật chưa chạy một worker thật đầu cuối.
