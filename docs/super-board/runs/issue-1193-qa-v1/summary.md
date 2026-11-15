# QA #1193 v1 — PASS
- Test: `bash tests/super-board/test_session_card_sweep.sh` trên PR head sau khi merge origin/main: exit 0, ALL PASS (9 ✔)
- RED: cùng test với runner của main và không có helper: exit 5, 5 ✖ (read failure rc=2, runner has no sweep_dead_sessions)
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua super-board-qa-exit2.sh: `pass`
- Security pass: không có phát hiện (subprocess dạng list, SID giới hạn ký tự, không shell)
- AC1 đóng thẻ phiên chết: ✔ · AC2 không đụng phiên sống/PR mở: ✔ · AC3 ĐỎ→XANH: ✔
