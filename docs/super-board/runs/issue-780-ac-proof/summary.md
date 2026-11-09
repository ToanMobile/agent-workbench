# #780 · chứng minh 4 AC trên origin/main 5ec86f09

Bản sửa đã vào main qua PR #794 (merge b0edceb0). PR này chỉ thêm bằng chứng cho AC còn thiếu (T0054).

## AC1 · Test tái hiện: bản cũ ĐỎ, bản mới XANH
- Lệnh: `bash universal-agent-devkit/tests/verification/test_impeccable_pipefail_guard.sh`
- Trên main 5ec86f09: exit 0, `ALL 4 CHECKS PASSED` (PROF_OUT 6000 dòng, ENV_DUMP ~160 KB, đối chứng âm `backend`, quét tĩnh pipefail).
- ĐỎ của bản cũ: ghi ở PR #794 (`rc=1` trên origin/main trước sửa, `printf: write error: Broken pipe`).

## AC2 · test_impeccable_skill.sh XANH 20/20
- Lệnh: `bash universal-agent-devkit/tests/verification/test_impeccable_skill.sh`
- Trên main 5ec86f09: 5/5 lượt exit 0, `ALL 29 CHECKS PASSED`; 20/20 dưới `lane_lock` ghi ở PR #794.

## AC3 · Kiểm kê test kit cùng mẫu pipe + grep -q dưới pipefail
- Đã sửa 2/2 file vi phạm ở PR #794; ca "Self-test + quét tĩnh" của test ở AC1 khoá: 0 file test bật pipefail còn pipe sang grep thoát sớm.

## AC4 · Gate scoped exit 0
- Reviewer đã chạy `post-fix-gate.py --run-tests --scoped --brief` tại head merge 1d0681d8: exit 0, 7/7 suite, biên nhận scoped `f4eede457c16a01a449443e2` (comment [reviewer] trên #780, 01/11 17:01).
- Gate scoped của PR này: xem comment `[builder] [report]` trên PR.
