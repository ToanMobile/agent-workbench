# QA v1 — Issue #1406 (PR #1413)

- Head kiểm thử (gốc): `6bad1dbba19e4f5734c643baf0c9883b9269c8a9`
- Base: `origin/main` (`1c256ac2`) — `merge-base --is-ancestor` = true

## Kết quả test tự động
- `bash tests/super-board/test_audit_sweep_1406.sh` -> exit 0 (20/20 PASS)
- `bash tests/super-board/test_status_ungated_merges_1406.sh` -> exit 0 (7/7 PASS)
- `bash universal-agent-devkit/tests/gates/test_gate_full_flaky_streak_1406.sh` -> exit 0 (8/8 PASS)
- `bash tests/super-board/test_setup_bin_list.sh` -> exit 0 (65 mục BIN PASS)
- `bash tests/super-board/test_sweep_closed_cards.sh` -> exit 0 (6/6 PASS)
- `bash universal-agent-devkit/tests/gates/test_gate_full_close_proven_cards.sh` -> exit 0 (16/16 PASS)
- `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` -> exit 0 (`pass`, 8/8 suite)

## Kiểm thử thực tế (chỉ đọc) & Đánh giá bổ sung
- `super-board-status.py geelyex2` (chạy trên `/Volumes/Data/Toan/GeelyEx2`): exit 0, hiển thị `ungated merges (7d): 7  (2026-11-20: 2, 2026-11-17: 5)`.
- `super-board-audit-sweep.py sweep --dry-run` trên GeelyEx2: exit 0, `ungated_total_7d=7`, `warned_issues=[413]`; ghi nhận `#409` của GeelyEx2 hiện đã ở trạng thái `OPEN` với nhãn `ac-open` (`REOPENED`).
- `super-board-audit-sweep.py sweep --dry-run` trên `agent-workbench`: exit 0, `ungated_total_7d=0`, `reopened=[]`.
- `.claude/skills/super-qa/SKILL.md`: `19976` bytes (< 20000).
- `pr-security-review`: 0 findings (confidence >= 8).
- Test-gap check: 0 High gaps; 2 Medium gaps (branch fallback `head:issue-<N>-` prefix collision và reopen thẻ đã có `ac-open` khi đóng `COMPLETED`).
- Không có UI nên bỏ qua ảnh chụp; AC4 (chạy sweep thật trên GeelyEx2 sau sync kit) giữ chưa tick để gắn `ac-open`.
