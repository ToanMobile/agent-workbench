# Audit DevKit 2026-10-09 — plan chạy tiếp ở local (macOS)

## Trạng thái khi bàn giao

| Nơi | Commit | Nội dung | Đã kiểm chứng |
|---|---|---|---|
| `main` | `03295d9` | Đợt 1 + đợt 2 | 158/158 test DevKit bị ảnh hưởng pass (Linux cloud) |
| nhánh `claude/laughing-dijkstra-gc7xjk` | commit "WIP round 3" (ngay sau `03295d9`) | Đợt 3 (danh sách dưới) | Từng test mới RED→GREEN; **chưa chạy lại toàn bộ test DevKit**, **chưa chạy gate `--full`** |

Gate `--full` chưa từng ra exit 0 trên cloud. 2 suite fail là do môi trường: `mcp-servers/antigravity-pm-mcp` chưa có `node_modules`, và clone trên cloud chưa cài kit nên `agent-kit health` FAIL. Trên Mac của bạn không gặp hai lỗi này.

### Đợt 3 (nằm trên nhánh, chưa vào `main`)
- `bin/post-fix-gate.py`: khi xét test đã sửa trong khoảng `--since`, dòng `Test-approved-by:` chỉ được tính khi là trailer thật **và** có biên bản audit pass của antigravity-pm (dùng chung `push_gate.approved`). Test: `tests/gates/test_gate_since_test_edit.sh` (thêm ca "dòng tự viết vẫn bị gắn cờ").
- `bin/push_gate.py`: không còn crash với tên file hoặc tag không phải UTF-8. Test: `tests/gates/test_push_gate_non_utf8.sh`.
- `bin/tree_fp.py`: không còn crash khi thư mục repo có tên không phải UTF-8 (cùng file test trên).
- `hooks/hardware_safety_gate.sh`:
  - `rm -r` (không có `-f`) trên thư mục project, thư mục cha, `~`, `/` hoặc phân vùng hệ thống giờ bị chặn; `rm -r src` vẫn được phép.
  - `find -name '*' -delete` (và `*/*`, `./*`, `.*`) được coi như không có bộ lọc.
  - Test: `tests/gates/test_hardware_rm_unforced.sh`, `tests/gates/test_hardware_find_match_all.sh`.
- `hooks/block-dangerous-git.sh`: shell nhận văn bản từ `<(…)` (ví dụ `bash <(curl …)`, `bash < <(…)`) bị chặn như pipe văn bản sinh ra vào shell. Test: `tests/gates/test_git_guard_process_subst.sh`.
- `tests/lib/test_durations.txt`: thêm 4 test mới.

## Bước 1 — kiểm chứng đợt 3 trên Mac
```bash
cd <agent-workbench>
git fetch origin && git switch claude/laughing-dijkstra-gc7xjk && git pull --ff-only
cd universal-agent-devkit
for t in tests/gates/test_gate_since_test_edit.sh tests/gates/test_push_gate_non_utf8.sh \
         tests/gates/test_hardware_rm_unforced.sh tests/gates/test_hardware_find_match_all.sh \
         tests/gates/test_git_guard_process_subst.sh hooks/tests/hook_contract_test.sh; do
  bash "$t" >/tmp/t.log 2>&1 && echo "PASS $t" || { echo "FAIL $t"; tail -20 /tmp/t.log; }
done
bash tests/run_impacted.sh          # mọi test bị ảnh hưởng, khoảng 8 phút
cd .. && python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief   # phải ra exit 0
```
Lần chạy gate này cũng tự bỏ dòng rác `REG-01 echo FULL_TEST_EXECUTED` khỏi checklist, nhờ bản sửa `sync_from_matrix` ở đợt 2.

## Bước 2 — đưa vào `main`
```bash
git switch main && git pull --ff-only && git merge --ff-only claude/laughing-dijkstra-gc7xjk && git push origin main
```

## Bước 3 — việc còn lại (chưa làm)
1. **RED-proof cho 19 dòng bug cũ** trong `.agents/CHECKLIST.md` (đang INCONCLUSIVE hoặc chưa chạy). Lý do: các dòng này chỉ được liên kết với suite chung `REG-DK-ALL-01`.
   - Với mỗi bug: tìm commit sửa và test bảo vệ (CHANGELOG ghi "Guard: tests/…"), liên kết bug với đúng file test đó bằng `agent-kit bugs` (`bug-link`), rồi chạy RED-proof bằng công cụ của DevKit (`scripts/testing/red_proof.py`).
   - Không sửa JSON bằng tay: sửa tay sẽ kích hoạt cảnh báo rollback.
   - Clone trên cloud là clone nông nên không làm được; trên Mac có đủ lịch sử.
2. **Giới hạn đã biết của guard** (đều có ghi chú trong code, chưa chặn):
   - `eval "$(…)"`, `source <(…)`, `. <(…)`, `… | tee >(sh)`, `bash -c "$(…)"`.
   - `bash < file`, `bash script.sh` (không quét nội dung script).
   - `find` có bộ lọc `!` / `-o`.
   - `rm -r` (không `-f`) trên đích không phân giải được (`$VAR`, `cd` vào thư mục không rõ, `xargs` đọc đầu vào không đọc được).
3. **Chất lượng phụ:**
   - `comment_claim_guard` chưa quét docstring Python, chưa quét comment ở cuối dòng code.
   - Kiểm tra test bị đè với JS `it(...)` có thể gắn cờ nhầm khi cùng tiêu đề nằm trong hai `describe` khác nhau.
   - Script runner không có `set -e` vẫn có thể che một lỗi ở phía trước bằng một lệnh được nối thêm vào cuối. Có bắt buộc review mọi thay đổi runner hay không là quyết định chính sách.
   - `hooks/review_timing_guard.sh` vẫn truyền payload qua biến môi trường `RT_INPUT`.
   - Nhiều hook khác vẫn dò thư mục log theo `cwd` khi `CLAUDE_PROJECT_DIR` không được đặt. Claude Code luôn đặt biến này nên chỉ ảnh hưởng các harness khác.
4. **Hiệu năng còn lại:**
   - `churn_guard` không có đường tắt (khoảng 32 ms mỗi Edit).
   - `prompt_context` khoảng 150 ms mỗi prompt.
   - Gate khởi động khoảng 110 ms, vì 4800 dòng script được biên dịch lại mỗi lần chạy.
5. **Chưa kiểm chứng trên macOS:**
   - Đợt 2 và đợt 3 chỉ chạy trên Linux (bash 5.2). Bash 3.2 của macOS mới chỉ được kiểm bằng `bash -n` và đọc code (không dùng mảng kết hợp, `mapfile`, `${x,,}`).
   - Bước 1 là lần chạy thật đầu tiên trên macOS.
   - Gemini qua alias chưa kiểm (`includeDirectories` vẫn dùng đường dẫn thật).
   - Receipt `head_and_dirty` băm đích của symlink thay vì chính symlink (giả thuyết, chưa kiểm).
