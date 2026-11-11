# QA #867 v1 — shim adb

- Test: `bash universal-agent-devkit/tests/gates/test_adb_shim.sh` → exit 0, 46 ca ✔, 0 lỗi ("PASS: test_adb_shim").
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` trên head sau merge origin/main → `pass` (exit 0).
- Bảo mật: rà shims/adb + session_context.sh; `eval "home=~$user"` chỉ chạy khi $user khớp [A-Za-z0-9._-]; env chỉ THÊM denylist; fail-closed. Không có finding.
- Không sửa test cũ; hook hardware_safety_gate.sh không đổi.
- Không cần ảnh (tooling shell).
