# QA #532 v1 — PR #563 (bằng chứng AC)

Head: nhánh đã merge origin/main 7fda00d1 (đã gồm #550).
Lệnh: `bash universal-agent-devkit/tests/verification/test_stale_rerun.sh`

- GREEN (stale_rerun.py hiện tại): exit 0, 3 test AC đều ✔
- RED (stale_rerun.py trước #550, 26c56a07^): exit ≠ 0, 2 failed
  - ✖ SIGINT: suite con mồ côi (-2 alive)
  - ✖ SIGTERM: suite con mồ côi (-15 alive)
  - ✔ quá giờ vẫn SIGKILL → TIMEOUT (AC3 giữ nguyên hành vi, xanh ở cả hai)
- Phục hồi file sau RED, cây sạch.
