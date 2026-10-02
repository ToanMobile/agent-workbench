# DevKit Testing, Proof & Oracle Runners

Bộ công cụ kiểm thử thực thi, thu thập bằng chứng và kiểm chứng Paired Executable Oracle:

- `capture_3d_proof.py`: Chụp ảnh nghiệm thu mô hình 3D Blender / baked sprites.
- `proof_phash.py`: So sánh perceptual hash (pHash) của ảnh chụp bằng chứng nghiệm thu.
- `red_proof.py`: Kiểm chứng Paired Executable Oracle (bắt buộc test ĐỎ trên mã nguồn lỗi).
- `run_unity_tests.py`: Chạy Unity NUnit tests độc lập không phụ thuộc UI.
- `stale_rerun.py`: Chạy lại các ca kiểm thử bị ảnh hưởng hoặc quá hạn.
