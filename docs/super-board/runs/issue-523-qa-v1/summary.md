# QA #523 v1 — devkit_incident: dòng PASS chứa RUNAWAY không sinh thẻ

Head kiểm: 6abd15ec (đã merge origin/main, không xung đột).

| AC | Kết quả | Bằng chứng |
|---|---|---|
| Test ĐỎ→XANH ở tầng thấp nhất | ✅ | `bash universal-agent-devkit/tests/verification/test_devkit_incident.sh` |
| Dòng `kitbug845deab14903` không còn sinh thẻ | ✅ | ca 22c |

- ĐỎ (script gốc origin/main + test mới): `✖ dòng PASS test hồi quy sinh thẻ runaway: create=21 (trước 20)`, exit 1.
- XANH (script có sửa): `PASS test_devkit_incident`, exit 0.
- Ca 23 / `RUNAWAY (daemon)` vẫn xanh: `🛑 halt — RUNAWAY` vẫn thành thẻ.
- `post-fix-gate.py --run-tests --brief`: exit 0 (2/2 hồi quy, lớp tĩnh đạt).
- Phạm vi diff: 2 file, +7 dòng. Không ảnh UI (backend).
