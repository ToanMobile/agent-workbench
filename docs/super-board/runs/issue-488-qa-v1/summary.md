# QA #488 v1 — tlimit bắt INT/TERM, killpg nhóm con

Base: origin/main a412df1c đã merge vào nhánh. Helper: universal-agent-devkit/tests/lib/tlimit.py

| AC | Lệnh | Kết quả |
|---|---|---|
| 1 RED | `TLIMIT=<tlimit cũ trích từ origin/main> bash tests/gates/test_tlimit_signal.sh` | exit 1: SIGTERM để lại grandchild mồ côi, SIGINT exit 1 thay vì 130 |
| 2 GREEN | `bash tests/gates/test_tlimit_signal.sh` | exit 0, 6/6: grandchild dừng với TERM và INT, rc 143/130, rc 7 giữ nguyên, timeout 124 |
| 3 | `test_gate_readonly_receipt_race.sh` / `test_gate_stop_reuse_race.sh` | cả hai exit 0; 48.8 s / 27.5 s (Builder đo 52 s / 39 s) |

Ghi chú: dòng "timeout: 1" ở ca RED do tlimit cũ trích tay, không phải lỗi sản phẩm.
