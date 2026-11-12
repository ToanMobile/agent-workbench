# QA #982 v2 (rebuild 1) — PR #1135 @ a8ee4088
Base: origin/main đã merge (Already up to date).
- tests/super-board/test_merge_queue_root_cause_cap.sh: exit 0, 6/6 (gồm ca comment [qa]/[builder] xen giữa)
- tests/super-board/test_status_rebuild_cap.sh: exit 0, 4/4
- post-fix-gate --run-tests --scoped --brief --json | super-board-qa-exit2.sh: `pass` (exit 0)
Review: comment queue mang tiền tố `[merge-queue]` khớp `last --from "[merge-queue]"`; AC1 (cùng hash ở cap ⇒ Blocked 🛡, khác hash ⇒ đếm lại từ 1) và AC2 (attempt N/<rebuild_cap>) đạt.
