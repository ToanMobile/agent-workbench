# QA #110 — merge train (v2, sau rebuild round 1)

Head đã test: `ded74ccf`
Lệnh: `bash tests/super-board/test_merge_train.sh` → exit 0 (20 kiểm tra ✔, 0 ✖)
Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` → exit 0, hồi quy 45/45
Merge: `git merge-tree origin/main HEAD` → sạch (không conflict)

| Mục | Bằng chứng |
|---|---|
| AC1: 3 PR, 1 lần verify, cả 3 merge | ca 1: verify=1, 3 file trên origin/main |
| AC2: 1 PR đỏ, chia đôi ra #5, 2 PR còn lại merge | ca 2: exit 11, đúng #5, file xấu không lên origin |
| AC3: 1 PR chạy như gate thường | ca 3: verify=1, không có dòng train |
| AC4: gh giả, ĐỎ trước XANH sau | builder: script chưa có → đỏ; có → xanh |
| R1: head-read exit 79 tới caller | ca 5, 2 kiểm tra ✔ |
| R2: timeout thử lại 1 lần, exit 12, không quy PR đỏ | ca 6, 4 kiểm tra ✔ |
| R3: ma trận giữ cả 2 rule, rule mới ở cuối | merge-tree sạch, gate 45/45 |
| R4: lời biên nhận chỉ chứng minh cây đầy đủ | run.md đã sửa |

Đột biến QA (v2): `|| exit $?` → `|| true` ở dòng đọc head của PR:
`✖ head read outage: exit 1 (want 79)` → test ĐỎ; khôi phục → XANH. Đột biến không vào commit.

Test gap chưa viết (Medium/Low, không chặn):
- Chuỗi không dựng được khi bisect (exit 5) chưa có fixture (builder đã nêu).
- Gate chặn giữa đợt khiến PR sau verify lại.
- R5 (over-engineering) để nguyên theo Reviewer: không chặn.
