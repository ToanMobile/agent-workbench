# QA #451 v2 (PR #512, head 9a1649ab sau khi gộp main)
- AC1: `bash tests/super-board/test_size_exclude_evidence.sh` → exit 0, 7/7 ca ✔ (config fixture auto_max_lines 400).
- AC2: bỏ mục `docs/super-board/runs` khỏi size_exclude → exit 1, 2 ca ✖; đã khôi phục, test lại exit 0.
- Gate: `post-fix-gate.py --run-tests --brief` (--auto-approve-tests --allow-no-tests) exit 0.
- Ảnh: không cần (chỉ sửa test, không UI).
