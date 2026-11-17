# QA #1259 · PR #1260 · head bedd104614

| AC | Kết quả | Bằng chứng |
|---|---|---|
| 1. Block merge-queue ≤ ~16 dòng, hết `Why I (bot)`, `Move back`, `Checked` | ✅ | 15 dòng; bản main cũ: 55 dòng |
| 2. Log gate cắt còn 6 dòng + dòng báo phần còn lại | ✅ | test thấy dòng 1 còn, dòng 40 mất |
| 3. `writing-standard.md` + luật 00 có văn phong, ảnh hiện thẳng, mẫu comment | ✅ | đọc diff, 3 mục có mặt ở cả hai file |
| 4. Test mới ĐỎ→XANH, test cũ merge-queue đạt | ✅ | ĐỎ (3 lỗi) trên script main; XANH trên PR; 9 test cũ rc=0 |

Lệnh: `bash tests/super-board/test_merge_queue_short_comments.sh` (PR: PASS 6/6; script main: FAIL 3).
Test cũ chạy: refused_detail, merge_queue, e2e, route_rows, reject_card_note, root_cause_cap, gate_exit_14, unverified_edited_test_1235, parallel, decision_reader: tất cả rc=0.
Security pass: diff chỉ đổi chữ comment và tài liệu, không có input ngoài, secret hay quyền: không có finding.
Còn hở (đúng phạm vi ticket): các khối Block cứng ở `super-board-run.sh`, `block-template.md` vẫn dùng mẫu cũ.
