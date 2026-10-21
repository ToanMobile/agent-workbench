# QA issue #29 · v1 · ✅ pass

Đầu nhánh: `9a209b8c` (PR #159). Không có UI, không có ảnh chụp màn hình.

## Lệnh và kết quả
- `bash universal-agent-devkit/tests/verification/test_game_script_args.sh` → exit 0, 4/4 ✔
- `post-fix-gate.py --run-tests --brief --diff origin/main` → exit 0, hồi quy 1/1, lớp tĩnh sạch

## Từng AC
- AC1 `unity-bot-marathon.sh --help` in hướng dẫn, thoát 0 → ✔ (test a1). Gỡ fix (bản `origin/main`) thì test ĐỎ: `help: unbound variable`.
- AC2 `unity-batch.sh --filter` thiếu giá trị → ✔ thoát 2 (test b1). Gỡ fix thì test ĐỎ: rc=124, lặp vô tận.
- AC3 rename ra ngoài `Assets/` không làm hỏng `validate-assets.sh` → ✔ (test c1), nhưng xem ghi chú.

## Kiểm đột biến
- Mutant: bản `origin/main` của `unity-batch.sh` → ĐỎ. Bản `origin/main` của `unity-bot-marathon.sh` → ĐỎ ×2 (`--help`, injection).
- Mutant: gỡ dòng đọc trường NUL thứ hai trong `validate-assets.sh` → test c1 vẫn XANH (mutant sống).

## Ghi chú AC3 (không chặn)
`validate-assets.sh` đã đọc đủ 2 trường NUL ở `main`, nên AC3 đúng từ trước và nhánh không sửa file này. Test c1 không bắt được việc gỡ dòng đó: lệnh `git status` giới hạn theo `Assets/`, nên mọi bản ghi rename có mặt trong luồng đều có đường cũ bắt đầu bằng `Assets/`, và khi lệch luồng dòng đó bị bỏ qua (`ets/...`). Đã thử fixture thứ hai (`ArtAssets/notes.md` → `Docs/notes.md`) và nó cũng không phân biệt được. Không thêm test vô nghĩa.
