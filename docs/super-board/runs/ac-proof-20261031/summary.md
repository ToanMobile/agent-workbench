# Chứng minh AC còn mở của #699, #716 (và trạng thái #685) — 31/10/2026

Bản sửa của cả ba thẻ đã vào main. PR này chỉ ghi bằng chứng cho các dòng AC mà merge gate để lại ở `ac-open`.

## #699 · fixture test_postfix_gate dùng một mốc now (PR #703, merged 28017e9c, 30/10 17:23)
- **AC1 · đỏ→xanh có trễ 2 s.** `POSTFIX_FIXTURE_DELAY_S=2`:
  - Trước sửa (test của main 75ba0426) exit 1, có 3 FAILED: ca "another session's Edit", bản sub-agent và json. Exit 2 thay cho 0.
  - Sau sửa (head 3fbd7775) exit 0, 269 ✔.
  - Không trễ: exit 0. Cửa sổ 1,5 s của gate không đổi.
  - Phiên điều phối tự chạy qua khoá (`work-1644/rg703.sh`), ghi ở body PR #703 và handoff 30/10 17:04.
- **AC2 · các ca khác giữ nguyên kỳ vọng.** Diff của PR #703 không chạm dòng `check`/`other_case`/`expect` nào. Cả file exit 0, có trễ và không trễ.
- **AC3 · Antigravity duyệt chéo test sửa.**
  - Audit T0160 pass, `auditedHead 3fbd7775867554c17759dede515c4e69b4c4aa8b` (sau gộp main 75ba0426).
  - Comment duyệt trên PR #703 có `approved-head:3fbd7775…`, `approved-by … T0160 …`, và `edited-tests` gồm `universal-agent-devkit/tests/gates/test_postfix_gate.sh`, sha256 `a3e7080a952a4923b371f59a43835bd3e1cd1708c80de0cdf68a6b4a626b462c`.
  - Đồng thuận Claude + Antigravity.
- **AC4 · gate scoped exit 0.**
  - Gate @3fbd7775: exit 0, 3/3, fp cây = head = `8fef0e18d3a29fe03d6a354d` (17:16).
  - Merge gate verify xanh trên main, merged `28017e9c` (17:23).

Lý do thẻ còn `ac-open`: body PR #703 ghi dòng ↳ của AC3/AC4 là "not verified yet" lúc mở PR, vì audit và gate chạy sau đó. Các dòng trên là bằng chứng đã có thật.

## #716 · lane lock 2 slot theo load (PR #717, merged 049f313b, 30/10 22:38)
- **AC1–AC4, AC6:** đã chứng minh trong body PR #717. Test `universal-agent-devkit/tests/gates/test_lane_lock.sh`:
  - khoá mkdir cũ đỏ 5/8 ca (1, 3, 4, 7, 8);
  - `lane_lock.py` xanh 8/8, chạy 2 lượt;
  - gate scoped exit 0, 3/3, fp `7102e52fc1292ab025e09132`;
  - Antigravity T0169 pass @f0c10a06.
- **AC5 · đo thời gian chờ slot trước/sau** (dòng còn mở). Đo A/B lúc 22:41 30/10 (`work-1644/ab716.sh`), load1 9–11, hai việc nặng giống nhau xin khoá cùng lúc:

  | | Khoá mkdir cũ (trước) | `lane_lock.py` (sau) |
  |---|---|---|
  | Việc thứ hai chờ | 14 s | 0 s ("slot 2/2, cho phép 2") |
  | Cả cặp xong sau | 26 s | 11 s |

  Ca thật trước đó: merge gate #707 chờ khoá cũ 4 phút 45 giây (20:16:05 → 20:20:50). Sau khi chuyển (dòng `[lock] … giữ khoá` trong `work-1644/*.out`):
  - Các lượt nặng ở tải < 12 đều ghi "chờ 0 s": gp712 (load 9,3), commit712b (5,7), gp712b (4,5), commitac và gpac (5,3).
  - commitac và gpac vào "slot 2/2" trong lúc slot 1 đang có việc khác, tức 2 việc nặng chạy song song.
  - rg719 xin khoá lúc 05:38 31/10 khi tải ≥ 12 (chỉ 1 slot, đang bị việc #720 giữ) nên chờ 55 s, tới khi tải còn 10,7 thì vào slot 2/2. Đúng luật 1 slot khi tải cao.
  Comment trên thẻ: https://github.com/ToanMobile/agent-workbench/issues/716#issuecomment-6526852417

## #685 · CHƯA đóng
- AC "agent-kit test PASS trên origin/main" và "gate_full.py run kế tiếp XANH, last_full_green_sha trỏ tới main mới" cần một đêm gate-full xanh. Đêm 31/10 00:00 đỏ ở `test_game_blender_default.sh` (#719) và `test_hook_contract_watchdog_env.sh` (#720, chập chờn do tải). Hai lỗi này đang sửa trong PR gộp #719/#720/#721.
- Điều kiện đóng: lượt gate-full đầu tiên XANH sau khi PR đó merge.
