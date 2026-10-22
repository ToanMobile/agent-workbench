# QA #106 v1 — PASS

Lệnh: `bash tests/super-board/test_wave_needs_you_mark.sh` → exit 0 (PASS, 12 check).
RED: cùng test chạy trên super-board-wave.js của origin/main → FAIL (12), thiếu `super-board-needs-you.py mark` và `--next`.
Cú pháp: `super-board-needs-you.py mark --help` có đủ `--repo --issue --action --next`; wave.js bọc hàm qua `node --check` OK.
Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` → exit 0, 42/42 (sau khi gộp origin/main, giữ cả 2 entry ma trận).

| AC | Bằng chứng |
|---|---|
| Exit 7/8 nêu lệnh mark với --next comment done | tests/super-board/test_wave_needs_you_mark.sh (vòng for n in 7 8, 2 case `comment đúng một chữ done`) |
| Test khẳng định cả hai chuỗi chứa mark | REG-SB-WAVE-NEEDSYOU-01 trong ma trận |

Test gaps (not written): test là grep chuỗi prompt, không chạy lane thật (Low).
Ảnh: không cần — thay đổi chỉ là chuỗi prompt, không lên màn hình.
