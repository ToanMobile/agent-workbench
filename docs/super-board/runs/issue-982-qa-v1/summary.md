# QA #982 v1 — PR #1135 (head 015f250c)
- `bash tests/super-board/test_merge_queue_root_cause_cap.sh`: exit 0, 6/6 ✔ (cùng hash ở cap ⇒ Blocked 🛡, không loop:rebuild-3; hash khác ⇒ loop:rebuild-1 về Ready; comment queue có dòng root-cause-hash)
- `bash tests/super-board/test_status_rebuild_cap.sh`: exit 0, 4/4 ✔ (attempt N/cap từ config; cap 4; mặc định 2; cap 0 ⇒ 2)
- Gate `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass` (exit 0), trên base origin/main đã merge (Already up to date)
- RED: hai test là file mới; trước PR status.py in `attempt N/3` (cap 2) và merge-queue không so hash. Không tự chạy lại trên base (hook chặn checkout -- path).
- Lưu ý: runner super-board-run.sh không đổi; việc chặn nằm ở merge-queue.sh (nơi đếm loop:rebuild-N) — khớp Fix của issue về hành vi.
