# QA v4 · issue #1333 · PR #1334 (head 6dde919 + merge origin/main)

Lệnh (đặt CLAUDE_CODE_SESSION_ID=qa-x), tất cả exit 0:
- test_create_task_fold_cap.sh (AC1, AC2, 11a/11b/12a/12b)
- test_create_task_from_file.sh (10a/10b, AC1)
- test_create_task_batch.sh
- test_devkit_incident.sh
- test_gate_full_card_ac_provable.sh
- post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh -> `pass`

AC3: skill create-task ghi luật 1 yêu cầu 1 thẻ (diff SKILL.md).
AC4: RED→GREEN theo comment builder lượt 2; test_create_task_from_file.sh là test cũ bị sửa -> cần duyệt chéo.
AC5: PR body phải ghi rate_limit graphql (reviewer kiểm).
Không có UI, không ảnh.
