# QA #255 v1 — tách test_postfix_gate / test_gate_suite_cache thành nhóm song song

PR #273 · nhánh issue-255-parallel-gate-suites (đã merge origin/main trước khi đo)

## AC1 — thời gian giảm ≥ 50% (A/B cùng máy, bản cũ = origin/main, xen kẽ thứ tự)
Máy không rảnh (load 16–56), nên con số là cận xấu; một cặp mỗi suite (mỗi lần 1.5–3.5 phút).

| Suite | Cũ | Mới | Giảm |
|---|---|---|---|
| test_gate_suite_cache.sh | 92 s | 24 s | 74% |
| test_postfix_gate.sh | 204 s | 81 s | 60% |
| Tổng | 296 s | 105 s | 65% |

## AC2 — số ca và assertion không giảm
- cache: 44 ✔ / 0 ✖ cũ và mới; tập dòng ✔ giống hệt.
- postfix: 264 ✔ / 0 ✖ cũ và mới; tập dòng giống, chỉ lệch số đo thời gian trong ngoặc (1.02s vs 1.05s).

## Đột biến (nhóm song song không nuốt lỗi)
- M1: đảo kỳ vọng ca 32 trong suite cache → suite exit 1.
- M2: nhóm `coalesce` thoát sớm → in `✖ group coalesce did not finish`, exit 1.

## AC3 — gate `--full --diff origin/main`
`post-fix-gate.py --run-tests --full --brief --diff origin/main --auto-approve-tests` → exit 0, 56/56 hồi quy đạt.
Hai lần đầu không tính: nhánh tụt origin/main (thiếu file test mới) nên REJECT giả; lần có đủ nhánh nhưng không duyệt test cho exit 2 (chỉ vì 2 test cũ bị sửa, 56/56 đạt).
Hai test bị sửa được QA tự duyệt sau khi đối chiếu tập assertion và đột biến (xem trên).

## Chưa kiểm
- Trap dọn nhóm tiến trình khi INT/TERM (Builder cũng chưa thử).
- `test_merge_gate_load_wait.sh` không nằm trong tiêu đề/AC, chưa động tới.
