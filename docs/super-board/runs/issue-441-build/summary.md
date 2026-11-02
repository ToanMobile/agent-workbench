# Builder #441: đồng bộ gói super-board lên 4 repo app

Nguồn: agent-workbench main a412df1c. Mỗi repo một PR nháp, nhánh `issue-441-sync-super-board`.

| Repo | PR | post-fix-gate (impacted) |
|---|---|---|
| Idle-Plaza-3D | ToanMobile/Idle-Plaza-3D#17 | exit 0, 5/5 |
| OfficeReader | ToanMobile/OfficeReader#219 | exit 0, 9/9 |
| Humans-vs.-UFOs | ToanMobile/Humans-vs.-UFOs#85 | exit 0, 16/16 (`--auto-approve-tests`, test chỉ được thay bằng bản workbench) |
| Goods-Triple-Shelf-Match-3D | ToanMobile/Goods-Triple-Shelf-Match-3D#89 | exit 0, 3/3 (`--auto-approve-tests`) |

## AC

- AC1 (merge-gate không gọi `cleanup-wt.py --post-merge`): `grep -c` chữ đó = 1 ở cả 4 repo, và là dòng chú thích
  có sẵn trong bản workbench ("Không còn gọi ..."). Dòng lệnh không phải chú thích = 0.
  Ghi chú: "grep = 0" theo nghĩa đen không đạt được với bản copy y hệt workbench.
- AC2 (`post-merge-clean.sh` giống workbench): Humans và Goods đã cập nhật; Idle và Office đã bằng sẵn.
- AC3 (tests/super-board của workbench trên bản copy): chạy 115 test trong thư mục tạm có bản copy
  của từng repo. Bản gốc workbench trong cùng thư mục: 106 PASS. Idle 105 (+1 flake thời gian, chạy lại PASS),
  Humans 106, Goods 106, Office 102 (5 ca do `.claude/workflows` là symlink tới thư mục ignore; chạy lại PASS).
  Các ca đỏ còn lại trùng với bản gốc: board_heartbeat (thiếu .github/), builder_already_met, github_read,
  lane_worktree_kit, main_stays_clean, merge_train (SB_BOARD_WORKER=1 của phiên này; gate chạy với biến đó
  được bỏ thì PASS), agent_office_inbox, size_exclude_evidence.
- AC4 (PR merge qua `super-board-merge-gate.sh`): chưa, chờ Reviewer. Đây là phần Builder không làm.

## Không đụng

`configs/`, `verify_commands`, hooks cục bộ của từng repo. Office: `.claude/workflows` là symlink tới thư mục
ignore; wave.js ở checkout chính đã bằng workbench (cmp) nên không có gì để commit.
