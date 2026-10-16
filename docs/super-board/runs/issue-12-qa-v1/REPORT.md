# QA issue #12 — v1 (PR #37, head Builder `15ed99f`)

Kết luận: **❌ Fail** — AC1 đạt; AC2 còn một ca mất commit chưa merge (F2) cần sửa code app.
Đường dẫn `$TMP` trong log là thư mục tạm của lần chạy; đã thay để log không lộ đường dẫn máy.
Không có ảnh chụp: thay đổi chỉ ở script CLI (`worktree.py`, `worktree_sandbox.py`), không có giao diện.

## Kết quả theo AC

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 `worktree gc` không xoá worktree còn file chưa commit | ✅ | `head-test_worktree_gc.txt` exit 0; trên code gốc `origin/main` 3 ca ĐỎ (`main-orphan-copy`, `main-orphan-oldblob` bị xoá — `base-test_worktree_gc.txt`). Ca QA thêm `main-orphan-empty` (file rỗng mới, Context a của ticket): XANH trên head, ĐỎ trên gốc (`qa-head-…`, `qa-base-test_worktree_gc.txt`) |
| AC2 sandbox còn commit chưa merge vào main thì từ chối dọn và cảnh báo | ❌ | Ca nhánh (`ahead_sb`) và HEAD tách rời (`det_sb`) đạt: `head-test_worktree_sandbox.txt` exit 0, trên gốc 2 ca ĐỎ. **2 ca hỏng, mất commit** (cả hai có sẵn từ trước PR, code gốc cũng hỏng y vậy — `f2-probe-base.txt`): **F2** commit làm trên HEAD tách rời của sandbox rồi `git checkout sandbox/<x>` → `cleanup` xoá thư mục + nhánh, không cảnh báo, commit unreachable (`f2-probe-head.txt`); **SW6** main checkout đang `checkout --detach sandbox/<x>` → `cleanup` coi là đã merge (so với HEAD của checkout chính, không so với `main`) → xoá; sau `git checkout main` commit không còn ref nào (`sw6-probe-head.txt`) |

## Ledger AC → test

| AC | unit / CLI (bash, repo git thật) | e2e |
|---|---|---|
| AC1 | `test_worktree_gc.sh`: `main-orphan-copy`, `main-orphan-oldblob`, `main-orphan-unique`, `main-orphan-moved` (không xoá oan); QA thêm `main-orphan-trackedcopy`, `main-orphan-movedcopy`, `main-orphan-empty` | n/a: CLI không có giao diện |
| AC2 | `test_worktree_sandbox.sh`: `ahead_sb`, `det_sb`; F2, SW6: none (code hỏng, xem trên) | n/a |

Ledger lập bởi một sub-agent chỉ-đọc chỉ được cho AC + diff (không đọc mô tả của Builder), theo super-qa cho thay đổi chống mất dữ liệu.

## Test the tests — đột biến

12 đột biến chạy trên bản copy (sub-agent): 4 bị giết, 1 tương đương, 7 sống. Hai đột biến sống ở hàm kiểm chính của gc xoá mất việc:

- **G2** `(sha, rel) not in more` → chỉ so blob trong `more`: bản copy của một file mà main dời đi sau đó bị xoá. QA viết `main-orphan-movedcopy`.
- **G5** cặp → `not (sha in blobs and rel in tracked)`: file tracked bị ghi đè bằng nội dung file khác bị xoá. QA viết `main-orphan-trackedcopy`.

`qa-tests-mutants.txt`: head + test QA XANH; G2 → ĐỎ đúng `main-orphan-movedcopy`; G5 → ĐỎ `main-orphan-trackedcopy`; code gốc → ĐỎ 7 ca; `worktree.py` khôi phục = HEAD (0 dòng khác). Đột biến không vào commit nào (`mutate.py.txt`).

## Gap High cần đổi code app (→ Fail, trả Builder)

1. **F2** — witness `f2_probe.sh.txt`: `create f2_sb`; trong sandbox `git checkout --detach`, commit `f2.txt`, `git checkout sandbox/f2_sb`; `cleanup --name f2_sb`. Kỳ vọng: giữ thư mục + nhánh, in "chưa merge". Thực tế: xoá hết, commit unreachable. Gợi ý: tái dùng `_reflog_only()` ở `scripts/git/worktree.py:1034` (đúng ca "commit made detached and then `checkout <branch>`" mà `worktree remove` đã chặn). Rung: CLI bash, `test_worktree_sandbox.sh`.
2. **SW6** — witness `sw6_probe.sh.txt`: sandbox có 1 commit; ở checkout chính `git checkout --detach sandbox/sb`; `cleanup --name sb`. Kỳ vọng: từ chối (commit chưa vào `main`). Thực tế: xoá thư mục + nhánh. Nguyên nhân: `sandbox_unmerged_commits` (`worktree_sandbox.py:286`) đếm `HEAD..<rev>` theo HEAD của checkout chính, và `git branch -d` cũng xét HEAD. Gợi ý: so với nhánh trunk (`main`) thay vì `HEAD`, hoặc coi HEAD tách rời của checkout chính là không biết → giữ. Rung: CLI bash, `test_worktree_sandbox.sh`.

## Test gaps (chưa viết — Medium/Low, không chặn)

- Medium S3: `rev-list` lỗi (checkout chính `git switch --orphan unborn`) → hiện giữ đúng ("không đếm được … rc=128"), nhưng không test nào ghim; đột biến `continue` thay `return` xoá mất commit.
- Medium S2: nhánh có commit nhưng HEAD sandbox lùi về `HEAD~1` → hiện từ chối đúng; không test ghim (chỉ `branch -d` cứu nhánh dưới đột biến). Cũng chưa test: thư mục đã mất mà nhánh còn commit.
- Medium S4/SW5: `cleanup --all` / `merge-winner --clean-others` với sandbox thua còn commit chưa có test; sandbox HEAD tách rời không nằm trong `list_sandboxes` (`worktree_sandbox.py:200` chỉ nhận mục có dòng `branch`) nên `--all` bỏ qua nó mà không cảnh báo.
- Medium S6, G6: nhánh fail-closed khi không đọc được HEAD sandbox / `hash-object` lỗi (`chmod 000`) chưa test (G6 có từ trước PR).
- Low: `cleanup` vẫn in "✅ Đã dọn dẹp hoàn tất" và exit 0 sau khi từ chối; đường dẫn có ký tự xuống dòng làm `rev-list` cắt sai tên (byte vẫn trong git); Test 8 của sandbox in lỗi `mv` thừa (có từ trước).

## File trong thư mục

`f2_probe.sh.txt`, `sw6_probe.sh.txt`, `mutate.py.txt`: script probe của QA (đuôi `.txt` để không bị tính là test). `gate-full.txt`: gate full trên commit QA. Các file `.txt` còn lại là output.
