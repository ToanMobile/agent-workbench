<!-- sb:status -->
> [!NOTE]
> ⏳ Đang review · vòng 2 · ✅ 6/6 AC · Refs #96 #118 · head `675aad5`
<!-- /sb:status -->

<!-- sb:problem -->
## Problem
- **Where:** `.claude/bin/super-board-run.sh` (vòng chính), `.claude/bin/super-board-post-merge-clean.sh --sweep` (merge ở #111)
  - a. OCR batch 19/10 đọc lại phần đã merge
  - b. Thẻ #7 / PR #128 merge lúc 19:12, worktree `issue-7-review` vẫn nằm đó
- **Who:** mọi board super-board chạy runner claude-p
- **What happened:**
  - Runner chỉ gọi `--sweep` một lần trong `startup_reconcile`; runner chạy nhiều ngày nên thẻ merge giữa chừng giữ worktree tới lần khởi động sau.
  - Worker review (LLM) báo "đã gỡ worktree" mà không chạy lệnh gỡ nào: `issue-7-review` detached ở head `f1afe2e` đã squash (không phải tổ tiên của main), cây sạch.
  - Các lỗi sweep cũ (200 PR, rác vào kho object, ref giữ tạm, nhánh có commit sau merge) đã lên main qua #126.
<!-- /sb:problem -->

<!-- sb:solution -->
## Solution
- Gộp main: #126 đã chứa toàn bộ sửa sweep, runner `startup_reconcile`, Cleanup của wave và test wiring; mọi hunk cũ của nhánh lấy theo main
- `sweep_merged_lanes`: một lời gọi nền dùng chung cho `startup_reconcile` và mỗi tick của vòng chính, đặt trước nhánh cap-reached (3 lane bận vẫn sweep)
- Runner tự giãn 600 s (`SWEEP_NEXT`), vì sweep không ghi stamp khi đọc GitHub hỏng; truyền `--min-interval 300` để nhịp không thành 10/20 phút xen kẽ
- Luật ma trận `REG-SB-RUN-SWEEP-TICK-01` (thêm cuối) chạy test wiring khi `super-board-run.sh` đổi
<!-- /sb:solution -->

<!-- sb:ac -->
## Acceptance criteria
- [x] Runner và wave thật sự gọi sweep; sweep lỗi không dừng runner, Cleanup lỗi không làm mất kết quả wave; wave halted không gọi\
  ↳ `tests/super-board/test_post_merge_sweep_wiring.sh` R1–R3, W1–W4 (đã trên main qua #126)
- [x] Thẻ cũ phía sau 200 PR mới hơn vẫn được tìm thấy và dọn\
  ↳ `test_post_merge_squash_leftovers.sh` B2/B5/B7/B8/B10 (main)
- [x] Rác chưa track không thành git object; sửa trên file QA đã track được cất; kit giữ worktree thì rác được trả lại\
  ↳ A8, B16, B20, B21 (main)
- [x] Ref giữ tạm ngoài `refs/remotes/origin/`; giữ head thất bại thì giữ worktree, nói lý do; dry-run không hứa gỡ khi GitHub thiếu `refs/pull`\
  ↳ B9, B17, B18 (main)
- [x] Worktree trên nhánh có commit sau merge được giữ; worktree review detached ở head đã squash, cây sạch (hình dạng #7) được gỡ\
  ↳ B24, B5 `issue-7-review` (main)
- [x] Runner gọi sweep mỗi tick, kể cả tick cap-reached; tick liền nhau chỉ khởi một sweep; sweep treo không giữ tick\
  ↳ R4–R6 (ĐỎ trước sửa: R4/R5/R6 ✖; đột biến bỏ giãn: R5 ✖ 4 lời gọi)
<!-- /sb:ac -->

<!-- sb:history -->
## Iteration history
| Lane | Done | Time | Details |
|---|---|---|---|
| 🔨 builder | ✅ | Oct 19 +07 | `ccba6ed`, `53dcdab`, `1bf5fdc` · principal-code-reviewer 0 Blocker · OCR lượt cuối 0 điểm |
| 🔨 builder | ✅ | Oct 19 +07 | gộp main (lấy bản #126) · `8d501a9`, `ba8e9d8` sweep mỗi tick · principal-code-reviewer 0 Blocker, 4 Nit đã sửa · OCR 1 điểm đã sửa, lượt cuối 0 điểm |
<!-- /sb:history -->

<!-- sb:risk -->
## Risk
🟢 **Low** · chỉ thêm lời gọi nền một script luôn exit 0, tự khoá flock, giãn 600 s phía runner; luật gỡ worktree không đổi (đã review ở #126). Backend codex (`super-board-codex-wave.sh`) chưa gọi sweep: phần còn lại của #118.
<!-- /sb:risk -->

🤖 Generated with [Claude Code](https://claude.com/claude-code)
