# QA #582 v1 — PASS

- Test: `bash universal-agent-devkit/tests/gates/test_gate_worktree_main_transcript.sh`
  - Bản gate gốc (origin/main): exit 1, `✖ main_transcript_approves: muốn True, được False` (ĐỎ, tái hiện lỗi).
  - Bản PR: exit 0, 6/6 case PASS (XANH).
- Case giữ chặt (không nới điều kiện): test sửa sau lời duyệt, nhãn "Không duyệt", transcript phiên khác trong cùng thư mục, thư mục con của repo cha, transcript dự án khác.
- Gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief` exit 0, hồi quy 12/12.
- Ảnh: không cần, thay đổi chỉ ở gate backend, không lên màn hình.
