# Audit trùng lặp / cũ — retro 2026-10-26 (415 mục đã đọc)

## Boilerplate chép khắp nơi → gỡ khỏi file project
- INSTINCT-001…005 và mục placeholder XXX có trong cả 8 file (4 project + android, automotive, game, universal). 006–010 có trong cả 4 file project. Chỉ giữ ở universal hoặc profile phù hợp.
  - 002/005 không hợp agent-workbench.
  - 010 (DB migration) không hợp game Unity.
- humans-vs-ufos.md chỉ có mục mẫu, chưa có bài học thật.

## Trùng với profile → xoá bản project, giữ bản profile
- GeelyEx2 V01–V04 ↔ voice-assistant VOICE-06/07/08/04.
- GeelyEx2 ↔ automotive: 022↔AUTO-02, 114↔AUTO-01, 025↔AUTO-08, 026↔AUTO-04, 037↔AUTO-10, 015↔AUTO-09, 019↔AUTO-11.
- goods-triple ↔ game: 016↔G08, 030↔G09, 013↔G13, 015↔G14, 011/042↔G12, 036↔G07, 024↔G06 (trùng một phần).

## Lặp ở nhiều project → nâng lên universal hoặc profile mới `antigravity-pm`
- Quy trình antigravity-pm: goods 012/014/022/025/026/027/028, GeelyEx2 048/052/154/155 → profile mới antigravity-pm.
- Commit không có message: GeelyEx2 065 ↔ goods 028.
- Agent dùng git restore/stash trong cây dùng chung: GeelyEx2 035/155 ↔ goods 013.
- Lời agent tự khai so với bằng chứng XML: goods 024 ↔ GeelyEx2 138/154.
- zsh: GeelyEx2 095/100 ↔ aw-035.
- Hỏi lại / quên quyết định: GeelyEx2 041 → universal (retro cũng thấy ở OfficeReader và Antigravity).

## Đặt sai chỗ
- agent-workbench 023 (Swift) → ios.
- agent-workbench 024 (Android StateFlow) → android.
- agent-workbench 060 (GLB cache) → web.

## Cũ / cần kiểm lại
- 119 mục ghi "nhập 2026-09-23, chưa chạy lại" (GeelyEx2 93, goods 26) → chạy lại check, hoặc gắn nhãn chưa xác minh.
- Có thể chỉ gặp một lần: GeelyEx2 103 (Go embed), 104 (DMG mount), aw-043 (hostname Mac).
