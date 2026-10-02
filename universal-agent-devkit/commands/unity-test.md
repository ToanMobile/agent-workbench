# /unity-test

Chạy bộ kiểm thử tự động của Unity (EditMode / PlayMode) ở chế độ headless (batchmode không mở GUI).

## Cách dùng:
```bash
python3 .agents/devkit/scripts/run_unity_tests.py [--platform editmode|playmode] [--project .] [--output reports/unity-test-results.xml]
```

## Luồng thực thi:
1. Tự động phát hiện phiên bản Unity Editor phù hợp từ `ProjectSettings/ProjectVersion.txt`.
2. Chạy test trong môi trường cách ly (tự động khóa Editor lock, restore PlayerPrefs).
3. Đọc file XML kết quả, in tóm tắt số ca Pass/Fail và stack trace chi tiết nếu có lỗi.
4. Trả exit code: `0` khi PASS 100%, `1` khi có test FAIL, `2` khi lỗi biên dịch/không tìm thấy Editor.
