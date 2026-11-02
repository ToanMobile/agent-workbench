# #562 QA v1 — merge train state signal
Base: origin/main đã merge vào nhánh (Already up to date). Chạy với `env -u SB_BOARD_WORKER` (biến này rò vào ca F4, xem #528).

| AC | Lệnh | Kết quả |
|---|---|---|
| 1 Agent Office, PID sống/chết | `python3 -m unittest discover -s mcp-servers/agent-office/tests -p test_merge_train.py` | exit 0, 7 test OK |
| 2 Nhãn gate merge / chờ train | `bash tests/super-board/test_status_merge_train.sh` | exit 0, all passed |
| 3 State xoá khi exit 4, TERM; mồ côi bỏ qua | `bash tests/super-board/test_merge_train_state.sh` | exit 0, PASS |
| 4 Không flock; train cũ vẫn PASS | `bash tests/super-board/test_merge_train.sh` | exit 0, 80 ✔, all passed |

Gate impacted: `post-fix-gate.py --run-tests --brief` → PASS, 11/11.
Không có UI chụp được (hiển thị web chỉ là nhãn; logic đã có test server).
