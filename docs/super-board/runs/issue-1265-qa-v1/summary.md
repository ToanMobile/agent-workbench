# QA #1265 v1 — PASS

## Tóm tắt kiểm thử (Tiếng Việt)
- **Test mục tiêu:** `bash universal-agent-devkit/tests/worktree_git/test_worktree_active_profile_clean.sh`
  - Trên `origin/main` (RED): `exit 4`, 4 fail (`M .agents/active-profile.json` ở Ca 1, Ca 2a, Ca 2b và `Khong ghi pham vi` ở Ca 3), Ca 4 control pass.
  - Trên nhánh PR #1337 sau merge `origin/main` (GREEN): `exit 0`, 5/5 ca PASS (`ALL PASSED`).
- **Test worktree liên quan:** `bash universal-agent-devkit/tests/worktree_git/test_worktree_lane.sh` -> `exit 0`, `test_worktree_lane: PASS` (không sửa test cũ).
- **Cổng scoped:** `CLAUDE_PROJECT_DIR="$PWD" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json | .claude/bin/super-board-qa-exit2.sh --root "$PWD"` -> `pass` (`exit_code: 0`, 6/6 quy tắc hồi quy PASS).
- **Bảo mật (`pr-security-review`):** 0 phát hiện mức high-confidence (≥ 8/10) trên `agent-config.py`, `install.sh`, `worktree.py`.
- **Ảnh chụp màn hình:** bỏ qua có chủ đích — thay đổi thuần CLI/tooling/worktree không có giao diện UI; bằng chứng là kết quả chạy thật ĐỎ→XANH và log lưu ngoài nhánh.

## Đối chiếu Acceptance Criteria
- AC1 (`git status` sạch khi chạy lại): Đạt — Ca 1, 2a, 2b ĐỎ trên `origin/main`, XANH trên PR #1337.
- AC2 (`pm_dispatch kind=audit` ghi `Pham vi:`, không in `Khong ghi pham vi`): Đạt — Ca 3 ĐỎ trên `origin/main`, XANH trên PR #1337.
- AC3 (Không sửa test cũ): Đạt — chỉ thêm mới `test_worktree_active_profile_clean.sh` và rule `REG-1265-ACTIVE-PROFILE-CLEAN-01`.

## Khoảng trống test chưa viết (Test gaps - Medium/Low)
- Medium: `_reuse_lane` khi worktree review đã tồn tại trước đó và bị lệch `profile.json` mới được kiểm tra gián tiếp qua shared helper `_run_install_in_worktree` và `test_worktree_lane.sh`, chưa có ca tách riêng trong `test_worktree_active_profile_clean.sh`.
