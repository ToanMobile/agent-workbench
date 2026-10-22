# QA #237 v2 — rebuild sau reviewer vòng 1 (PR #244 @ 92f7f381)

Kết quả: PASS. Không có ảnh (thay đổi runner/backend, không lên màn hình).

## Lệnh và kết quả
- `bash tests/super-board/test_worker_death_record.sh` → exit 0, ALL PASS (A, B, C, D, E, F, G1, G2, H, I).
- `test_runner_lanes.sh`, `test_runner_lane_workers.sh`, `test_runner_build_workers.sh` → exit 0, all passed.
- `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` (đúng dòng của `super-board-verify-cmd.sh`, nhánh đã up to date với origin/main) → exit 0, 60/60.

## Kiểm lại hai lỗi reviewer vòng 1
- [x] R1 `startup_orphan_workers`: con của wrapper có PID trong lock không bị coi là orphan; worker lạ vẫn bị bắt (test I).
- [x] R2 `check_lane_zombie`: kill zombie diệt cả con của wrapper, kể cả con bỏ qua TERM (test H).
- [x] Nit: `ZOMBIE_SEEN` được dọn khi thẻ về cột cũ và sau khi kill (đọc mã, chưa có test riêng).

## Mutation (chống test tautology)
- Bỏ dòng `pkill -9 -P "$pid"` và dòng `case "$locked" in *" $ppid "*)` → H ĐỎ ("child survived"), I ĐỎ ("child ... reported as orphan"). Đã khôi phục, cây sạch.

## Chưa đo
- Chưa chạy một worker `claude -p --output-format stream-json --verbose` thật đầu cuối.
- Dọn `ZOMBIE_SEEN` khi thẻ về cột cũ chưa có test riêng (Low).
