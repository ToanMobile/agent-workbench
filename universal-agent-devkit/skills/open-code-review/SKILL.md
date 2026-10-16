---
name: open-code-review
description: Dùng khi cần review code tự động, kiểm tra chất lượng git diff trước khi commit/PR, hoặc audit toàn bộ file bằng OpenCodeReview CLI (Alibaba Group). Hỗ trợ cả chế độ OCR-managed và Delegation mode.
---

# Open Code Review (`ocr`) — Alibaba Quality Engine

## 1. Tổng quan (Overview)

Tích hợp trực tiếp công cụ `ocr` (Alibaba Group OpenCodeReview) vào quy trình phát triển.
Công cụ giải quyết 4 điểm nghẽn lớn của AI code review truyền thống:
1. **Chống bỏ sót file (Incomplete Coverage):** Tự động phân rã changeset thành các bundle $\le 10$ file có quan hệ ngữ nghĩa để review độc lập, không "cắt xén" góc cạnh.
2. **Định vị dòng chính xác tuyệt đối (Deterministic Line Resolution):** AI chỉ trích xuất `existing_code`, engine Go tĩnh (`resolver.go`) tự đối chiếu Git Diff Hunks để tính `StartLine` và `EndLine` chính xác 100%.
3. **Độ chính xác cao (High Precision / Low Noise):** Đạt chuẩn benchmark AACR-Bench, ưu tiên loại bỏ nhận xét rác.
4. **Tiết kiệm token:** Chỉ tiêu tốn $\sim 1/9$ lượng token so với đưa toàn bộ diff thô vào prompt.

---

## 2. Các chế độ thực thi (Execution Modes)

> **Chạy bằng `.agents/devkit/bin/ocr-review` (khuyến nghị).** `ocr review` gửi diff tới một LLM và KHÔNG chạy nếu chưa có endpoint (`OCR_LLM_URL/OCR_LLM_TOKEN/OCR_LLM_MODEL`, `~/.opencodereview/config.json` qua `ocr config provider`, hoặc `ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN/ANTHROPIC_MODEL`): nó thoát 1 với "no valid LLM endpoint configured" (13/10: mọi lượt trên máy này đều vậy, nên OCR không được dùng). Phiên đăng nhập của Claude Code KHÔNG phải endpoint. `ocr-review` tự chọn: có endpoint thì Mode 1, không thì Mode 2 và ghi spec ra thư mục tạm (không ghi vào repo). Khoá LLM là bí mật: người dùng tự nhập bằng `ocr config provider` ngoài phiên agent; đừng export `ANTHROPIC_API_KEY` toàn cục (Claude Code cũng đọc nó). Stop hook `review_gate.sh` chỉ tính một lượt OCR là review khi nó có REPORT JSON thật (dòng `report: <file>` của helper, hoặc `ocr review … -o <file>`), ghi sau lần sửa code cuối; chữ trong output không đủ.

### Mode 1: Chế độ Review Diff Trực tiếp (`ocr review`)
Sử dụng khi cần review các thay đổi chưa commit (workspace), branch diff, hoặc một commit cụ thể.

```bash
# 1. Review toàn bộ staged, unstaged và untracked changes trong workspace
ocr review --audience agent

# 2. Review diff giữa nhánh hiện tại và nhánh main kèm ngữ cảnh nghiệp vụ
ocr review --from main --to $(git branch --show-current) -b "Automotive zero-regression fix"

# 3. Review 1 commit cụ thể
ocr review -c <commit-hash>

# 4. Xuất kết quả dạng JSON để script phân tích
ocr review --format json --output ocr-report.json
```

### Mode 2: Chế độ Ủy quyền (Delegation Mode — `ocr delegate`)
Sử dụng khi **không muốn cấu hình thêm API key ngoài cho OCR**, mà muốn chính Host Agent (Claude Code / Antigravity / Gemini) tự review bằng model của mình:

```bash
# Bước 1: Để OCR phân tích diff, loại trừ file rác và xuất danh sách file cần review
ocr delegate preview --format json

# Bước 2: Để OCR phân giải các bộ luật review phù hợp cho từng file
ocr delegate rule --format json <file1> <file2> ...

# Bước 3: Host Agent tự đọc diff và áp dụng luật để xuất nhận xét
```

### Mode 3: Quét Toàn Bộ File (`ocr scan`)
Sử dụng khi cần kiểm toán mã nguồn một thư mục hoặc file mà không có git diff:

```bash
ocr scan --path src/main/java/com/car/media/
```

---

## 3. Quy chuẩn Kết hợp với Automotive Zero-Regression

Khi `ocr review` được gọi trong dự án ô tô / hệ sinh thái phức tạp:
1. **Pass Condition:** 0 lỗi Critical/High liên quan đến:
   - Thay đổi không an toàn ở luồng dùng chung (Shared Flow breach).
   - Xóa hoặc nới lỏng Guard Conditions (`Build.VERSION.SDK_INT <= 28`, `FlymeAuto`).
   - Rò rỉ thông tin nhạy cảm, token, credentials.
2. **Sửa lỗi theo gợi ý:** Nếu OCR đưa ra `suggested_diff`, kiểm tra lại call-sites trước khi áp dụng.

---

## 4. Ba Nguyên Tắc Phản Biện Chống Mù Quáng (Adversarial Review Discipline)

Khi Host Agent hoặc Reviewer độc lập thẩm định diff (Mode 2 hoặc hậu kiểm OCR):
1. **Blind-First Pass (Chống hiệu ứng mỏ neo):** Đọc Acceptance Criteria + `git diff` thô và tự đặt 2–4 giả thuyết lỗi (*điều gì sẽ vỡ với dữ liệu thực hoặc caller hiện hữu?*) **TRƯỚC KHI** đọc bản tóm tắt hay `result.json` của người viết code. Lời khai của Builder là mệnh đề cần kiểm chứng, không phải khung dẫn dắt.
2. **Review Remembers (`R1, R2...` — Không dời cột gôn):** Ở vòng review lại (rework), bước đầu tiên bắt buộc là chấm trạng thái từng finding của vòng trước (`fixed` kèm `file:line` | `not fixed` | `no longer applies`) rồi mới tìm lỗi mới.
3. **Không chặn code đúng chỉ vì gu (Taste Never Blocks):** Góp ý về cấu trúc/độ sâu module (`Over-engineering` / `Deepening opportunity`) chỉ xếp mức `Should fix` hoặc tách task — **không bao giờ dùng làm lý do duy nhất để BLOCK một bản diff chạy đúng, an toàn và đã PASS test**.
