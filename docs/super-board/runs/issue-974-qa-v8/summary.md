# QA #974 vòng 8 · head ccf2e1a8 (đã gồm origin/main f7bb462b)
- test_kit_tests_devkit_fallback.sh: exit 0
- test_super_board_all_slots.py: exit 0
- test_runner_watchdog.sh: exit 0, 0 dòng skip (mục 9 chạy)
- Gate scoped (post-fix-gate --run-tests --scoped --brief --json qua super-board-qa-exit2.sh): `review` (test_super_board_all_slots.py và test_kit_tests_devkit_fallback.sh là test có sẵn bị sửa, cần Antigravity duyệt chéo)
- AC3 (drift 5 repo app): ngoài PR kit, tách sang ToanMobile/GeelyEx2#406
