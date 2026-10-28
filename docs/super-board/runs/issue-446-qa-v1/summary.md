# QA #446 v1 — hw_emulator_window.window_limit

- Lệnh: `bash universal-agent-devkit/tests/gates/test_hw_emulator_window.sh` (sau merge origin/main, đã up to date)
- Kết quả: exit 0, 17 ✔ / 0 ✖ (10 ca window_limit giả + 2 ca 12000 dòng, hạn theo tải)
- AC1 (cores 0 / load Infinity / null → 1.0): đạt, ca "cores 0", "load Infinity", "load null" đều 1.0
- AC2 (hook trước 8abacc69 vẫn đỏ): bản v1 chứng minh sai — hook cũ đặt ngoài `hooks/` nên rc 2 do thiếu `shell_norm`,
  không phải do hành vi hook; ở tải thật hook cũ (1.1 s) vẫn dưới hạn. Sửa ở vòng rebuild-1: thêm tiêu chí tỉ lệ
  thời gian (big-eval / `eval 'ls'` cùng hook, ngưỡng x6). Hook cũ đặt trong bản sao `hooks/` đủ `shell_norm`:
  `✖ harmless 12000-line command (eval): rc 0, 1.10s x18.9 (want rc 0, under 1.9s and x6)` → ĐỎ do hành vi; hook mới x1.5 → XANH.
- Gate: `post-fix-gate.py --run-tests --brief --auto-approve-tests` exit 0 (1/1 hồi quy, lớp tĩnh đạt)
- Test-gap Medium/Low không viết thêm: load NaN, cores âm (đều rơi về 1.0 qua nhánh cores>0/isfinite).
