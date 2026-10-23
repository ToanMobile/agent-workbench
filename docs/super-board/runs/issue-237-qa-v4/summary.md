# QA #237 v4 — PR #244 (nhánh issue-237-worker-silent-death)

Phạm vi: bản sửa vòng 3 của reviewer (R8 `kill_pid` diệt con của wrapper, R9 trap TERM đặt trước con) cộng các AC cũ.

| Lệnh | Mã thoát | Kết quả |
|---|---|---|
| `bash tests/super-board/test_worker_death_record.sh` | 0 | ALL PASS (A–M) |
| `bash tests/super-board/test_runner_build_workers.sh` | 0 | all passed |
| `bash tests/super-board/test_runner_lane_workers.sh` | 0 | không có dòng ✖ |
| `bash tests/super-board/test_runner_lanes.sh` | 0 | không có dòng ✖ |
| `bash tests/super-board/test_stop_scope.sh` | 0 | all passed |
| `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | 0 | PASS 63/63 |

Nhánh đã up to date với origin/main (merge: Already up to date), không còn thread chưa giải quyết.

Mutation: bỏ dòng `pkill -KILL -P "$pid"` ở `super-board-stop.sh` → L ĐỎ ("child survived stop"); khôi phục → XANH.

Chưa chạy: worker `claude -p` stream-json thật đầu cuối; R6 (test đường `issue_locked`, should fix, không chặn).
