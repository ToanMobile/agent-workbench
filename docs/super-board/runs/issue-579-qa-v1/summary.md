# QA #579 v1 — merge-train verify_timed_out (SIGPIPE dưới pipefail)

Nhánh: issue-579-verify-timed-out-sigpipe (đã gộp origin/main 46260cf0; xung đột với #588 giải bằng cách giữ `)` của #579 + `single_red_test` của #588).

## RED (hàm gốc trên origin/main, log > 128 KB, dưới `set -euo pipefail`)
- KẾT LUẬN + chỉ suite TIMEOUT: trả 1 (mong 0)
- Không KẾT LUẬN + "TIMEOUT after": trả 141 (mong 0)

## GREEN (nhánh đã sửa)
- Lệnh: `env -u SB_BOARD_WORKER -u SB_DAEMON -u SB_WATCHDOG_START bash tests/super-board/test_merge_train.sh`
- Exit 0, 80 ✔, 0 ✖: "test_merge_train: all passed"
- Lưu ý: biến SB_BOARD_WORKER của phiên QA làm ca F4 "no worker flag" đỏ nếu không bỏ biến (môi trường, không phải lỗi PR).

## AC
- [x] VLOG lớn, KẾT LUẬN + mọi suite TIMEOUT → 0 (RED→GREEN)
- [x] VLOG lớn, KẾT LUẬN + suite FAIL → khác 0
- [x] VLOG lớn, không KẾT LUẬN, "TIMEOUT after" → 0; rc=124 → 0
- [x] Không còn "Broken pipe"; test_merge_train.sh xanh

Rà `printf|grep -q` khác: dòng 270/274 nằm trong hàm đã sửa; dòng 100 là `sed|grep -v|tail … || true` (không dùng `grep -q`, không SIGPIPE).
