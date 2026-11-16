# QA #1182 v3 — PR #1191 @ 697f7b36 (+ merge origin/main)

- 5 test `tests/gates/*zero_defect*.sh` trên 5db81236: ĐỎ cả 5 (FAILS 21 / 143 / 7 dạng token / 276 / 175) (tự chạy).
- Cùng 5 test trên head 697f7b36: XANH cả 5, ALL PASS (tự chạy).
- Không sửa test cũ: PR chỉ thêm 5 test mới + test_durations.txt.
- `post-fix-gate.py --run-tests --scoped --brief --json` sau khi merge origin/main: `super-board-qa-exit2.sh` in `pass`, exit 0 (tự chạy).
- Chưa kiểm: replay lưu lượng thật (AC3), thuộc audit Antigravity ở lane Review.
