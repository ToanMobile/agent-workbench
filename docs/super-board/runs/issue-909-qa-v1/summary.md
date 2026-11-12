# QA #909 v1 — PR #1130, head fe399197 (base origin/main đã merge: Already up to date)

Kết quả: PASS. Không có ảnh (chỉ tooling/test, không hiện trên màn hình).

| AC | Bằng chứng |
|---|---|
| OOM JVM + `<locals>` khớp, ĐỎ trên main, XANH sau sửa | regex main: Terminating/Aborting/`<locals>`/`$$` = False; PR = True. `test_fail_line_oom_locals.sh` rc=0 |
| `retry after java.net.SocketTimeoutError:` không khớp | main=False, PR=False; test (b) ✔ |
| 40 KB `Ab` < 1 s, bỏ neo thì vượt | test (c) ✔, (d) ✔ |
| qualified/prefixed/precision/ecosystems + red_fail_lines | 5/5 rc=0 |
| Sparse/skip-worktree, projectRoot con, worktree add lỗi (I1-I4) | `node --test grok-audit.test.js grok-audit-hidden.test.js`: 47 pass, 0 fail |
| Gate `post-fix-gate.py --run-tests --scoped --brief --json` | `super-board-qa-exit2.sh` in `pass`, rc=0 |

Ghi chú: `  at ...java.lang.LinkageError:` (sau từ thường) không khớp, đúng thiết kế `(?<![a-z] )`; `...X` ở đầu dòng khớp.
Chưa tự đo lại: RED của I1-I4 trên main (hook chặn checkout đè file); tin báo cáo builder.
Security pass (pr-security-review) trên diff tools.js: không phát hiện.
