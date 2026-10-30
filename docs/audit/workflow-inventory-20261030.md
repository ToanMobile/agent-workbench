# Kiểm kê workflow DevKit + super-board — 2026-10-30

Đọc code tại main `46b553fa` (chỉ đọc, chưa chạy gate/test). `file:dòng` đúng tại commit này; sau mỗi PR merge sẽ lệch — tra theo tên hàm.
Nguồn: 3 agent chỉ đọc (haiku) theo nhóm gate/cache/core · board/merge/train · hook/launchd/capacity, phiên điều phối gộp và đối chiếu.
Mốc A: `runs.jsonl` 465 dòng, 2026-10-29T07:27 → 2026-10-30T07:40 (lưu ở `.claude/audit-gate/stabilize/baseline-A-20261030.jsonl`).

## 1. Gate, cache, bộ chọn test

| Cơ chế | Hàm / vị trí | Env / TTL | Leo full? Chạy lại? |
|---|---|---|---|
| Scoped quyết định | `scoped_gate.py` `decide` (:481), `load_core` (:119); gọi từ `post-fix-gate.py` khi `--scoped` không `--since` (:6642-6659), `integrate.py:308` | `FAN_IN_CORE=5`, `MAX_BYTES` 2 MB | Lõi / không test / unmapped → full (fail closed) |
| `[core]` viết tay | `.agents/gate-core.txt` | — | Có |
| `[core:auto]` | `core_auto` (:584), `_fragile` (:560, ≥3 commit 🐛 trong 60 ngày), `write_core_auto` (:608) — snapshot do `gen --write-core` | — | Có |
| Fan-in / test-read-by sống | `decide` :520, :523 dùng số sống, không đọc snapshot | — | Có |
| Smoke | `[smoke]` 4 file, `decide` :488 | — | Chạy thêm |
| Suite cache khoá nội dung | `suite_cache.py` `cacheable` (:467), `selection_keyable` (:491); loại Unity/thiết bị, `cache:false`, `run_impacted.sh`, lệnh mạng | — | Miss → chạy |
| TTL suite cache | `suite_cache.py` `hit` :683 = `min(DEVKIT_SUITE_CACHE_MAX_S, DEVKIT_GATE_CACHE_MAX_S)` theo `last_pass_at` | `MAX_AGE_S` 6 h (:40) | `void` làm PASS cũ hết hạn |
| Kho cache | `prune` (:799) | `STORE_MAX=4000`, PASS 7 ngày, FAIL 30 ngày, dọn mỗi giờ | — |
| Quarantine flaky | `quarantined` (:1016) | `DEVKIT_FLAKY_QUARANTINE_S` 7 ngày | Chặn dùng lại |
| Unity reuse | `post-fix-gate.py` `reusable_suite` (:6912-6925) | `DEVKIT_UNITY_REUSE_MAX_S` 3600 | Chạy lại sau 1 h |
| Cached-full | `cached_full_pass` (:1267, tuổi :1290 theo `tested_at`) | `DEVKIT_GATE_CACHE_MAX_S` 21600 | Quá 6 h → `--full` chạy lại |
| `rerun_skip.json` (#648) | ghi `write_rerun_skip` (:5430), khớp `rerun_skip_match` (:5419), hạn `_rerun_skip_expired` (:5448 theo mtime), điều kiện :7103-7115 | `DEVKIT_GATE_CACHE_MAX_S` | Thoát sớm exit 0 |
| Sentinel | :6875-6882, `suite_cache.sentinel_due` (:961) | `DEVKIT_SENTINEL_MAX_S` 24 h; không chạy khi `DEVKIT_SLOT_PRIORITY=merge` | Tắt khoá nội dung, chạy thật |
| `stale_suite_ids` | :3311, gọi :6719 khi có `force_reason` | — | Thêm suite STALE |

## 2. Biên nhận, duyệt test, ma trận, nhật ký, tải

| Cơ chế | Hàm / vị trí | Ghi chú |
|---|---|---|
| `full_pass.json` | `write_full_pass_receipt` (:1732) | Đọc qua `cached_full_pass`; `push_gate.py:729`, `proof_gate.sh:630` |
| `scoped_pass.json` / `scoped_receipts/` | :1663-1670, :1752, :1844 (`scope:"scoped"`) | Không đụng full_pass |
| `task_receipts/` | `write_task_receipt` (:1571) | `scope:"task"` |
| `tree_receipts/` | `_tree_store` (:1682) | Sống qua gỡ worktree |
| `local_state_sha` | :1049 (băm `.env`, `local.properties`…) | `"?"` ⇒ tắt mọi dùng lại |
| `budget_pass.json` | :1945-1972, ràng HEAD + `SELECTION_ENV` | |
| Trailer `Test-approved-by` | `push_gate.py` `approved` (:570, so cây :612-619), `audited_head` (:455); `post-fix-gate.py:670-715` | |
| `approved_tests.json` | `post-fix-gate.py:727-815` (sha256 blob, reviewer ≠ author) | Tự duyệt bị từ chối :742 |
| `pm_verdict` auditedHead | `tools.js:789`, :803-816 | Từ chối nhiều head (#629) |
| `trust_additive_matrix` | `matrix_additions` (:2196), `trust_additive_matrix` (:2232), chạy cuối :6785-6804 | Chỉ thêm cuối |
| `runs.jsonl` | `_log_gate_run` (:6085), `_append_run_log` (:5963), `_run_log_fit` (:5910) | Dòng >3000 byte bị BỎ IM LẶNG; xoay >1280 KiB |
| `_full_red_on_tree` | :1418, gọi :8288/:8314 | Đọc runs.jsonl để chặn scoped xanh đè full đỏ |
| `heavy_slot` | `LOAD_MAX=100` (:28), `HEAVY_MAX=3` (:31), `acquire_for_suite` (:668) | Chờ ≤600 s rồi chạy |
| `capacity.py` | `hold_load`=8×lõi×hệ số, `heavy_max`=lõi/4×hệ số, `busy_load`=3×lõi×hệ số | `DEVKIT_CAPACITY` |
| Ưu tiên slot | `heavy_slot.PRIORITY`: merge 0, push 1, interactive 2, stop 3, nightly 4 | |

## 3. Board, merge gate, queue, train

| Cơ chế | Vị trí | Ghi chú |
|---|---|---|
| Tick runner | `super-board-run.sh:3367`, `tick_seconds: 30` | Stop marker mỗi tick |
| max_workers | `MAX_WORKERS` (:160), `at_worker_cap` (:892) | config 5, đếm toàn máy |
| Ngưỡng spawn | `spawn_load_threshold` (:826): `DEVKIT_SPAWN_LOAD` → config `spawn_load_max` → `busy_load` | Config CHƯA có `spawn_load_max` |
| Model worker | `worker_backend: claude-p` ⇒ `claude_model_for_tier` (:1258-1268, :1628): medium → sonnet mọi lane | `LADDERS` wave.js (:201-204) KHÔNG phải đường đang chạy |
| No-op | `block_noop_workers` (:2076), 2 lần / 24 h → Blocked | |
| Merge gate lock | `merge.lock` dưới `${REPO_PATH}` tương đối (:210, :226), `acquire` (:278), `own_lock_or_stop` (:718, gọi :1147, :1346) | Không có `merge-pr-<PR>.lock` |
| AC (T0054) | :426-470, :1208-1264, `AC_CARD` :432 | |
| BASE_SHA / PREFLIGHT | :575 / :611-623 | |
| TRAIN_PROVED / TREE_PROVED | :635-644, bỏ verify :1056-1057 | |
| Red-on-base (#251) | `red_only_on_base` (:1005) | Train không có |
| Merge | `gh pr merge --squash --match-head-commit` (:1347) | |
| Merge queue | `merge-queue.sh`, lock common-dir (:88), không gom đợt (gỡ 28c59ee2) | |
| Merge train | lock common-dir (:137), `verify_set` (:372), `single_red_test` (:315), bisect `solve` (:454) | |
| Stop | `super-board-stop.sh` kill worker :159-173, :281-291 | Không dừng tiến trình queue nền (`.mq.pid`) |
| Waiting-on | `super-board-waiting-on.py mark`, `sweep_waiting_on` (run.sh:2715) | |
| Worktree dọn | `sweep_merged_lanes` (:2485), `cleanup_stale_worktrees` (:2300), `worktree.py gc` | |

## 4. Hook, launchd, capacity

| Cơ chế | Vị trí | Ghi chú |
|---|---|---|
| Stop: `regression_gate.sh` | chạy `post-fix-gate.py --run-tests --json --task … --since` (:807) | Dùng lại block cùng key trong `REGRESSION_GATE_REPEAT_TTL_S` 1800; key đổi → chạy lại (lấy PASS từ budget_pass) |
| Stop: `test_evidence_gate.sh` | settings.json:228-232 (Stop, không phải PreToolUse) | Claim "pass" phải có XML/runner |
| Stop: `proof_gate.sh` | | Báo cáo 4 mục khi có push |
| Stop: `worktree_merge_gate.sh` | :590-612, :681-684 | Giữ Stop cả với worktree "owed" của phiên khác (3 lần) |
| PreToolUse `session_lock` trunk | `trunk_write`, `_lands_in_main` (:2128-2146) | Chặn cả ghi vào `<main>/.git/postfix-gate` (check-ignore trả 1) — thẻ #688 |
| `block-dangerous-git.sh` | `PM_STATE_ENVS` (:392), `backup_root` (:758) | Chặn `git branch -D` nhánh chưa merge |
| UserPromptSubmit tạo bug REPORTED | `enrich_context.py` `capture_bug` (:881) | Main trunk → `pending_rows.json` |
| Cài DevKit bẩn settings.json | `worktree.py` `install_args` (:745-768) → `install.sh:333` → `merge_json.py` cộng dồn hook template | 13 worktree có `M .claude/settings.json` |
| 37 test thừa | `gate-core.txt:86` `[core:auto]` chứa `universal-agent-devkit/.claude/settings.json` (test-read-by 37); `reads` khớp theo basename (`build_graph` :324-354) | Số lệch: 37 / 38 (comment :517) / 34 (grep) |
| gate-full đêm | `com.toanmobile.devkit.gate-full.agent-workbench-4783853b` 00:00, `gate_full.py run` | Đêm 30/10 ĐỎ, 427' 40", 159 dòng UNTESTED |
| gate-full cũ | `com.toanmobile.devkit.gate-full` trỏ worktree đã xoá | disabled 30/10; glob gỡ của `gate-full-schedule.sh:138` không khớp tên này |
| capacity | sampler (30 s), switch 07:00 (`CYCLE 1 0.75 0.5`), reapply, report 06:30, weekly CN 07:30 | PIN là FILE (0 byte), `DEVKIT_CAPACITY` qua `launchctl setenv` |

## 5. Ma trận mâu thuẫn

| # | Mâu thuẫn | Bằng chứng | Xử lý trong plan |
|---|---|---|---|
| C1 | 3 TTL 3 đồng hồ: suite cache (`last_pass_at`, min 2 env), rerun_skip (mtime, chỉ GATE), cached-full (`tested_at`) | `suite_cache.py:683`; `post-fix-gate.py:5448`, :1290 | Đợt 0 (b) đặt cả hai env 86400 |
| C2 | `rerun_skip` không ràng HEAD/ma trận/env chọn test, khác `BUDGET_RECORD` | :5430-5436 vs :1948-1968 | #678 + B |
| C3 | Sentinel chạy cả scoped đã leo full | :3673, :6875-6882 | Ghi trong Đợt 0 (b) |
| C4 | Dòng runs.jsonl >3000 byte bị bỏ im lặng nhưng `_full_red_on_tree` dựa vào nó | :5910-5939 vs :1418 | Shadow ghi archive riêng; L2 |
| C5 | `push_gate.audited_head` lấy khớp đầu, `pm_verdict` từ chối nhiều head | `push_gate.py:466-472` vs `tools.js:810` | L3 |
| C6 | Tiêu chí duyệt test: push_gate so cả cây, post-fix-gate theo blob từng file | `push_gate.py:600-619` vs `post-fix-gate.py:690-812` | L3 |
| C7 | `[core:auto]` snapshot vs fan-in sống trong `decide` | `scoped_gate.py:520/523` vs :584/:631 | L2 |
| C8 | `AGENT_STATE` khớp đúng gốc repo, không khớp bản kit ⇒ `universal-agent-devkit/.claude/settings.json`, `.agents/regression_status.json` thành lõi | `scoped_gate.py:40`, :517-518; `gate-core.txt` | L2 (hạ hub) / card |
| C9 | `heavy_slot.LOAD_MAX=100` vs `capacity.hold_load` 96 (12 lõi) | `heavy_slot.py:28` vs `capacity.py:109` | Ghi nhận |
| C10 | Model medium: wave.js sonnet/opus/session vs runner sonnet mọi lane | wave.js:201-204; run.sh:1262-1268 | Đợt 0 (c) sửa đường runner |
| C11 | Red-on-base chỉ ở merge gate, không ở train | gate :1005 vs train :372-440 | Bỏ (#669 đóng) |
| C12 | Lock merge gate tương đối cwd; train/queue common-dir | gate :210/:226 vs train :137, queue :88 | L1 |
| C13 | Stop không dừng tiến trình merge queue nền | run.sh:1172 vs stop.sh | Card Backlog |
| C14 | run.md: reviewer "không rerun gate" nhưng cùng khối yêu cầu chạy gate | run.md:466-469 | L1 / dọn docs |
| C15 | Nightly 00:00 → ~07:08 chồng `report` 06:30 + `switch` 07:00 | `report.py:30`, `switch.sh` | Ghi nhận (đo) |
| C16 | `hooks.json` template ≠ `settings.json` (thứ tự, tập hook) ⇒ cài DevKit làm bẩn settings.json | `hooks.json` vs settings.json:58-146 | Card Backlog |
| C17 | Stop hook xanh giả khi UNTESTED sau FAIL: fail-fast #647 dừng khi một suite FAIL, kể cả FAIL `env_blocked` (bị kill) ⇒ suite lỗi thật đứng sau thành UNTESTED; `regression_gate.sh` xếp UNTESTED vào busy rồi cho Stop qua "vì môi trường" ⇒ lỗi thật bị che | `post-fix-gate.py:7668-7670`; `regression_gate.sh:933-934`, :985 | Đang sửa ở PR #689 (#678) |

## 6. Gate chạy lại trên cùng một cây (một PR, queue bật)

| Lần | Ai | Lệnh | Lặp? |
|---|---|---|---|
| 1 | QA | `post-fix-gate --run-tests --scoped --brief --json` trên cây gộp base | Gốc |
| 2 | Review | chạy lại lệnh test của QA (run.md:466) | Lặp |
| 3 | Review | `post-fix-gate --run-tests --brief` (run.md:469) | Lặp |
| 4 | Train verify | `verify_commands` + `--scoped` | Lặp lần 1 (không đọc biên nhận QA) |
| 5 | Train bisect | `solve` | +log2(n) khi đỏ |
| 6–8 | Train preflight / dry-run / merge | `--preflight`, `--dry-run`, `--train-receipt` | Không lặp |

Đo số liệu thật (script Pha 1) sẽ bổ sung: chạy lại trên cây đỏ, giờ máy, BUSY, đỏ giả, merge gate median/p90, load.
