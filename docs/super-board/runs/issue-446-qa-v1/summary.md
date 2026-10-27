# QA #446 v1 — hw_emulator_window.window_limit

- Lệnh: `bash universal-agent-devkit/tests/gates/test_hw_emulator_window.sh` (sau merge origin/main, đã up to date)
- Kết quả: exit 0, 17 ✔ / 0 ✖ (10 ca window_limit giả + 2 ca 12000 dòng, hạn 1.5 s)
- AC1 (cores 0 / load Infinity / null → 1.0): đạt, ca "cores 0", "load Infinity", "load null" đều 1.0
- AC2 (hook trước 8abacc69 vẫn đỏ): `HW_HOOK=<hook 8abacc69~1>` exit 1,
  `✖ harmless 12000-line command (eval): rc 2, 0.05s (want rc 0 under 1.4s)`
  Lưu ý: đỏ vì rc 2 (hook cũ chặn nhầm), không phải vì vượt hạn thời gian; vẫn thỏa "ĐỎ".
- Gate: `post-fix-gate.py --run-tests --brief --auto-approve-tests` exit 0 (1/1 hồi quy, lớp tĩnh đạt)
- Test-gap Medium/Low không viết thêm: load NaN, cores âm (đều rơi về 1.0 qua nhánh cores>0/isfinite).
