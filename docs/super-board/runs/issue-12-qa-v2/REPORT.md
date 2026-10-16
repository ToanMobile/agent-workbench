# QA issue #12 — v2 (PR #37, head Builder `2dedd2c`, rebuild 1)

Kết luận: **✅ Pass** — AC1 đạt (như v1, chạy lại xanh); AC2 đạt khi thư mục sandbox còn: hai lỗ v1 (F2, SW6) đã sửa, ĐỎ trên `6185d2e` → XANH trên `2dedd2c`.
Lỗ còn lại ngoài tầm sửa của PR (thư mục sandbox bị xoá tay + `git worktree prune` toàn repo, có từ trước, cả ở `red_proof.py`) → ticket #38, không chặn.
Không có ảnh chụp: thay đổi chỉ ở script CLI, không có giao diện. Đường dẫn máy trong log đã thay bằng `$TMP` / `$S` / `$WT`.

## Kết quả theo AC

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 `worktree gc` không xoá worktree còn file chưa commit | ✅ | `head-test_worktree_gc.txt` exit 0 (code `worktree.py` không đổi từ v1) |
| AC2 sandbox còn commit chưa merge thì từ chối dọn và cảnh báo | ✅ (thư mục còn) | `base6185-test_worktree_sandbox.txt`: 4 ca mới của Builder (`f2_sb`, `reset_sb`, `sw6_sb`, `mw_sb`) ĐỎ trên `6185d2e`; `head-test_worktree_sandbox.txt` exit 0. Probe v1 chạy lại (`probes-f2-sw6.txt`): F2 và SW6 DELETED trên `6185d2e` → KEPT trên head. Thư mục đã bị xoá tay: xem "Gap" bên dưới (#38) |

## Ledger AC → test (sub-agent chỉ-đọc, chỉ nhận AC + range + danh sách file)

| AC | CLI bash trên repo git thật | e2e |
|---|---|---|
| AC1 | `test_worktree_gc.sh` 7 ca orphan (unique / staged / detcommit / copy / oldblob / trackedcopy / empty) giữ + nêu tên | n/a: CLI |
| AC2 | `test_worktree_sandbox.sh`: `ahead_sb`, `det_sb`, `f2_sb`, `reset_sb`, `sw6_sb`, `mw_sb`; QA v2 thêm `mwl_lose` (`merge-winner --clean-others`), `rlg_sb` (reflog không đọc được), `unb_sb` (HEAD sandbox không đọc được) | n/a: CLI |

## Test the tests — 15 đột biến (`mutants-summary.txt`, `mutate.py.txt`)

Trên head chưa có test QA: 7 bị giết (M1, M2, M7, M8, Mc, Me, Mg), 2 tương đương về dữ liệu (M5, Mf), 6 sống (M3, M4, M6, Ma, Mb, Md).
Ba đột biến sống làm MẤT commit, QA viết test giết chúng (ĐỎ dưới đột biến, XANH trên head — `qa-new-tests-red.txt`; trên `origin/main` cả 3 ĐỎ):

- **M3** bỏ `if lost is None` (reflog không đọc được coi là sạch) → `rlg_sb`.
- **M6** `rev-parse HEAD` của sandbox lỗi trả None → `unb_sb` (`git switch --orphan` trong sandbox).
- **Ma** bỏ kiểm commit chưa merge khi `--all` / `--clean-others` → `mwl_lose`.

Đột biến không vào commit nào: chạy trên bản copy ở thư mục tạm (`red_new_tests.sh.txt`).

## Chặn thừa? (luồng bình thường vẫn tự dọn — `witnesses-head.txt`)

`commit` → `commit --amend` → `merge-winner`; merge tay ff / non-ff rồi `cleanup`; detach không commit; commit tách rời đã cherry-pick vào nhánh; commit nằm ở nhánh phụ còn giữ: đều dọn sạch, có 🎉. `merge-winner` khi checkout chính tách rời: giữ + "chưa dọn", không 🎉.

## Gap

**High cần đổi code app trong phạm vi PR: không có.**

**Medium — có từ trước, ticket #38 (không chặn):** thư mục sandbox bị `rm -rf` bằng tay khi commit của nó chỉ reflog HEAD trong admin dir giữ. `cleanup --name x` (head_sha None nên bỏ qua kiểm reflog), `cleanup --name y` của sandbox khác, và cả khi `cleanup` vừa in "giữ nguyên" (prune cuối hàm) đều `git worktree prune` toàn repo → commit unreachable (`gone-probe-head.txt` = `gone-probe-basemain.txt`, witness `dl_a`, `dl_a2`, `dl_b`, `dl_b2`). Không xếp High vì: (1) mọi witness cần xoá tay thư mục ngoài tool — không lệnh sandbox/DevKit nào để lại thư mục mất mà admin dir còn; (2) `red_proof.py:323` cũng prune toàn repo (chạy nền ở Stop), nên sửa riêng `cleanup` không bịt được lỗ; (3) y hệt trên `origin/main`.

## Test gaps (chưa viết — Medium/Low, không chặn)

- Medium: `reset --soft HEAD~1` + commit lại rồi `merge-winner` → sandbox luôn bị giữ (đúng AC2, nhưng là luồng hay gặp; xoá bằng `--force`).
- Medium: M4 — `worktree_sandbox.py` chạy tách khỏi `worktree.py` thì mọi `cleanup` từ chối; `commands/sandbox.md`, `skills/worktree-sandbox/SKILL.md` trỏ `scripts/worktree_sandbox.py` (không tồn tại; file thật ở `scripts/git/`).
- Low: Mb (Test 3 không kiểm 🎉), Md (không test "nhánh phụ giữ commit thì được dọn").
- Low: `rev-list` dùng tên trần `sandbox/x` → tag cùng tên che nhánh; `branch -d` cứu nhánh nhưng thư mục bị xoá, thông báo sai (`or_tag_shadows_branch`) — gộp vào #38.
- Low: `--all` bỏ qua sandbox HEAD tách rời (`list_sandboxes` chỉ nhận mục có `branch`); `cleanup` vẫn in "✅ Đã dọn dẹp hoàn tất" và exit 0 sau khi từ chối; Test 8 in lỗi `mv` thừa (có từ trước).

## File trong thư mục

`*.sh.txt`, `mutate.py.txt`: script probe/đột biến (đuôi `.txt` để không bị tính là test). `witness.sh.txt` + `witnesses-head.txt`: kịch bản và kết quả của sub-agent. `gate-full.txt`: gate full trên commit QA.
