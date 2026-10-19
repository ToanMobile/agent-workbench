# QA issue #7 (PR #128) — v1 — PASS

Head được kiểm: 8f6e4b7. Không có UI nên không có ảnh.

| AC | Bằng chứng | Kết quả |
|---|---|---|
| PoC ANSI-C quote + `git reset --hard` bị chặn | probe độc lập → block-dangerous-git exit 2 | ✅ |
| PoC ANSI-C quote + `rm -rf /Users` bị chặn | probe độc lập → hardware_safety_gate exit 2 | ✅ |
| PoC nối dòng backslash-newline trước `#` bị chặn | probe độc lập → exit 2 | ✅ |
| Dollar-brace sau backslash (gộp #7 c) | probe độc lập → exit 2 | ✅ |
| `python3 -ISc`, `node --eval=` (#8) | probe độc lập → exit 2 | ✅ |
| Tạo nhánh qua inline script (#8) | probe độc lập → exit 2 | ✅ |

Lệnh hợp lệ không bị chặn: `git status # it's fine`, `ls -la`, `echo` có ANSI-C quote vô hại → exit 0.

## Paired test
- `bash universal-agent-devkit/hooks/tests/test_git_guard_ansi_c_quote.sh`
- ĐỎ (guard của origin/main + test mới): pass=11 fail=15
- XANH (head PR): pass=26 fail=0

## Hồi quy lân cận (exit 0 cả 4)
- test_git_guard_bypass.sh: 37/0
- test_git_guard_nested.sh: 36/0
- hook_contract_test.sh: 690 ok, 0 lệch
- or_ported_contract_test.sh: 79 ok, 0 lệch

## Chưa kiểm
`git branch NAME` trong script và `shell_writes.py` / `worktree_guard` (PR đã ghi `ponytail`). Cần Antigravity audit độc lập ở lane Review.
