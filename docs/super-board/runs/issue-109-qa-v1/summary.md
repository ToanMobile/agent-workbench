# QA #109 v1 — preflight: tiêu đề AC có hậu tố và "máy thật" phủ định

Lệnh: `bash tests/super-board/test_preflight_too_big.sh`
- Nhánh issue-109 (d3662ea9): exit 0, `PASS: preflight too-big`, Synthetic #908 proceed.
- Bản preflight của origin/main (mutant, giữ fixture 908): exit 1, `✖ Synthetic #908: muốn proceed/clean, được hold/too-big` → ĐỎ.
- Gate: `post-fix-gate.py --run-tests --brief --diff origin/main --auto-approve-tests` → exit 0 (hồi quy 3/3).

| AC | Kết quả |
|---|---|
| Tiêu đề `## Acceptance Criteria (draft)` bị giữ như tiêu đề chuẩn | ✅ Synthetic #906 hold/too-big |
| "không cần máy thật" không bị giữ chỉ vì tín hiệu máy thật | ✅ Synthetic #908 proceed/clean |
| test_preflight_too_big.sh xanh | ✅ exit 0 |

Khoảng trống (Low, không viết): dòng trộn "không cần X, nhưng cần máy thật" bị bỏ cả dòng (phủ định theo dòng).
