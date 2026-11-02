# QA #441 v1: đồng bộ gói super-board lên 4 repo app

Kiểm độc lập trên head của 4 PR nháp (đọc file qua `gh api`, không dùng số liệu của Builder).
Không có UI: không chụp ảnh.

| Repo | PR | head | post-merge-clean.sh | merge-gate.sh | `cleanup-wt.py --post-merge` (tổng / dòng lệnh) |
|---|---|---|---|---|---|
| Idle-Plaza-3D | #17 | cda0185f | c9e852573216 | bc2e4bf8410a | 1 / 0 |
| OfficeReader | #219 | be11ee83 | c9e852573216 | bc2e4bf8410a | 1 / 0 |
| Humans-vs.-UFOs | #85 | ea73be5c | c9e852573216 | bc2e4bf8410a | 1 / 0 |
| Goods-Triple-Shelf-Match-3D | #89 | d6f1965f | c9e852573216 | bc2e4bf8410a | 1 / 0 |

agent-workbench main: post-merge-clean.sh = c9e852573216, merge-gate.sh = bc2e4bf8410a (khớp cả 4 repo).
Dòng còn lại (1416) là chú thích "Không còn gọi ... cleanup-wt.py --post-merge".

- AC1: PASS (không còn dòng lệnh; `grep` chữ thuần = 1 vì chú thích có sẵn).
- AC2: PASS (hash bằng nhau ở 4 repo).
- AC3: PASS có điều kiện, dựa số liệu Builder (102-106/115, ca đỏ trùng bản gốc cùng môi trường); QA không chạy lại 115 test trên 4 bản copy.
- AC4: chưa, chờ Reviewer merge từng PR qua super-board-merge-gate.sh.
- Gate impacted trên nhánh sau `git merge origin/main`: `post-fix-gate.py --run-tests --brief` exit 0.
