# QA #229 v1 — runner tự nạp lại code (PR #241)

Head sau khi merge origin/main vào nhánh; diff so với main: 3 file, +150 dòng (< 400).

| Kiểm | Lệnh | Kết quả |
|---|---|---|
| Test mới | `bash tests/super-board/test_runner_self_reload.sh` | exit 0, 10/10 PASS |
| Cú pháp | `bash -n .claude/bin/super-board-run.sh` | OK |
| Ma trận | rule REG-SB-SELF-RELOAD-01 | nối CUỐI, phần đầu giữ nguyên |
| Mutation M1 bỏ guard worker | chạy lại test | ĐỎ (busy: exec=1) |
| Mutation M3 bỏ `bash -n` | chạy lại test | ĐỎ (syntax: exec=1) |
| Mutation M4 bỏ dedupe cảnh báo | chạy lại test | ĐỎ (notices: 2, 3) |
| Mutation M2 bỏ kiểm tổ tiên | chạy lại test | XANH: `merge --ff-only` chặn trùng, chỉ đổi thông báo |
| Gate `--full --diff origin/main` | post-fix-gate | exit 1: 47/49 |

Gate 2 suite đỏ, cả hai ngoài phạm vi PR:
- REG-SB-BUILD-WORKERS-01: chạy riêng trên runner của PR exit 0 "all passed" → đỏ do tải khi chạy song song.
- REG-AUTO-PLAY-STORE-MCP-01: `test_credentials_endpoint` TimeoutError (server 127.0.0.1 không lên sau 10s), đỏ cả khi chạy riêng; PR không đổi file nào trong mcp-servers/.

Chưa kiểm: AC2 (≤ 2 tick) trên runner thật; AC4 (gate exit 0) chưa đạt vì 2 suite trên.
