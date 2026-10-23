# QA #325 v1 — PASS (không có UI render, ảnh: không cần)

Gate (verify cmd của merge gate, sau khi merge origin/main): `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, hồi quy 80/80.

| AC | Lệnh | Kết quả |
|---|---|---|
| halt test < 60 s, vẫn XANH | `bash tests/super-board/test_runner_halt_keeps_workers.sh` | 1.3 s, "all passed" (trước ~600 s theo builder) |
| đột biến giết worker ở rc 79 bị bắt | thêm rc 79 vào điều kiện kill của `halt_cleanup` | ĐỎ: "✖ rc 79 killed the worker (#306)"; khôi phục → XANH |
| self-reload: không cảnh báo giả, worktree cũ không chặn | `bash tests/super-board/test_runner_self_reload.sh` | XANH; với run.sh gốc origin/main ĐỎ ("stale worktree blocked reload: rc=1") |
| repro script không đường dẫn máy, xoá chỉ trong mktemp | đọc diff | `git rev-parse --show-toplevel`, `mktemp -d`, trap dọn đúng thư mục tạm |
| presenter: Head không quay tích luỹ, snapshot có faceOut | `node mcp-servers/agent-office/tests/present_pose_test.js` | XANH; với index.html gốc ĐỎ (Head quay 3.133 rad) |

Chưa kiểm: ảnh render agent-office (lane này không có trình duyệt; hành vi đo bằng quaternion). Ca "không cảnh báo giả remove" không phân biệt bản cũ/mới (bản cũ lỗi sớm hơn ở bước add) — nhẹ, không chặn.
