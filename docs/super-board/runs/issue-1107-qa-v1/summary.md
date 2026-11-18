# QA #1107 v1 — self-reload khi main detached HEAD

- Head PR: 5bf99070 (base origin/main đã gộp: Already up to date)
- AC1: `bash tests/super-board/test_runner_self_reload.sh` exit 0, "all passed". Bỏ bản sửa (runner của origin/main): exit 1,
  `detached: exec=0 notify=1` ĐỎ; có bản sửa: XANH. Ca 4d thứ hai (detached + runner sửa tay) giữ file và notify.
- AC2: ca 4d detached: exec=1, notify=0 — dòng cảnh báo "main checkout is on branch 'detached'" không còn sinh ra.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` => `pass` (exit 0).
- pr-security-review: 0 findings (chỉ đọc ref origin qua `git show`, đường dẫn từ `git ls-files`, không có input ngoài).
- Test không bị sửa (chỉ thêm ca 4d), không cần cross-review.
