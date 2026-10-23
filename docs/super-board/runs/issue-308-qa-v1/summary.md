# QA v1 · issue #308 · PR #310 · head 574b800 · FAIL (AC1)

Không có UI: không chụp ảnh (AC là hành vi runner/shell).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_runner_self_reload.sh` | 0 | 13/13 xanh (finish bị stub) |
| `post-fix-gate ... --diff origin/main --force-full` (cây đã gộp origin/main) | 1 | 64/65: `test_runner_build_workers.sh` đỏ do thư mục tmp biến mất khi gate chạy song song |
| `bash tests/super-board/test_runner_build_workers.sh` chạy riêng | 0 | all passed, không liên quan PR |
| `repro-finish-diverged-main.sh` (agent-kit `worktree finish` THẬT) | 1 | BLOCKED, xem dưới |

## Lỗi (AC1 chưa đạt)
Repo tạm: main ahead 1 / behind 1 (commit cục bộ `local.txt`, origin đổi `runner.sh`).
`worktree add .claude/worktrees/self-reload-1 --base=origin/main` rồi `worktree finish` ra:

    ✖ worktree blocked: PR của worktree đã gộp vào origin nhưng main local chưa đồng bộ được về origin:
    main local có commit origin chưa có và không thuộc PR nào đã merge vào trunk ... Không gộp commit gốc của PR vào main

Nguyên nhân: HEAD worktree = origin/main, không nằm trong main => `_squashed_on_origin`
(worktree.py:3177) coi là "PR đã squash trên origin" và đi đường `_sync_main_to` (reset/ff),
đường này từ chối khi main có commit cục bộ. Đường "merge main vào worktree rồi ff main"
(worktree.py:3407-3498) không bao giờ chạy. `reload_finish_main` trả 1, runner chỉ notify:
đúng hành vi cũ của issue, không tự đồng bộ. Test pass vì stub `finish`.
Main sau probe: không đổi (`localcommit`, runner.sh=r).
