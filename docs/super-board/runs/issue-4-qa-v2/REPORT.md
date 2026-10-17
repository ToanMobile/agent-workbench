# QA v2 · issue #4 · PR #33 · head `e5cb84e`

Kết luận: ✅ đạt cả 2 AC. Không có giao diện nên không có ảnh chụp (AC là hành vi của Stop hook `test_evidence_gate.sh`).

## AC ↔ test

| AC | Test chứng minh | Head `e5cb84e` | Kit `origin/main` `22f5c75` |
|---|---|---|---|
| AC1 · `gate-green` của `post-fix-gate.py` được check 7 công nhận | `test_evidence_check7_pair.sh:87`, `:90` | ✔ exit 0 | ✖ exit 2 `CHECK 7` |
| AC1 · cùng ca với stdout THẬT của gate (không phải chuỗi viết tay) | `ac1-real-gate-replay.txt` | ✔ exit 0 | ✖ exit 2 `CHECK 7` |
| AC2 · sửa file test sau cặp RED→GREEN không làm mất cặp | `:89`, `:90`, `:91` (thư mục tạm) | ✔ | ✖ |
| AC2 · sửa rồi `git commit` file test (ca QA thêm) | `:95` | ✔ | ✖ |
| Check 2 giữ nguyên (quyết định R4): claim "test pass" sau lần sửa test chưa chạy lại vẫn bị chặn | `:113`, `:114` | ✔ exit 2 `TEST-EVIDENCE` | ✔ exit 2 |
| Vẫn chặn: không có ĐỎ, gate PASS trước bản sửa, sửa source sau XANH | `:103`–`:106` | ✔ | ✔ |

- Test cặp: head 19/19 xanh (`pair-head-e5cb84e.txt`); kit `main` 7/19 đỏ (`pair-main-22f5c75.txt`): 5 ca AC + 2 ca thắt chặt có chủ đích (`:108`, `:109`).
- Đột biến (bản sao kit trong scratch, `mutate.py.txt`): 5/5 bị bắt (`mutants.txt`).
  - M1 check 7 chỉ nhận `green` (`test_evidence_gate.sh:1746`): 2 ca đỏ.
  - M2 bỏ `is_test_path` ở marker project (`:1127`): 5 ca đỏ, gồm ca commit mới `:95`.
  - M3 bỏ `is_test_path` ở marker thư mục tạm (`:1120`): 1 ca đỏ.
  - M4 check 2 dùng marker của check 7 (`:1577`): 2 ca đỏ.
  - M5 bỏ fallback tầng chỉ có sửa test (`:1739`): 3 ca đỏ.

## Test-gap check (ca biên, `edge-probes.txt`, harness `probe.py.txt`)

| Ca | Head | Main | Đánh giá |
|---|---|---|---|
| G1 chỉ `git commit` file test sau XANH | 0 | 0 | đúng (lệnh Bash không dời marker) |
| G1b sửa + commit file test sau XANH | 0 | 2 | đúng AC2 → đã ghim thành `:95` |
| G2 gate FAIL không phải nửa ĐỎ | 2 | 2 | đúng thiết kế (nửa ĐỎ phải là runner thật) |
| G3 gate PASS `0/0` làm nửa XANH | 2 | 2 | đúng (đã ghim cho check 2 ở `test_evidence_runners.sh:103`, cùng `runner_state`) |
| G4 gate FAIL làm nửa XANH | 2 | 2 | đúng |
| G5 `Write` (không phải `Edit`) file test sau XANH | 0 | 2 | đúng AC2 |
| G6 sửa test Kotlin `src/test/` sau XANH | 0 | 2 | đúng AC2 |
| G7 sửa `tests/unit/conftest.py` (helper lồng thư mục) sau XANH | 2 | 2 | Medium: `is_test_path` không nhận helper lồng thư mục; chặn thừa, an toàn |
| G8 sửa file PRODUCTION tên `src/test_utils.py` sau XANH | 0 | 2 | Low: nới mới — file production tên kiểu test bị bỏ qua; đo 5 repo: 0 file như vậy (`g8-test-path-count.txt`) |
| G9 RED, sửa, XANH, sửa test, ĐỎ lại (không chạy sau) | 0 | 2 | Medium: đã ghi ở mục Risk của PR |

## Gate

- `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main --timeout 3600` → exit 0, PASS 7/7 suite (`gate-run1.txt`):
  - REG-DK-HOOK-01 hook contract · REG-DK-HOOK-02 proof gate · REG-DK-ALL-01 `run_impacted.sh` (45 test, gồm `test_evidence_check7_pair.sh`, `test_evidence_runners.sh`, `test_run_impacted_order.sh`, `test_repo_consistency.sh`)
  - REG-DK-GATE-01/02 · REG-DK-SESSION-01 · REG-DK-COST-01
- OCR (`ocr-review`, workspace so với `e5cb84e`): 0 finding trên ca test QA thêm.

## Ghi chú

- Kit `origin/main` lấy bằng `git archive origin/main` vào scratch, chạy cùng test qua `EG_KIT=`.
- Không cần ảnh: thay đổi chỉ ở Stop hook và test của DevKit.
