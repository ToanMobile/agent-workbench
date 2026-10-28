# QA #526 · v1 · PR #544

Cơ sở: nhánh issue-526-shell-norm-ansi-quote đã merge origin/main (726d777b).

| AC | Kết quả | Bằng chứng |
|---|---|---|
| git viết bằng hex trong dollar-quote bị chặn cùng mã lệnh trần | ✅ | `check 2 git` x4 (hex, octal, unicode, hex giữa tên), đối chứng `status` rc 0 |
| rm viết bằng hex trong dollar-quote bị chặn cùng mã lệnh trần | ✅ | `check 2 hw` x3, đối chứng `rm -f nothing.tmp` rc 0 |
| Test chỉ đưa stdin JSON cho hook | ✅ | hàng mới dùng `check` (stdin JSON), không thực thi lệnh |

Lệnh: `bash universal-agent-devkit/tests/gates/test_guard_shell_norm.sh` → ALL PASS.
Gate impacted: `post-fix-gate.py --run-tests --brief` → PASS, 3/3 hồi quy.

Thăm dò thêm `ansi_c_to_single`: backslash kép trước x67 giữ nguyên; `\xZZ` giữ nguyên; `\x27` thành `'\''`; dollar-quote chưa đóng giữ nguyên.
Khoảng trống Low (không chặn merge): `\x00git` trong dollar-quote, bash cắt tại NUL (từ rỗng), code trả `git` → chặn chặt hơn bash, an toàn.
