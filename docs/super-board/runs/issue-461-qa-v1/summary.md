# QA #461 v1 — PASS

Nhánh issue-461-session-context-index đã gộp origin/main.

| AC | Test | Kết quả |
|---|---|---|
| 1 RED | test_instincts_index_trunk.sh với hook cũ (origin/main) | ✖ ` M .agents/instincts-index.md` (đột biến, đã khôi phục) |
| 2 GREEN | cùng test, hook mới | ✔ status sạch, dòng "41 mục" còn |
| 3 learn | cùng test | ✔ mục mới có trong index, dải sed đúng dòng 690, 42 mục |
| 4 worktree | cùng test | ✔ index vẫn sinh lại |
| 5 ignore | tests/super-board/test_main_stays_clean.sh | ✔ log run + dup-noted bị ignore |

Gate: `post-fix-gate.py --run-tests --brief` exit 0 (6/6).
Test gaps (không viết): `_refresh_index` chỉ chạy khi target là .agents/instincts.md; lỗi indexer chỉ cảnh báo (Medium/Low).
