# Retro lịch sử agent — 2026-10-26

## Dữ liệu
- corrections.jsonl: 524 bản ghi (claude 471, antigravity 53), 149 phiên, 2026-08-12 → 2026-10-26.
- signals: 4197 file claude / 9369 tin nhắn người dùng; 502 file AGY / 1469 tin nhắn. tool_errors 5353, hook_blocks 4691.
- Lần sửa thật: 99. False positive: 425 = 397 lọc tự động (task-notification 282, tóm tắt nối phiên 99, bash-input/stdout/artifact) + 28 lọc tay. Tóm tắt nối phiên chỉ dùng làm bằng chứng phụ.

## Cụm (số lần / phiên / ngày / phân loại)
| Cụm | n | phiên | ngày | phân loại |
|---|---|---|---|---|
| A bịa số liệu/tính năng/thư viện trong tài liệu | 25 | 17 | 08-27→10-19 | NEW (mức cao) |
| B báo fix nhưng vẫn lỗi | 15 | 11 | 08-14→10-17 | RECURRING (AUTO-05, GeelyEx2 086/132) |
| G gate chậm/chạy lặp | 11 | 11 | 09-29→10-26 | RECURRING (aw 017/018/051/066) |
| C hiểu sai yêu cầu → revert | 9 | 9 | 08-12→10-13 | NEW |
| E hỏi/chờ duyệt/đẩy việc | 8 | 8 | 09-25→10-13 | RECURRING (GeelyEx2 041) |
| H chờ khoá phiên/worktree | 5 | 4 | 09-26→10-15 | NEW (luật devkit) |
| D data giả/cũ khi đo | 4 | 3 | 08-13→10-08 | NEW |
| F quên quyết định | 3 | 3 | 09-29→10-05 | NEW |
| J báo cáo tiến độ không rõ | 3 | 3 | 09-30→10-03 | NEW |
| I quá tải máy vì board | 4 | 2 | 10-21→10-26 | NEW |
| K văn giọng AI | 2 | 2 | 10-16 | NEW |
| L worktree/branch rác | 2 | 2 | 10-13→10-20 | RECURRING (GeelyEx2 156, aw 047) |
| M hạ chất lượng game/asset | 2 (+1 tóm tắt) | 2 | 10-10→10-12 | NEW |
| N phá huỷ (xoá trunk) | 2 | 2 | — | COVERED (chặn dangerous-git) |

Lần sửa lẻ, không thành bài học: #136, #216, #483, #83.

Tổng: NEW 9, RECURRING 4, COVERED 1. Thêm 3 bài học NEW từ signals (sleep/Monitor, git trong worktree cô lập, macOS sed/timeout).

## Câu nguyên văn tiêu biểu
- A: "là mày đang bịa à?"; "check kỹ lại AndroidUtilCode đâu có ?"
- B: "mày chắc chưa bug này đã báo 1 lần mà mày fix h vẫn bị lại á"
- C: "revert lại cũ bổ sung chứ ko phải thay thế bị mất 2 cái cũ rồi tổng 4 cái mới đúng"
- E: "chỉ hỏi khi xoá dữ liệu quan trọng, đụng secrets/billing thôi còn lại tự làm hết đi"
- G: "moá đổi có vài file doc mà chạy 30 phút chưa xong"
- H: "tôi đã fix lại là ko giữ main mà sao giờ vẫn bị giữ?"

## Signals (thói quen agent)
| Số lần | Tín hiệu |
|---|---|
| 1863 | trunk-mode chặn |
| 1040 | hook thiếu file |
| 353 | worktree-isolation từ chối git phức hợp |
| 227 | một thư mục một phiên |
| 225 | Monitor thiếu description |
| 220 | sleep rồi poll |
| 181 | auto-mode classifier (nhiễu) |
| 159 | rm -rf |
| 132 | PRE-CODE gate (đang hiệu quả) |
| 126 | AGY view_file (nhiễu) |
| 85 | No such tool |
| 147 | permission/deny |
| 72 | deny_dir |
| 39 | pm_order |
| 26 | BSD sed / timeout |
| 26 | guard_secrets |
| 15 | dangerous-git |
| 12 | push main |

## File kết quả
- new_lessons.json: 15 bài học tiếng Việt, nhập bằng `instincts.py add --from-json`.
- enforce.md: đề xuất cưỡng chế.
- promote.md: audit trùng lặp/cũ.

## Lưu ý
- Bản ghi Antigravity không có trường project. Các cụm A/E/K chủ yếu đến từ Antigravity, nơi hook devkit không chạy.
- Slug FinOS-SDK không xác định chắc đường dẫn, nên không gán bài học nào cho slug này.
