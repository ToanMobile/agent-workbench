# QA #346 v1 — PASS
- unittest agent-office: `python3 -m unittest discover -s tests` → 75 OK, exit 0
- gate: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 83/83
- Trình duyệt (Chromium headless, 375×667, /api/phone cố ý chậm 3 s):
  - t0 sau khi bấm: `Đang lấy mã…`, hộp thoại đã mở, chưa có QR
  - t1.0s: vẫn `Đang lấy mã…` (waiting.png)
  - t4.5s: chữ chờ được thay bằng QR svg (done.png)
