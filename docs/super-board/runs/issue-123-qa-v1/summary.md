# QA #123 v1 — merge-policy bắt DROP/TRUNCATE dạng hợp lệ

Head đã test: `579d1b73` (PR #164). Không có UI nên không có ảnh chụp.

| AC | Lệnh | Kết quả |
|---|---|---|
| 3 ca ra category schema | `bash tests/super-board/test_merge_policy_sql_forms.sh` | exit 0, 10/10 |
| Đối chứng âm vẫn auto | cùng test (5 ca âm) | exit 0 |
| Test cũ vẫn PASS | `test_merge_policy_odd_newlines`, `test_merge_gate_ff`, `_squash_sync`, `_devkit_from_main`, `_identical_sync` | cả 5 exit 0 |

RED đối chứng: chạy test mới với `super-board-merge-policy.py` của origin/main (bản chép ở thư mục tạm)
cho 4/10 ca đỏ (DROP/**/TABLE, DROP/*x*/TABLE, ALTER TABLE DROP email, TRUNCATE users). Bản của nhánh: 10/10 xanh.

Gate: `post-fix-gate.py --run-tests --full --brief --diff 334f3d17` (merge-base) exit 0, 39/39.
`--diff origin/main` cho exit 1 vì nhánh chậm 3 commit so với main (test_heavy_slot_cap.sh chưa có trong nhánh), không liên quan diff này.

Test gaps (not written):
- Medium: `DROP -- c` xuống dòng `TABLE users` (comment `--`): added_text gộp dòng nên không tách được comment, không bị bắt.
  Ngoài phạm vi AC (chỉ nêu `/**/`); đáng thẻ Backlog riêng.
- Low: `TRUNCATE <từ>` khớp cả văn xuôi/comment, lệch về phía an toàn (Builder đã ghi ở Risk).
