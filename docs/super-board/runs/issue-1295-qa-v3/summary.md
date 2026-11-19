# QA #1295 v3 (PR #1297)

- Head PR lúc QA bắt đầu: 9e6bc518; đã gộp origin/main (3236abe9) vào cây QA, xung đột duy nhất ở `.agents/instincts-index.md` (dòng mục lục INSTINCT-112/114/115), giữ phía PR vì số dòng khớp `instincts.md` sau gộp.
- `bash tests/super-board/test_runner_self_reload_catchup_ff.sh` exit 0 (A/B/C/D/E đều xanh).
- 3 test self_reload cũ (`test_runner_self_reload.sh`, `_absorbed.sh`, `_absorbed_ff.sh`) exit 0.
- Không sửa test cũ. Diff chỉ là bash runner, không eval/curl/secret.
- Gate scoped: xem comment `[qa] [report]`.
