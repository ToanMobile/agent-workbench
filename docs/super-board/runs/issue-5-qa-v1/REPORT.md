# QA issue #5 — v1 (PR #36, head Builder `2821feb`)

Đường dẫn `$TMP` / `$SCRATCH` trong log là thư mục tạm của lần chạy; đã thay để log không lộ đường dẫn máy.

## Kết quả theo AC

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 `git push origin main` qua push gate khi worktree đã pass gate exit 0 | ✅ | `ac1-real-flow-probe.txt`: DevKit cài symlink-mode, `worktree add --session` (đúng lệnh hook WorktreeCreate chạy), gate `--full` trong worktree, `worktree finish` gỡ worktree, rồi hook `block-dangerous-git.sh` nhận `git push origin main` → exit 0 (cả gate trên tree dirty lẫn `--diff main`). Cùng probe trên DevKit của base `261ed3d` → hook exit 2 (`ac1-real-flow-probe-BASE.txt`) |
| AC2 test tự động mô phỏng merge từ worktree và xác nhận push gate pass | ✅ | `test_push_gate_linked_worktree.txt`: 19 dòng ✔ (L1–L17, L3b, L17 control), exit 0. Trên base: L1, L7, L9, L11 ĐỎ (`test_push_gate_linked_worktree-BASE.txt`) |

## Ledger AC → test

| AC | unit / CLI `push_gate.py` | e2e (hook + luồng thật) |
|---|---|---|
| AC1 | L1, L7, L9, L11 (`tests/gates/test_push_gate_linked_worktree.sh`) | probe `ac1_real_flow.sh.txt` (không commit vào suite) |
| AC2 | L1 (merge ff), L7 (`worktree finish`), L11 (`automerge --keep` rồi `remove`) | n/a: AC2 chính là test tự động |

## Kiểm edge case

- Ranh giới biên nhận: exit ≠ 0 → **gap High, đã viết L17** (xem dưới); không có biên nhận → L16; biên nhận giả → L4; biên nhận cũ của main → L9; `carried_from` sai project → L13.
- Lịch sử: code đổi sau gate → L3; commit đã gate bị viết lại → L3b; commit chưa gate trên main → L2, L8; sửa chưa commit rồi main đảo lại → L10, L15.
- Lỗi: worktree mất thư mục / không ma trận → L5, L6; một worktree ném lỗi không chặn worktree khác → L14.
- Tag push qua remote của worktree → L12.
- Số lượng: repo thật có 9 work tree, main không có biên nhận (trường hợp xấu nhất, xét mọi worktree): 0,55–0,58 s mỗi lần `push_gate.py` (base 0,15–0,16 s), xa ngưỡng timeout 30 s của hook (`perf-real-repo.txt`). Đây là cận trên, không phải một khẳng định hiệu năng (các lần chạy không xen kẽ AB/BA).

## Test the tests — mutant sống sót

Bỏ `receipt.get("exit") != 0` khỏi điều kiện trong `_own_check` (M1): biên nhận exit 2 (gate giữ cho lần UNVERIFIED hoặc partial, cùng fingerprint và head) của linked worktree bảo lãnh được push từ main, mà cả 9 test push_gate (kể cả 17 ca của Builder) vẫn xanh. Dòng này dùng chung với đường của chính main, nên mutant này đã sống từ trước PR.

L17 (thêm vào `test_push_gate_linked_worktree.sh`): xanh trên nhánh → ĐỎ dưới M1 (chỉ L17 hỏng) → xanh sau khi khôi phục, `push_gate.py` không đổi so với HEAD (`l17-mutation.txt`). Mutant không vào commit nào.

## Gap chưa viết (Medium, không chặn)

- Một lần gate FAIL mới hơn ở worktree anh em trên cùng nội dung chưa thu hồi biên nhận PASS cũ hơn (`ponytail:` trong `check()`); cần ghi fingerprint vào `runs.jsonl`, tức đổi code app.
- AC1 ở tầng hook với DevKit symlink-mode và `worktree add --session` chỉ có probe, chưa thành test trong suite (AC1 đã có test tầng CLI).

## File trong thư mục

`ac1_real_flow.sh.txt`, `exit2_receipt.sh.txt`, `mutate.py.txt`: script probe của QA (đuôi `.txt` để không bị tính là test). Các file `.txt` còn lại là output.
