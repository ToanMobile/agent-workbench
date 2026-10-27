# QA v2 · #471 · PR #497 @ 1210d627 (đã merge origin/main)

Lệnh: `bash tests/super-board/test_batch_canary.sh` → exit 0 (PASS test_batch_canary)
- AC1: 2 PR merge lẻ + train đỏ → ĐỎ, nêu số PR (ca 3h) ✔
- AC2: train PASS → XANH (3i) ✔
- R1 rebuild: train exit 0 + verdict REUSED vẫn XANH (3j) ✔; train đỏ exit 2/3 không tính (3k) ✔
- Các ca cũ (enabled_at, backend, BUSY, exit 2, agent-health, nightly) vẫn ✔
Gate: `post-fix-gate.py --run-tests --brief` exit 0, hồi quy 2/2.
Test gap (Medium, không chặn): runs.jsonl chưa ghi số PR để đối chiếu từng PR với train phủ nó.
