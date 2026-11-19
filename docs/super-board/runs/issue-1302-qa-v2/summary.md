# QA #1302 v2 @ bd269e89 (đã merge origin/main)
- `bash tests/super-board/test_qa_head_settle_1302.sh`: exit 0, 8/8 PASS
- `bash tests/super-board/test_setup_bin_list.sh`: exit 0, PASS (BIN có helper, 62 script)
- Phá thử `attempt >= max_tries` thành 999: test đỏ (FAIL: 1); đã khôi phục.
- AC1 (head đổi → chạy lại, không Blocked): case 2, 3. AC2 (quá N lần / không đứng yên → Blocked kèm lý do + số lần): case 4, 5.
- Blocker/major của reviewer (BIN, fetch trước checkout, ls-remote lỗi, `$# -ge 2`): case 6, 6b, 7 + bin list.
- Không có UI: không cần ảnh. Log thô: /tmp, không commit.
