# #659 QA v1 — PR #665 @ 4bb3fd3

Thay đổi: 1 dòng trong `.claude/bin/super-board-setup.py` (thêm `super-board-merge-cards.py` vào `BIN`).

| AC | Kiểm | Kết quả |
|---|---|---|
| 1. test_setup_bin_list.sh exit 0 | `bash tests/super-board/test_setup_bin_list.sh` trên nhánh đã merge origin/main | PASS, exit 0, 51 script |
| 2. Board mới có merge-cards.py | `BIN` chứa mục này (setup.py:75); test kiểm mọi script tham chiếu đều có trong BIN | PASS |

RED trên base: origin/main không có `merge-cards` trong BIN (0 lần), test đỏ (Builder: exit 1).

Gate: `post-fix-gate.py --run-tests --scoped --brief` exit 1, 151/152.
Suite đỏ duy nhất: REG-SB-MERGE-TRAIN-01 (`tests/super-board/test_merge_train.sh`, dòng `✖ F4 no worker flag: exit 13`).
Chạy lại trên origin/main 239bd7ef: đỏ y hệt (exit 1) → đỏ sẵn trên base, không do PR này.
PR chỉ đổi setup.py; không chạm merge-train.
