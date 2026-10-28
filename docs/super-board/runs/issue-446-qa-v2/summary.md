# QA #446 v2 — hw_emulator_window (sau rebuild-1, head ed910136)

- Lệnh: `bash universal-agent-devkit/tests/gates/test_hw_emulator_window.sh` (origin/main đã gộp, up to date)
- Kết quả: exit 0, 19 ✔ / 0 ✖ (7 ca chặn emulator, 10 ca window_limit giả, 2 ca 12000 dòng)
- AC1 đạt: cores 0 / thiếu, load Infinity / null / chuỗi, JSON list/chuỗi/không phải JSON đều 1.0; 36/12 = 3.0; kẹp 5.0.
- AC2 đạt (QA tự chạy lại): hook `8abacc69~1` qua `HW_HOOK`, đặt trong `hooks/` đủ `shell_norm`:
  `✖ harmless 12000-line command (eval): rc 0, 1.08s x19.6 (want rc 0, under 1.0s and x6)` → exit 1, ĐỎ do hành vi.
  Hook mới: 0.11 s x1.5 → exit 0.
- Gate: `post-fix-gate.py --run-tests --brief --auto-approve-tests` exit 0 (biên nhận task đã ghi).
- Test-gap Medium/Low không viết thêm: load NaN, cores âm (rơi về 1.0 qua nhánh cores>0 / isfinite).
