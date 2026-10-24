# QA #291 v1 — PR #313 (refresh-matrix-driver)

Không có giao diện: thay đổi chỉ ở script git và hook, nên không có ảnh chụp.

## Test của AC
Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_matrix_driver_refresh.sh`

| Kết quả | Exit | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Nhánh PR (GREEN) | 0 | ✔ | ✔ | ✔ | ✔ |
| Kit của origin/main + test mới (RED) | 1 | ✖ lệnh cũ giữ nguyên | ✖ `unknown action 'refresh-matrix-driver'` | ✔ | ✖ session_context.sh không gọi |

Case 1 = AC1 (lệnh cũ được ghi lại), case 2 = AC2 (đúng rồi thì im lặng, `.git/config` không đổi),
case 3 = repo chưa cài driver không bị ghi, case 4 = SessionStart gọi refresh.

## Gate như merge gate (#251)
Đã `git merge --no-edit origin/main` (Already up to date).
Lệnh: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main`
Exit 0 — test hồi quy 67/67, lớp tĩnh đạt.

## Soát diff
`refresh_matrix_driver`: `config --get` không có khóa → `return 0` (không opt-in repo); chỉ `config` một khóa khi khác bản mới.
`matrix_driver_cmd` là nguồn duy nhất cho `install` và refresh, không lệch lệnh.
Test-gap Medium/Low (không viết): refresh chạy từ linked worktree (config dùng chung, không đổi hành vi).
