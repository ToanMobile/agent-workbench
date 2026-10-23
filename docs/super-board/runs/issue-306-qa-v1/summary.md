# QA #306 v1 — halt rc=79 không giết worker

Nhánh: issue-306-halt-keeps-workers (đã merge origin/main trước khi chạy).

| Kiểm tra | Lệnh | Kết quả |
|---|---|---|
| AC1: rc 79 và rc 69 giữ worker sống | `bash tests/super-board/test_runner_halt_keeps_workers.sh` | exit 0, 4/4 ✔ |
| AC1 đột biến: hoàn lại điều kiện cũ `\|\| ! github-read --check` | cùng lệnh | exit 1, ✖ rc 79 và ✖ rc 69 giết worker (RED), hoàn nguyên → GREEN |
| AC2: rc 9/10 vẫn dừng worker | cùng test | ✔ rc 10, ✔ rc 9 |
| AC2: super-board-stop.sh dừng như cũ | `bash tests/super-board/test_stop_scope.sh` | exit 0, all passed |
| AC3: gate như merge gate | `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | exit 0, 65/65 suite hồi quy |

Test-gap (Medium, không chặn): test cắt `halt_cleanup` rồi eval với stub, không chạy trap EXIT thật của runner.
Gate báo 2 test sửa (test_github_read_jq_flag.sh, test_runner_ready_order.sh): do merge origin/main, không thuộc diff của PR này.
