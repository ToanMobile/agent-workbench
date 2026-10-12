# Thực hành kiểm thử JS/TS và mã sạch — tham chiếu nạp khi cần

Phạm vi: chỉ cho dự án JS/TS/Node (profile `web`, hoặc `backend` khi runtime là Node). Không áp dụng cho Android/Kotlin, iOS, automotive hay game (Unity/C#): các profile đó dùng test runner và quy ước riêng của profile.

Nguồn đã đọc (2026-10-12, qua WebFetch, số mục theo README của nguồn): `goldbergyoni/javascript-testing-best-practices`, `goldbergyoni/nodebestpractices` (mục 4), `ryanmcdermott/clean-code-javascript`. Bổ sung cho skill, không thay `RED → GREEN` trong `SKILL.md`. Rule ngắn: `profiles/web/rules/web-rules.md` §8. Mục "[DevKit]" là quy ước của kit.

## Cấu trúc một test
- Tên gồm đơn vị + kịch bản + kết quả mong đợi (JS-TBP 1.1, NBP 4.2); thân theo AAA (1.2); assertion khai báo (`expect`).
- Một khái niệm mỗi test (clean-code); [DevKit] không `if`/vòng lặp trong test; lồng `describe` tối thiểu 2 cấp để báo cáo đọc được (1.12).
- Black-box: chỉ kiểm hành vi công khai (1.4); ưu tiên stub/spy hơn mock (1.5); dữ liệu thực tế, không "foo" (1.6); chỉ đưa vào test dữ liệu ảnh hưởng kết quả (1.9).
- Mong đợi lỗi bằng assertion (`toThrow`, mã lỗi), không `try/catch` (1.10). Snapshot chỉ ngắn, inline (1.8).
- Test không phải code production: ngắn, phẳng, đọc lướt hiểu ngay (nguyên tắc 0).

## Chọn tầng test
- Backend: kiểm thử component/API (mô-đun thật, chỉ stub dịch vụ ngoài) cho ROI tốt nhất (2.2); thêm contract test theo consumer khi client/server khác repo (2.3); test middleware riêng (2.4); đừng bó vào kim tự tháp unit (2.1).
- Frontend: tách UI khỏi logic (3.1); truy vấn theo label/test-id, không theo CSS class (3.2); render component thật, tránh shallow (3.3); rất ít E2E, một smoke test trên sitemap (3.7, 3.9); dùng lại login/token (3.8).
- Mỗi flow kiểm 5 kết quả: phản hồi, trạng thái lưu, lời gọi ra ngoài, thông điệp queue, tín hiệu quan sát (NBP 4.13, JS-TBP 2.12).

## Dữ liệu, cô lập, flaky
- Không fixture/seed toàn cục; mỗi test tự tạo dữ liệu của nó (2.7, NBP 4.5). Dọn sau toàn bộ test thay vì sau từng test để chạy song song và dễ debug (2.8). Port ngẫu nhiên khi dựng server test (NBP 4.12).
- HTTP ngoài bị chặn bằng interceptor — nock (JS-TBP 2.9; MSW là lựa chọn của bulletproof-react) — và có ca chậm, timeout, 5xx (2.11, NBP 4.10).
- Chờ điều kiện, không `sleep` (3.4); stub backend chậm/flaky (3.6). [DevKit] Test dùng sleep cố định, đồng hồ thật, mạng thật hoặc dữ liệu chung thay đổi được phải bị loại trừ trừ khi có lý do ghi rõ; test phải chạy đúng khi đảo thứ tự và song song.
- Khi ID/ngày giờ không đoán trước, assert theo schema (2.10).

## Đo hiệu quả
- Coverage khoảng 80% là đủ, 100% làm xao nhãng (JS-TBP 4.1; clean-code-javascript nói hướng 100% "tuỳ nhóm" — hai nguồn khác nhau, DevKit chọn coi coverage là sàn). Mutation testing cho biết test có bắt được lỗi cài thử (4.3). Linter cho test: cấm test không assert, `.only`, `.skip` (4.4). Chạy lint ở CI và ở máy local giống nhau (5.1, 5.2).
- Chaos/góc khuất cho Node: quá tải bộ nhớ, crash tiến trình, event loop bị chặn (2.6).

## Mã sạch khi viết test và code
- Hàm ≤ 2 tham số (nhiều hơn → options object), một việc, không cờ boolean, không mutate tham số (trả bản sao), không mở rộng built-in/global, xoá code chết, không comment-out, tên có nghĩa, magic number thành hằng.
- Lỗi: không bỏ qua `catch`, không bỏ qua promise reject; ưu tiên `async/await`.
- SOLID chỉ khi có lý do thay đổi thật; ưu tiên composition hơn kế thừa.

## Liên hệ paired oracle
- RED phải thất bại tại assertion/triệu chứng ở tầng thấp nhất tái hiện được lỗi; các thực hành trên là cách làm test đó bền (không flaky, không phụ thuộc thứ tự), không phải lý do bỏ RED.
