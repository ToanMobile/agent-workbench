# QA #573 · PR #641 · v1 · head bde9765a

Chạy trong worktree `issue-573-qa`, mọi lệnh ở thư mục `universal-agent-devkit/tests/context_memory`.

| Lần chạy | Lệnh / môi trường | rc | ✔ | ✖ |
|---|---|---|---|---|
| main, sạch | `bash test_scratch_cleanup.sh` (bản origin/main) | 0 | 38 | 0 |
| nhánh, sạch | `bash test_scratch_cleanup.sh` | 0 | 38 | 0 |
| main, sạch | `bash test_giao_default.sh` (bản origin/main) | 0 | 35 | 0 |
| nhánh, sạch | `bash test_giao_default.sh` | 0 | 35 | 0 |
| main, bẩn (AC1) | `CLAUDE_CONFIG_DIR=<dir có <pid sống>.json, sessionId=11111111-…>` | 1 | 36 | 2 |
| nhánh, bẩn (AC1) | cùng môi trường | 0 | 38 | 0 |
| main, bẩn (AC2) | `PROMPT_DEDUPE=0` | 1 | 32 | 3 |
| nhánh, bẩn (AC2) | `DEVKIT_AGENT=bogus DEVKIT_ROOT=/nonexistent PROMPT_DEDUPE=0` | 0 | 35 | 0 |
| main, bẩn (AC2) | `DEVKIT_AGENT=bogus DEVKIT_ROOT=/nonexistent` | 0 | 35 | 0 |

Dòng đỏ của main (AC1): `prune left the dead dir (rc=0)`, `SessionStart prune wrong`.
Dòng đỏ của main (AC2): ca 5, 5b, 5c (`the order was repeated in the same session`, ...).

- Số ca và tên ca giữ nguyên (38 và 35); diff chỉ 2 file test.
- AC2 đúng nguyên văn không tái hiện được: `DEVKIT_AGENT` lạ hoặc `DEVKIT_ROOT` sai không làm test đỏ trên cây này; `PROMPT_DEDUPE=0` thì có.
- `post-fix-gate.py --run-tests --brief`: exit 0 (3/3 hồi quy, 2 test sửa có duyệt chéo antigravity T0080, sha256 khớp).
- Nhánh còn thiếu 34 commit của main (cố ý, giữ `auditedHead`); `--full` do merge point chạy.
