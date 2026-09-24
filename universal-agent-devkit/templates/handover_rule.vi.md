LUẬT ĐỨNG — NGHIỆM THU THEO LOẠI LƯỢT. Áp dụng cho Claude Code, Gemini CLI, Antigravity, Codex, Cursor và Grok. Không có ngoại lệ theo loại agent.

0. Xếp loại lượt trước khi làm, ghi loại vào dòng 3 của câu trả lời.
   - A. Hỏi đáp, review, audit, lập kế hoạch: không sửa file nào trong repo.
   - B. Có sửa file trong repo, nhưng không đổi thứ hiển thị trên thiết bị Android.
   - C. Có sửa thứ hiển thị trên thiết bị Android: layout, Compose, `res/`, màn hình, chuỗi hiển thị, luồng thao tác.
   Sửa dù chỉ một file thì không còn là A. Dự án Android có sửa giao diện thì là C, không được khai B để tránh chụp ảnh.
   Web, iOS có UI: nếu `.antigravity-pm.json` khai provider chụp cho nền tảng đó thì làm bước 4 bằng provider đó, không khai thì là B.

1. Mọi loại — đọc trước khi làm: AGENTS.md, .agents/context/essentials.md, .agents/context/profile-rules.md, .agents/context/rules-index.md, và mọi file .agents/local/rules/ mà mục lục trỏ tới.
   Thiếu file trong .agents/context/ thì đọc nguồn của nó: .agents/devkit/rules/essentials.md, .agents/active-profile/RULES.md, và toàn bộ .agents/local/rules/. Ghi tên file thiếu vào câu trả lời. Không đoán nội dung file không đọc được.

2. Loại B, C — sửa lỗi hoặc thêm hành vi có thể test: viết oracle đỏ trước, chạy và thấy đỏ, rồi mới sửa production, chạy lại cùng oracle và thấy xanh.
   Lưu lệnh, output và exit code của cả hai lần vào reports/oracle-<yyyyMMdd-HHmmss>.log.
   Hai lần sửa cho cùng một nguyên nhân mà vẫn đỏ: dừng, bỏ giả thuyết đó, đổi hướng.

3. Loại B, C — cổng nghiệm thu, chạy từ gốc repo:
   python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full
   - Exit 0 (PASS): qua bước tiếp.
   - Exit 1 (REJECT): dán 30 dòng cuối log, sửa, chạy lại bước 3 từ đầu.
   - Exit 2 (UNVERIFIED) hoặc 4 (UNTESTED): dừng. Trả lời CHƯA XONG, dán lý do cổng in ra. Không sửa matrix hay test cũ để qua cổng.
   - Exit 3 (không có gì để audit) ở loại B, C: cổng không thấy thay đổi, thường do đã commit. Chạy lại với --diff <commit trước khi bắt đầu lượt>.
   Dry-run, --help, --staged, --run-tests không kèm --full và test Gradle lẻ không thay cổng này.
   Loại A không chạy cổng.

4. Chỉ loại C — ảnh nghiệm thu là luật chặn, cùng cấp với exit 0.
   - Chụp bằng `python3 .agents/devkit/bin/proof-capture.py` từ gốc repo. Lệnh đọc provider `type: adb` trong `.antigravity-pm.json` (tên tuỳ dự án: device, xe, mayao…). Serial khai báo chỉ được chụp khi `adb devices` báo `device` và không nằm trong denylist.
   - Serial đó offline, hoặc không có máy nào được phép: lệnh mở AVD (`proof.providers.<tên>.avd`, không khai thì máy ảo điện thoại duy nhất — bỏ qua AVD tên car/auto), đợi `sys.boot_completed=1`, rồi chụp `emulator-<cổng>`. Không screencap địa chỉ chết. Không đổi sang điện thoại đang cắm.
   - Lệnh thoát khác 0 (không có adb, không có AVD): CHƯA XONG, dán stderr. Cấm vẽ, cấm dùng lại ảnh cũ, cấm lấy XML test thay ảnh.
   - Cài bản vừa sửa lên serial lệnh in ra, thao tác đến trạng thái thành công, chạy lại lệnh để PNG là màn đó.
   - File lệnh ghi là `reports/proof-<yyyyMMdd-HHmmss>.png`. Phải là PNG thật (`file` báo PNG image data), lớn hơn 8 KB, thời gian sửa mới hơn lúc bắt đầu lượt. Gắn ảnh vào câu trả lời, kèm đường dẫn và serial lệnh in ra.
   - reports/ phải có trong .gitignore. Che token, số điện thoại, dữ liệu cá nhân trên màn hình trước khi gửi.

5. Ba dòng đầu câu trả lời:
   - Dòng 1: trạng thái.
     - Loại A: TRẢ LỜI.
     - Loại B: XONG chỉ khi có exit 0 của bước 3 trong lượt này, và log đỏ→xanh nếu bước 2 áp dụng.
     - Loại C: XONG chỉ khi có exit 0 của bước 3 và ảnh PNG của bước 4, cả hai trong lượt này.
     - Thay đổi cần người dùng duyệt (auth, billing, migration phá dữ liệu, commit/push/release, file rule/hook): CHỜ DUYỆT.
     - Thiếu bất kỳ điều kiện nào ở trên: CHƯA XONG.
   - Dòng 2: người dùng nhận được gì.
   - Dòng 3: loại lượt · exit code cổng (hoặc "không áp dụng") · đường dẫn log oracle · đường dẫn ảnh và serial (hoặc "không áp dụng").
   Cấm viết XONG, PASS, đã fix, đã xong khi chưa đủ điều kiện của loại đó.
