# QA #471 v1 — batch_canary: train đỏ không tính là bằng chứng

- Lệnh: `bash tests/super-board/test_batch_canary.sh` — nhánh PR: exit 0 (PASS test_batch_canary).
- RED trên base (batch_canary.py của origin/main, test mới): exit 1, dòng quoted:
  `✖ #471: 2 PR merge lẻ + 3 train đỏ phải ĐỎ exit 1 (rc=0): merged PRs=2 merge-gate verifies=3 train verifies=3`
- GREEN trên nhánh PR: `2 merged PRs` + `no train verify` + `train verifies=0`, exit 1.
- AC2 (train PASS vẫn XANH): test 3i PASS cả trên base lẫn PR.
- Gate impacted (`post-fix-gate.py --run-tests --brief`, trên base đã merge): exit 0, hồi quy 2/2.
- Test gap (Medium, chưa viết): chưa đối chiếu từng PR với train phủ đúng PR đó (runs.jsonl chưa ghi số PR). Builder đã nêu ở handoff.
