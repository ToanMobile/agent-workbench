# QA #379 v1
- `bash tests/super-board/test_runner_self_reload.sh` → exit 0, "all passed" (ca 3 mới: ACTIVE_WORKERS=2 vẫn exec bản mới)
- Gate: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → PASS 106/106, exit 0
- Biên nhận cây đã verify: e26dba465a04 (--record)
- AC3: `self_reload_tick` nằm trước dispatch trong vòng tick (super-board-run.sh ~2675)
- AC2: `adopt_live_locks` (~1677) nhận lại worker sống qua `startup_reconcile` (không đổi)
- Chưa kiểm: runner thật với worker sống (không phải UI, không có ảnh)
