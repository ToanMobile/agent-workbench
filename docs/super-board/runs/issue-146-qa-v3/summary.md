# QA #146 v3 — đạt (head sau merge origin/main dec64a3c)

- Lệnh: `bash tests/super-board/test_merge_gate_heartbeat.sh` → exit 0, 6/6 xanh.
- Đột biến: xoá dòng `kill -0 "$owner"` → ca 4 ĐỎ (at 1792620467 -> 1792620471); khôi phục → 6/6 xanh, cây sạch.
- Gate: `post-fix-gate.py --run-tests --full --diff origin/main` → exit 0, hồi quy 42/42.
- Diff so với main: 4 file (merge-gate.sh, test heartbeat, summary v1/v2); không đụng test_notify.py.
- AC1–AC4: đủ bằng chứng (ca 1–4 + đột biến + gate).
