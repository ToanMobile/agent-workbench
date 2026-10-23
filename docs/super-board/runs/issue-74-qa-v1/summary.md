# QA #74 · PR #204 · v1 (head 691a8e10)

Kết quả: PASS

| AC | Bằng chứng |
|---|---|
| Edit → bash test_*.sh exit 0 → "test PASS" cho qua | `bash tests/verification/test_evidence_runners.sh` exit 0, "all checks passed" |
| exit 1 hoặc chạy trước lần sửa cuối vẫn chặn | ca `exit 1` và ca thứ tự trong cùng suite, xanh |
| `bash -c 'echo ✔'`, `cat test_y.sh` không tính | ca `-c`, `cat`, `; true`, `|| true`, pipe, `&` đều giữ đỏ, xanh |
| ĐỎ→XANH + đột biến | QA tự đột biến 2 chỗ trong hook: bỏ chốt pipe/`&` → 2 dòng ✖; bỏ luật một segment → 2 dòng ✖; đã khôi phục, cây sạch |

Lệnh: `post-fix-gate.py --run-tests --full --diff origin/main --brief`
- Lần 1: exit 1, 44/46: REG-DK-SESSION-01 FAIL thoáng qua (chạy riêng 2 lần exit 0; diff không đụng session) và REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 UNTESTED (khoá cache hết hạn).
- Lần 2: exit 0, 46/46.
- `test_suite_env.sh` exit 0.

Không có giao diện: không cần ảnh. Log thô giữ ngoài nhánh.
