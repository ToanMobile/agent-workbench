# QA #323 v1 (PR #349, head 6572b3da)

Lệnh gate: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 85/85.

RED→GREEN từng thẻ con (nguồn thay bằng bản origin/main → test đỏ; bản nhánh → xanh):
- #234 test_worktree_remove_essentials_block.sh: RED rc=1 · GREEN
- #326 test_worktree_discard_squash.sh: RED rc=1 · GREEN
- #157 test_place_keeps_tracked_in_worktree.sh: RED rc=1 · GREEN
- #262 tests/super-board/test_approval_auto_merge_head.py: RED rc=1 · GREEN (5 test)
- #302 test_durations_union_merge.sh: GREEN (3/3), .gitattributes merge=union
- #327: đã vào main (#350), nhánh giữ bản main

Nhánh đã cập nhật với origin/main (Already up to date).
Chưa đạt: AC thẻ #301 (trunk mode, repo main protected vẫn bị finish ghi vào main) — Builder chưa làm.
