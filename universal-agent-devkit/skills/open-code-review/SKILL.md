---
name: open-code-review
description: Dùng khi cần review code tự động, kiểm tra chất lượng git diff trước khi commit/PR bằng OpenCodeReview CLI (Alibaba Group). Chạy chế độ Delegation (OCR không gọi LLM).
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

> **Chạy bằng `.agents/devkit/bin/ocr-review`.** LLM của OCR đã gỡ hẳn (chủ repo 19/11, #1332): helper luôn chạy chế độ Delegation, không bao giờ gọi `ocr review`, và in `mode: delegate` + `spec: <file>` (spec ghi ra thư mục tạm, không ghi vào repo). Giao spec đó cho một reviewer context sạch (Agent tool); phát hiện của nó là phần OCR. Stop hook `review_gate.sh` tính lượt `ocr-review` (không phải `--delegate-only`) có spec của chính lượt chạy, kèm một agent review SAU nó.

### Chế độ Ủy quyền (Delegation Mode — `ocr delegate`)
Chính Host Agent (Claude Code / Antigravity) tự review bằng model của mình; OCR chỉ chọn file và luật, không gọi LLM:

```bash
# Bước 1: Để OCR phân tích diff, loại trừ file rác và xuất danh sách file cần review
ocr delegate preview --format json

# Bước 2: Để OCR phân giải các bộ luật review phù hợp cho từng file
ocr delegate rule --format json <file1> <file2> ...

# Bước 3: Host Agent tự đọc diff và áp dụng luật để xuất nhận xét
```

`ocr review` và `ocr scan` gọi LLM của OCR: không dùng (#1332).

---

## 3. Quy chuẩn Kết hợp với Automotive Zero-Regression

Khi review theo spec OCR trong dự án ô tô / hệ sinh thái phức tạp:
1. **Pass Condition:** 0 lỗi Critical/High liên quan đến:
   - Thay đổi không an toàn ở luồng dùng chung (Shared Flow breach).
   - Xóa hoặc nới lỏng Guard Conditions (`Build.VERSION.SDK_INT <= 28`, `FlymeAuto`).
   - Rò rỉ thông tin nhạy cảm, token, credentials.
2. **Sửa lỗi theo gợi ý:** Nếu OCR đưa ra `suggested_diff`, kiểm tra lại call-sites trước khi áp dụng.

---

## 4. Ba Nguyên Tắc Phản Biện Chống Mù Quáng (Adversarial Review Discipline)

Khi Host Agent hoặc Reviewer độc lập thẩm định diff (Delegation mode hoặc hậu kiểm OCR):
1. **Blind-First Pass (Chống hiệu ứng mỏ neo):** Đọc Acceptance Criteria + `git diff` thô và tự đặt 2–4 giả thuyết lỗi (*điều gì sẽ vỡ với dữ liệu thực hoặc caller hiện hữu?*) **TRƯỚC KHI** đọc bản tóm tắt hay `result.json` của người viết code. Lời khai của Builder là mệnh đề cần kiểm chứng, không phải khung dẫn dắt.
2. **Review Remembers (`R1, R2...` — Không dời cột gôn):** Ở vòng review lại (rework), bước đầu tiên bắt buộc là chấm trạng thái từng finding của vòng trước (`fixed` kèm `file:line` | `not fixed` | `no longer applies`) rồi mới tìm lỗi mới.
3. **Không chặn code đúng chỉ vì gu (Taste Never Blocks):** Góp ý về cấu trúc/độ sâu module (`Over-engineering` / `Deepening opportunity`) chỉ xếp mức `Should fix` hoặc tách task — **không bao giờ dùng làm lý do duy nhất để BLOCK một bản diff chạy đúng, an toàn và đã PASS test**.
