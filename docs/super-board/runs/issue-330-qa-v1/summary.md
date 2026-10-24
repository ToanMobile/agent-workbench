# QA #330 · PR #357 (lát 1, mục 1–2) · v1

Nhánh: `issue-330-ocr-createtask-slice` (đã merge origin/main, "Already up to date").

## Gate #251 (4c)
Lệnh: `CLAUDE_PROJECT_DIR=<worktree> python3 <worktree>/universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main`
Kết quả: exit 0 · PASS · test hồi quy 83/83 · lớp tĩnh đạt.

## RED → GREEN (test_create_task_batch.sh, ca mới 29 + 30)
Trên origin/main (create_task.py gốc, test của PR): 5 failed
- 29 rc=0: báo "Đã gom" dù edit lỗi (mục trùng tên) → việc mới mất im lặng
- 30 '' / '60s': Traceback lúc import (float rỗng/rác)
- 30 '0' / '-5': timeout 0s/-5s → gh read board hỏng → không gom
Trên nhánh PR: all passed (29 và 30 ×4 đều ✔).

## AC
- Mục 1 (gom thành công = edit exit 0 VÀ số mục cùng tên tăng): đạt, ca 29.
- Mục 2 (CREATE_TASK_GH_TIMEOUT_S rỗng/rác/≤0 → 60s + cảnh báo): đạt, ca 30.
- Mục còn lại tách sang #358 (ngoài phạm vi lát này).

## Test-gap (không viết)
- Thấp: ca 30 chưa kiểm cảnh báo stderr nêu đúng giá trị gốc.
