# #459 AC3 — bằng chứng (28/10, origin/main 0a535f1f)

Đo `git ls-tree` + `grep -c -- '--mark'` trên `origin/main` của từng repo whitelist (sau `git fetch`):

| repo | có super-board-verify-cmd.sh | số dòng nhắc `--mark` |
|---|---|---|
| agent-workbench | có | có (`--record` / `--mark`, dòng 10-13) |
| OfficeReader | có | 9 |
| Idle-Plaza-3D | có | 9 |
| GeelyEx2 | không | — (đi nhánh "không có script", không in ✖) |
| Goods-Triple-Shelf-Match-3D | không | — |
| Humans-vs.-UFOs | không | — |

Kết luận: mọi repo có script đều hỗ trợ `--mark`; 3 repo không có script thì kit giữ hành vi cũ, không còn dòng ✖ (AC1, PR #491).

Merge gate dùng lại biên nhận cây: `.claude/bin/super-board-merge-gate.sh` dòng 638 (`sb_verified_tree_receipt`) và dòng 958 in
`verify skipped: this exact merged tree was already verified green with the same commands`.

Lệnh: `bash universal-agent-devkit/tests/gates/test_gate_auto_tree_receipt.sh` — exit 0 (14/14b XANH).
