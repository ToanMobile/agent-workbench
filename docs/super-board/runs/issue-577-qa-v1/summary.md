# #577 QA v1 — test_gate_stop_reuse_race.sh dưới tải cao

Lệnh: `bash universal-agent-devkit/tests/gates/test_gate_stop_reuse_race.sh` (nhánh issue-577-stop-reuse-race-load, đã merge origin/main)
Tải: load1 tự nhiên của máy 50–88 (≥ 24), không cần tạo thêm.

| Bản | Lần | Exit | Kết quả |
|---|---|---|---|
| gốc (origin/main) | 1 | 1 | ĐỎ: K1/record/stop, K1/budget/stop, K1/receipt/stop: "A waited=no" |
| gốc (origin/main) | 2 | 1 | ĐỎ: K1/record/stop: "A waited=no re-used=no" |
| gốc (origin/main) | 3 | 1 | ĐỎ: K1/receipt/full: "A waited=no re-used=no" |
| sau sửa (9eb5a31) | 1 | 0 | all checks passed (load 84) |
| sau sửa (9eb5a31) | 2 | 0 | all checks passed (load 88) |
| sau sửa (9eb5a31) | 3 | 0 | all checks passed (load 86) |

Cơ chế: a.out của ca trước còn dòng "waiting for it", vòng chờ đọc nó trước khi lượt A cắt cụt file. Sửa: xoá a.out/a.rc trước khi chạy A. Không đổi timeout.
Diff: 1 dòng thêm, chỉ test DevKit.
Gate impacted (`post-fix-gate.py --run-tests --brief`): exit 0, regression 2/2, lớp tĩnh đạt.
