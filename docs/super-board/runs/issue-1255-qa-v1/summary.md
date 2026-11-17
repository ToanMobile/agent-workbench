# QA #1255 v1 — PASS
- Test mới: `bash tests/super-board/test_pr_size_guidance_1255.sh` → exit 0, 14 ✔ / 0 ✖ (PASS).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` → `pass` (đã merge origin/main, đang up to date).
- AC1: worker-preamble 5b + super-build "PR size (#1255)": ~400 dòng, không phải cổng, `auto_max_lines` = 0 (config: 0).
- AC2: super-review: Scope drift/Over-engineering (Should fix), không chặn merge.
- AC3: test mới là file mới; diff không sửa test cũ.
- AC4: 6 dòng thêm vào 3 file hướng dẫn (dưới 15).
- Ảnh: không cần (chỉ text hướng dẫn).
