# QA #516 v1 (PR #566, nhánh issue-516-decision-reader)

Head đã merge origin/main (7fda00d1): "Already up to date".

## Test đích
- `bash tests/super-board/test_decision_reader.sh`: PASS, 0 ✖ (27 ca, gồm 1 ca QA thêm).
- RED trên base: chép test vào `git archive origin/main`: FAIL (16 ✖). Cùng test trên nhánh: PASS.

## Test the tests (đột biến, đã khôi phục)
- M1 `at > last_mark` thành `at >= 0` (needs-you.py): trước đó SỐNG SÓT; QA thêm ca "needs-you mới hơn [decision] thì gắn lại": nay ĐỎ dưới M1.
- M2 bỏ so thứ tự decision/🙋 (deps.sh): đỏ (1 ✖).
- M3 tin mọi marker (decision.py): đỏ (2 ✖).

## Suite liên quan
- test_github_read, test_merge_queue: đỏ 1 lần dưới tải máy 56, xanh 2/2 lần chạy lại trên nhánh.
- test_merge_train F4 `no worker flag: exit 13`: đỏ cả trên origin/main sạch, không phải lỗi của PR.

## Gate
`post-fix-gate.py --run-tests --brief` chạy sau commit evidence; kết quả ghi trong comment `[qa] [report]`.

## Test gap (không viết, Medium/Low)
- 5 ca "luật 1–5" cùng một logic (chỉ khác chữ), chưa phân biệt luật theo nội dung.
- qa-report: một decision gỡ mọi mục Not done cũ hơn nó, không đối chiếu từng AC (đã ghi `ponytail:` trong code).
- STOP_RE chỉ xét `--action`, không xét nội dung decision.
