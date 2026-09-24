---
description: "Post-fix gate: static diff checks (secrets, placeholders, dependencies, perf, swallowed errors, raw logs) plus the regression tests of the active matrix; only exit 0 is PASS"
---

# /audit-gate — Post-Fix Audit & TIA Regression Gate

Chạy cổng kiểm toán sau khi sửa lỗi trên các file thay đổi của dự án (working tree, hoặc `--diff <ref>`).

**Chặn thật (quyết định verdict):**
1. 6 kiểm tra tĩnh:
   - bí mật (key/token/password, tên file cấm như `*.jks`, `*.key`, `.env`)
   - placeholder lười biếng (`// ... existing code ...`)
   - dependency: version thả nổi (`1.+`, `latest.release`, npm `latest`/`*`, Cargo `*`, pubspec `any`, Maven `LATEST`) và nguồn tải qua `http://` / tắt TLS (Gradle `maven { url }`, `.npmrc`, pip `--index-url`, Podfile `source`) — chỉ quét file manifest, trích nguyên dòng vi phạm
   - anti-pattern hiệu năng
   - nuốt lỗi (`catch {}`, `except: pass`)
   - log thô
2. Test hồi quy TIA với `--run-tests`:
   - Gate chạy thật các lệnh trong `regression_matrix.json`.
   - Lệnh được đọc từ bản đã commit (`HEAD`, hoặc ref của `--diff`), không đọc từ working copy.
   - Nếu matrix hoặc file test đã có bị sửa/xoá trong chính thay đổi, verdict là CHƯA XÁC MINH.

**Agent phải làm thêm, gate không tự làm và không tính vào exit code:**
- Ảnh nghiệm thu của chính lượt: `rules/essentials.md` mục "Every prompt". Exit 0 không thay PNG. Câu trả lời không được mở bằng XONG khi thiếu ảnh.
- Bằng chứng RED → GREEN khi sửa lỗi.
- DESIGN.md / a11y: gate chỉ kiểm file tồn tại.
- Immutable Guards.
- OpenCodeReview (`ocr`).

## Sử dụng
```bash
python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full
```

Exit code:
- `0`: PASS. Chỉ exit `0` mới được coi là đạt.
- `1`: REJECT.
- `2`: CHƯA XÁC MINH. Các trường hợp:
  - dry-run;
  - file không đọc được;
  - matrix chưa commit hoặc bị sửa;
  - test đã có bị sửa;
  - không test hồi quy nào khớp (thêm `--allow-no-tests` nếu chấp nhận);
  - có file code thay đổi mà chưa test hồi quy nào theo dõi (`⚠️ UNCOVERED` trong checklist — thêm vào matrix hoặc `regression_checklist.py link`);
  - `--diff` không hợp lệ.
- `3`: không có thay đổi để kiểm. Các link và state do DevKit cài không tính là thay đổi.

`--record-lesson` chỉ ghi vào `.agents/instincts.md` khi verdict là PASS, với id `[INSTINCT-NNN]` kế tiếp (cùng bộ ghi với `agent-kit learn`; tiêu đề đã có thì không ghi trùng).

`--staged`: chỉ chạy 6 kiểm tra tĩnh trên nội dung đã `git add` (đúng thứ sẽ được commit) — không chạy test, không probe thiết bị, không ghi báo cáo. Sạch ⇒ exit `2` (test chưa chạy), không bao giờ là PASS. Đây là thứ git pre-commit hook của `agent-kit githooks install` chạy.

### Regression checklist (tự động, xuyên suốt các task)
Mỗi lần gate chạy, nó cập nhật `.agents/CHECKLIST.md` (dashboard; `.agents/regression_checklist.md` là link tới nó) và `.agents/regression_status.json` (dữ liệu gốc):
- Mỗi test trong `regression_matrix.json` là một dòng: ✅ PASS / ❌ FAIL / ⏳ chưa chạy, kèm thời điểm, task (`--task T0001-...`), commit và 10 lần chạy gần nhất.
- **PASS/FAIL chỉ ghi khi gate chạy test thật (`--run-tests`)** — dry-run không đổi kết quả; không có lệnh nào để tự đánh dấu PASS.
- File code thay đổi mà không rule nào của matrix bao phủ ⇒ dòng `⚠️ UNCOVERED:<file>`. Gắn vào test thật: `python3 bin/regression_checklist.py link UNCOVERED:<file> <TEST-ID>`.
- `--record-lesson` trên một lần gate PASS ⇒ thêm dòng `BUG-…` link tới các test vừa pass; dòng bug luôn hiện kết quả thật của test đó.
- Commit hai file này để cả team thấy trạng thái. `--no-checklist` để tắt.
- Stop hook `regression_gate.sh` tự chạy gate này (`--run-tests`) mỗi khi agent định kết thúc với thay đổi chưa commit, và chặn nếu test liên quan fail hoặc có file UNCOVERED (chỉ với matrix riêng của project; `REGRESSION_GATE=0` để tắt).

