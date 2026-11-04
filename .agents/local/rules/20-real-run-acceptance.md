# Nghiệm Thu Bằng Lượt Chạy Thật (Real-Run Acceptance)

Lệnh chủ repo (04/11/2026, nguyên văn): "nghiệm thu phải được chạy thật chứ ko phải dùng test giả sau đó pass test giả là pass".
Lý do đo được: tuần 25/10–04/11 hơn 10 PR tối ưu gate báo "nhanh hơn" bằng replay/bench/fixture, không PR nào đo lại sau merge; p90 merge gate thật lại tăng 2361 s → 2696 s (#983). INSTINCT-106: luồng qua PM/grok xanh trên fixture nhưng hỏng khi chạy thật.

## 1. Luật (BẤT BIẾN)
- **Test fixture/giả chỉ là oracle ĐỎ→XANH, không bao giờ là nghiệm thu**: XONG, PASS, "đã fix", "nhanh hơn", "hết lỗi" cần thêm bằng chứng từ một lượt chạy THẬT của đúng luồng đã sửa, trên repo thật, bằng lệnh thật mà người dùng/board dùng (gate thật, merge gate thật, hook thật trong phiên, PM/grok thật, app thật trên thiết bị).
- **Dán nguyên văn dòng output thật làm bằng chứng**: lệnh đã chạy, exit code, dòng số đo của chính công cụ (vd `per_test_cache: reuse=N ran=M`, `merge gate (.merge-scratch-*): n p90`, receipt merge gate), thời điểm chạy. Không dán thì báo CHƯA XONG.
- **Việc tối ưu tốc độ nghiệm thu bằng số đo thật trước/sau merge**: chỉ số `gate_speed_report.py` (p90 merge gate thật gồm chờ khoá, cửa sổ 7 ngày) hoặc số phút của lượt chạy thật trên cùng kịch bản trước/sau; replay, bench, mô hình hay fixture không được tính là kết quả. Cửa sổ sau merge không tốt hơn thì việc chưa xong, kể cả khi mọi test xanh.
- **Sửa cache / khoá / bỏ qua test phải có thêm lượt chạy thật chứng minh không PASS sai**: đổi một file mà test phụ thuộc thì test đó phải chạy lại trong lượt thật.

## 2. Khi chưa chạy thật được
- Không có thiết bị, endpoint chết, chưa merge nên chưa có cửa sổ sau: ghi rõ "chưa nghiệm thu thật — <lý do>, sẽ đo <lệnh> lúc <khi nào>" trong báo cáo và để thẻ ở Review, không Done. Không gọi kết quả fixture là "đã chạy được".
