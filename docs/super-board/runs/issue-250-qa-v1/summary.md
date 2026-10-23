# QA #250 v1 — reviewer không chạy lại gate --full

Lệnh: `bash tests/super-board/test_reviewer_no_gate_rerun.sh`
- Base (origin/main): exit 1, FAIL 4 (thiếu "never rerun post-fix-gate --full" ở prompt reviewer, run.md, SKILL; SKILL còn "rerun it yourself") — RED
- Nhánh PR: exit 0, PASS 6/6 — GREEN
- Merge gate vẫn thêm `--force-full`: ✔

Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` trên head sau khi merge origin/main
- Lần 1: REJECT (nhánh tụt 2 commit so với main, thiếu test của #252/#253) → merge main vào nhánh
- Lần 2: exit 0, hồi quy 55/55, lớp tĩnh đạt

Ảnh: không cần — chỉ đổi tài liệu skill, prompt workflow và test shell.
