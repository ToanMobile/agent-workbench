# QA issue #3 — v2 (PR #34, bản gộp `8dd2280` = `ccb9bdc` + `origin/main` `261ed3d`)

Không có ảnh chụp: thay đổi không có giao diện (script Python + test shell). Bằng chứng là log test trong thư mục này.

## Kết quả theo AC

| AC | Test | Code nhánh | Code `origin/main` (đột biến) |
|---|---|---|---|
| AC1 nightly chạy trên repo trunk mode | `test_nightly.sh` ca (b) `test_nightly.sh:194-197` | XANH — `ac1-test_nightly.txt` | ĐỎ — `trunk: skip: trunk mode: main chỉ nhận merge` (`mutant-main-test_nightly.txt`) |
| AC2 red_proof revert không lưu diff vào `patch` | `test_red_proof.sh:122-124` | XANH — `ac2-test_red_proof.txt` | ĐỎ — `revert mode leaked a patch field: .agents/local/red-patches/...patch` (`mutant-main-test_red_proof.txt`) |

AC1 đi qua đường `nightly.py run <path>` (run có tên — chỉ đường này gọi `checkout_busy`); `run` trần của LaunchAgent không gọi `checkout_busy` nên vốn không bị chặn.

## Kiểm khoảng trống test

| Mức | Khoảng trống | Xử lý |
|---|---|---|
| High | Đột biến "main trunk → `return None` trước kiểm lock" (đúng câu chữ issue) sống sót: chưa ca nào ghim main trunk mà có phiên sống giữ lock | Viết ca (b2) `test_nightly.sh:198-203`: ĐỎ với đột biến (`gap-trunkheld-RED-mutant.txt`), XANH với code nhánh (`gap-trunkheld-GREEN.txt`) |
| Medium | Đột biến bỏ `out["patch"]` ở chế độ `--patch` (`red_proof.py:753-754`) sống sót; `regression_checklist.py:1325,1344` đọc trường này | Không viết — dòng đó không thuộc diff |
| Medium | Ở trunk mode main không ai giữ lock, nên `checkout_busy` không thấy phiên đang fast-forward main trong lúc run có tên chạy; run ghi checklist lên main (bản sổ đang dirty có thể giữ automerge) | Không viết — đúng hành vi issue yêu cầu |

## Ghi chú

- Issue nhắc cờ `--detached` cho `red_proof.py`: script không có cờ này (chỉ `--wait --heavy --pending --bug --fix-commit --patch`); nó luôn chứng minh trong worktree detached tạm (`red_proof.py:310-312`), nên không cần thêm.
- Head PR đổi từ `ccb9bdc` sang commit bằng chứng QA: gồm merge `origin/main` `8dd2280` của builder vòng 2 (trước đây chỉ ở local), báo cáo v1 và v2.
