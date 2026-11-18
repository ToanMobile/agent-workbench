# QA #1290 v1 — PASS

- Base: origin/main đã gộp vào head PR #1291 (706129c6).
- `bash universal-agent-devkit/tests/gates/test_gate_full_card_ac_provable.sh`: exit 0, 10/10 ca xanh (A–I, G2).
- `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass`, exit 0.
- AC1 (thẻ mới không có AC chỉ chứng minh được đêm sau): ca B, C.
- AC2 (đỏ kinh niên: thẻ đóng + không thẻ mở → mở lại; có thẻ mở → không trùng; chưa từng có thẻ → không thẻ): ca D, E, F, H, I.
- AC3 (test gate_full cũ vẫn qua): gate scoped pass; PR không sửa test cũ.
