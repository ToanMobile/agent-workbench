# Báo Cáo Deep Code Audit Toàn Diện — 10 Chuyên Gia (Tier 3 Auditor)

> **Ngày kiểm toán:** 2026-10-16  
> **Phạm vi:** Toàn bộ mã nguồn thực thi, hooks, scripts, profiles, rules, MCP server và test suite của `agent-workbench` (`universal-agent-devkit` + `mcp-servers/antigravity-pm-mcp`) cùng đối chiếu chéo với 2 worktree đang mở (`agent-a89d86b8e80426e23` — A15 Gate Speed và `agent-aa3f350b6e679b047` — Guard Parser).  
> **Phương pháp:** 10 Agent kiểm toán độc lập (Tier 3 Auditor) đọc **100% từng dòng code** trên **197 file cốt lõi** (**71.502 dòng code**), kết hợp kiểm chứng AST/Knowledge Graph (`codebase-memory-mcp`, generation `2026-10-15T15:12:10Z`, `21.597` nodes, `63.203` edges) và thực nghiệm PoC trực tiếp.

---

## 1. Tổng Quan & Ma Trận Độ Phủ 10 Agent Kiểm Toán

| Slice | Agent Role | Phạm vi kiểm toán (Bounded Scope) | Số file | Số dòng đã đọc | P0 | P1 | P2 | P3 | Tổng lỗi |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **01** | Core Gate & Proof CLI | `bin/agent-kit`, `bin/post-fix-gate.py`, `bin/proof-capture.py`, `bin/push_gate.py`, `bin/tree_fp.py` (+ diff worktree A15) | 5 | 7.652 | 0 | 3 | 3 | 1 | **7** |
| **02** | Lock, Checklist & Health CLI | `bin/session_lock.py`, `bin/session_authorship.py`, `bin/regression_checklist.py`, `bin/agent-health.py`, `bin/agent-config.py`, `bin/instincts.py`, `bin/ocr-review`, `bin/install.sh`, `bin/quick-install.sh`, `setup.sh` | 10 | 7.997 | 3 | 5 | 5 | 3 | **16** |
| **03** | Command & Security Guard Hooks | `hooks/block-dangerous-git.sh`, `hooks/hardware_safety_gate.sh`, `hooks/security_gate.sh`, `hooks/foreign_repo_gate.sh`, `hooks/worktree_guard.sh`, `hooks/worktree_merge_gate.sh`, `hooks/shell_writes.py`, `hooks/bash_write_ledger.sh`, `hooks/read_ledger.sh`, `hooks/precode_gate.sh` (+ worktree Guard) | 13 | 8.839 | 4 | 3 | 3 | 1 | **11** |
| **04** | Stop Hooks & Session Lifecycle | `hooks/hooks.json`, `hooks/devkit_harness.py`, `hooks/devkit_profile.py`, `hooks/proof_gate.sh`, `hooks/regression_gate.sh`, `hooks/review_gate.sh`, `hooks/review_timing_guard.sh`, `hooks/test_evidence_gate.sh`, `hooks/testsourceset_gate.sh`, `hooks/claim_check.sh`, `hooks/comment_claim_guard.sh`, `hooks/churn_guard.sh`, `hooks/session_*.{sh,py}`, `hooks/*_bridge.sh` | 19 | 8.368 | 4 | 4 | 3 | 1 | **12** |
| **05** | Git, Worktree & Parallel Lanes | `scripts/git/worktree.py`, `scripts/git/worktree_sandbox.py`, `scripts/git/githooks.sh`, `scripts/git/git-pre-commit.sh`, `scripts/git/git-commit-msg.sh`, `scripts/git/backup_conflict.sh`, `scripts/governance/lane_plan.py`, `adapters/setup_*.sh`, `completions/agent-kit.bash` | 12 | 5.582 | 4 | 6 | 5 | 2 | **17** |
| **06** | Governance, Context & Nightly | 22 scripts trong `scripts/governance/*.{py,sh}` + 5 scripts trong `scripts/context/*.py` | 27 | 6.554 | 1 | 7 | 9 | 4 | **21** |
| **07** | Linters, Red-Proof & Metrics | `scripts/linters/*.py`, `scripts/testing/*.py`, `skills/devkit-audit/scripts/devkit_metrics.py`, `workflows/*.{mjs,js}`, `dashboard/*` | 18 | 7.674 | 1 | 10 | 9 | 3 | **23** |
| **08** | Rules, Profiles, Skills & Templates | `AGENTS.md`, `rules/*.md`, `profiles/*/profile.json`, `profiles/game/{hooks,scripts}/*`, `templates/*`, `skills/*/SKILL.md` | 51 | 6.657 | 3 | 7 | 5 | 1 | **16** |
| **09** | Antigravity PM MCP Server | `mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js` + 20 modules trong `src/*.js` | 21 | 5.821 | 3 | 7 | 5 | 2 | **17** |
| **10** | Test Suite & Impacted Runner | `tests/run_impacted.sh`, `tests/impact_map.txt`, `tests/lib/*`, 11 file `parse_unusable`, 2 file `parse_partial`, `hooks/tests/*`, `tests/worktree_git/*` | 24 | 6.358 | 0 | 2 | 2 | 0 | **4** |
| **TỔNG** | **10 Auditors** | **Toàn bộ `agent-workbench`** | **197** | **71.502** | **23** | **54** | **49** | **18** | **144** |

> [!IMPORTANT]
> **Giải mã nguyên nhân gốc của 5 nút thắt vận hành lớn nhất hiện tại:**
> 1. **Tại sao `review_gate.sh` tự xả (auto-release) 43 lần ở `Neighbours-From-Hell` và chặn 10 lần ở `agent-workbench`?** → Do lỗi dòng 601 của [`review_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L601) gọi `_names(_bcmd, _rel, _base)` thay vì `_writes(_bcmd, _rel)` khi mở rộng cửa sổ lệnh Bash đang mở (`BASH_OPEN_MAX_S = 7200` giây = 2 giờ). Mọi lệnh chỉ đọc (`git diff`, `dotnet test --filter`, `grep`) có nhắc tên file đang dirty đều bị quy chụp là phiên hiện tại vừa sửa file đó (**Slice 04 — P0-01**).
> 2. **Tại sao `nightly.py` kẹt cứng 386 dòng `waiting` RED-proof trên cả 5 repo?** → Deadlock kép (Catch-22) giữa [`nightly.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L120-L130) và [`regression_checklist.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/universal-agent-devkit/bin/regression_checklist.py#L418-L433): `checkout_busy()` từ chối chạy trên `main` khi bật Trunk Mode (`exit 5`), nhưng `rc.skip_bookkeeping()` lại từ chối ghi sổ trên mọi linked worktree (**Slice 06 — P0-01**).
> 3. **Tại sao `red_proof.py` làm hỏng 100% bằng chứng RED ở chế độ `revert`?** → Trong hàm `prove_one()` của [`red_proof.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L569-L755), biến cục bộ `patch = git(...).stdout` (kiểu `str`) ở dòng 673 ghi đè (shadow) tham số `patch: Path | None = None` ở dòng 569, khiến `meta["patch"]` lưu nội dung diff thay vì đường dẫn file (**Slice 07 — P0-01**).
> 4. **Tại sao `block-dangerous-git.sh` và `hardware_safety_gate.sh` vẫn có thể bị qua mặt dù đã sửa ở worktree Guard?** → Do bất đồng bộ trạng thái nháy đơn giữa `drop_comments()` (hiểu ANSI-C `$'\''`) và `shlex(posix=True)` (coi `\` là ký tự thường trong `'...'`), cho phép payload `echo $'\''; git reset --hard HEAD; echo \'` và `echo $'\''; rm -rf /Users; echo \'` đi qua với **`exit 0`** trên cả `main` lẫn worktree `agent-aa3f350b6e679b047` (**Slice 03 — P0-01, P0-02, P0-03**).
> 5. **Tại sao `antigravity-pm-mcp` có thể bị vượt rào `commitPolicy: 'forbid'` và `forbiddenPaths`?** → `gateCtx` truyền `snap.wt` (chỉ gồm file chưa commit) thay vì `changedFiles` vào `soiThayDoi()` và `lastChangeAtOf()`; nếu Worker chạy `git commit`, `snap.wt` rỗng `[]` và toàn bộ kiểm tra diff/timestamp bị bỏ qua 100% (**Slice 09 — P0-01, P0-02**).

---

## 2. Chi Tiết Phát Hiện Theo Từng Slice (01 → 10)

### Slice 01 — Core Orchestrator, Gate & Proof Entrypoints (`7.652` dòng / 5 file)

**Phạm vi:**
- [`universal-agent-devkit/bin/agent-kit`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-kit) (491 dòng)
- [`universal-agent-devkit/bin/post-fix-gate.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py) (5.605 dòng trên `main` / 5.654 dòng trên worktree A15)
- [`universal-agent-devkit/bin/proof-capture.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/proof-capture.py) (784 dòng)
- [`universal-agent-devkit/bin/push_gate.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/push_gate.py) (646 dòng)
- [`universal-agent-devkit/bin/tree_fp.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/tree_fp.py) (126 dòng)

#### [S01-P1-01] Race condition TOCTOU tái sinh `full_pass.json` đã bị vô hiệu hóa & thiếu schema version trên `main`
- **Vị trí:** [`universal-agent-devkit/bin/post-fix-gate.py#L985-L1022`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L985-L1022), [`#L1063-L1227`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L1063-L1227), [`#L3594-L3627`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L3594-L3627), [`#L4850-L5096`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L4850-L5096), [`#L5419-L5455`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L5419-L5455)
- **Cơ chế lỗi:**
  1. Trên `main`, `reuse_full_pass()` chạy ở dòng 4855 **trước khi** lấy khóa `test_run.lock` (dòng 5053), và nếu tất cả suite đều có trong `cached` (`nothing_to_run == True`), gate bỏ qua luôn việc lấy khóa. Khi Phiên A đang chạy test (đã gọi `invalidate_full_pass(root)` ở dòng 5086 để xóa `full_pass.json`), Phiên B chạy song song đọc trúng `suite_pass.json` cũ và gọi `write_full_pass()` ghi đè lại `full_pass.json` mới dù Phiên A sắp FAIL.
  2. `write_budget_record()` trên `main` không ghi trường `"head"` và thiếu biến môi trường chọn lọc (`POSTFIX_GATE_SKIP_E2E`, `SKIP_TESTS`) trong `SELECTION_ENV`, khiến receipt từ lượt chạy cắt giảm được tái sử dụng cho `--full`.
  3. `cached_full_pass()` trên `main` không giới hạn kích thước file và không bắt `OverflowError`, `RecursionError`, `NaN`/`Infinity`.
  4. Ở dòng 5434, `lock_fh.close()` nhả khóa **trước khi** gọi `update_regression_checklist()` (dòng 5450).
- **Khuyến nghị sửa:** Hợp nhất bản vá từ worktree `agent-a89d86b8e80426e23` (`SCHEMA_VERSION = 2`, kiểm tra `full_pass.json` còn tồn tại dưới khóa trước khi `reuse_full_pass`), đồng thời dời khối `finally` đóng `lock_fh` xuống sau dòng 5455.

#### [S01-P1-02] Lỗi khớp chuỗi nghĩa đen với mẫu glob trong `tree_fp.py` và `push_gate.py`
- **Vị trí:** [`.claude/worktrees/agent-a89d86b8e80426e23/universal-agent-devkit/bin/tree_fp.py#L28`](file:///Volumes/Data/Toan/agent-workbench/.claude/worktrees/agent-a89d86b8e80426e23/universal-agent-devkit/bin/tree_fp.py#L28), [`universal-agent-devkit/bin/tree_fp.py#L49`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/tree_fp.py#L49), [`#L122`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/tree_fp.py#L122), [`universal-agent-devkit/bin/push_gate.py#L233`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/push_gate.py#L233), [`#L553`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/push_gate.py#L553)
- **Cơ chế lỗi:** Worktree A15 thêm mẫu glob `".agents/.regression_status." + "[a-z0-9_]" * 8` vào `EXCLUDE` cho `git status --`: `:(exclude)<glob>`. Tuy nhiên `_non_git_fingerprint()` (dòng 49), `_big_untracked()` (dòng 122) và `push_gate.py` (dòng 233, 553) lại so sánh bằng chuỗi trần `rel == ex or rel.startswith(ex + "/")`, không dùng `fnmatch.fnmatchcase`. Nếu file tạm `.agents/.regression_status.a1b2c3d4` tồn tại khi `update_regression_checklist` đang chạy, fingerprint bị lệch và `push_gate.py` báo lỗi dirty tree giả.
- **Khuyến nghị sửa:** Tạo helper `_is_excluded(rel: str) -> bool` dùng `fnmatch.fnmatchcase(rel, ex)` khi `ex` chứa `[*?\[]`.

#### [S01-P1-03] Bypass hoàn toàn `check_png()` và thiếu `timeout` cho nhánh chụp 3D (`capture_3d_proof.py`)
- **Vị trí:** [`universal-agent-devkit/bin/proof-capture.py#L701-L715`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/proof-capture.py#L701-L715)
- **Cơ chế lỗi:** Khi `plan["action"] == "3d"`, `proof-capture.py` chạy `capture_3d_proof.py` bằng `subprocess.run` **không có `timeout=`** và trả về `0` ngay khi `r.returncode == 0 and out.is_file()` mà **không gọi `check_png(out)`** (dòng 776 chỉ chạy cho nhánh Android/Web). Ảnh PNG rỗng 0 byte, dưới 8 KB hoặc trắng trơn đều được đóng dấu `PROOF_SAVED=`.
- **Khuyến nghị sửa:** Thêm `timeout=120` vào `subprocess.run` và gọi `check_png(out)` trước khi `return 0`.

#### [S01-P2-01] `asked_full` bỏ sót `POSTFIX_GATE_FULL=1`, `CI=true` và `--record-lesson`, trả về `exit 0` sai khi bị hoãn (deferred)
- **Vị trí:** [`universal-agent-devkit/bin/post-fix-gate.py#L2638-L2652`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L2638-L2652), [`#L4764-L4784`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L4764-L4784), [`#L5383-L5394`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L5383-L5394), [`#L5537-L5539`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L5537-L5539)
- **Cơ chế lỗi:** `asked_full = bool(getattr(args, "full", False))` chỉ đọc cờ CLI `--full`, trong khi `full_mode` còn được bật qua `POSTFIX_GATE_FULL=1`, `CI=true`, hoặc `--record-lesson`. Khi bị hạ cấp xuống impacted mode do còn phiên khác đang chạy, dòng 5537 kiểm tra `if deferred_full_reason and asked_full: return 5`, nên các trường hợp trên nhận `exit 0` giả dù không ghi receipt `full_pass.json`.
- **Khuyến nghị sửa:** Đặt `asked_full = full_mode` ngay tại dòng 4771 trước khi kiểm tra hạ cấp đa phiên.

#### [S01-P2-02] `approved_tests.json` đóng dấu `int(time.time())` không kèm hash nội dung, tạo thẻ bài miễn tử vĩnh viễn cho file test
- **Vị trí:** [`universal-agent-devkit/bin/post-fix-gate.py#L690-L702`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L690-L702), [`#L831`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L831)
- **Cơ chế lỗi:** `split_user_approved` gán `approved_at[f] = int(time.time())` cho mọi đường dẫn có trong `.claude/audit-gate/approved_tests.json` (dạng list đường dẫn không lưu SHA-256). Vì `time.time() >= mtime`, mọi chỉnh sửa tiếp theo trên file test đó trong tương lai đều tự động vượt qua kiểm tra `edited_test_is_red_at_head()`.
- **Khuyến nghị sửa:** Lưu kèm SHA-256 của file test tại thời điểm duyệt trong `approved_tests.json`.

#### [S01-P2-03] Thiếu `timeout` trong `tree_fp.py` & lỗi `set -euo pipefail` / thiếu quote trong `agent-kit`
- **Vị trí:** [`universal-agent-devkit/bin/tree_fp.py#L24-L25`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/tree_fp.py#L24-L25), [`#L96`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/tree_fp.py#L96); [`universal-agent-devkit/bin/agent-kit#L143`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-kit#L143), [`#L308-L319`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-kit#L308-L319)
- **Cơ chế lỗi:** `tree_fp.py` gọi `git rev-parse`, `git status`, `git diff` không có `timeout=`, có thể treo vô hạn nếu `.git/index.lock` bị kẹt. Trong `agent-kit`, lệnh `find "$BASE_DIR/skills"` ở dòng 143 không kiểm tra `[[ -d "$BASE_DIR/skills" ]]` nên nổ dưới `set -euo pipefail`, và `$R_APPLY` ở dòng 319 không được bọc ngoặc kép (thay bằng mảng `R_ARGS=()`).

#### [S01-P3-01] `push_gate.py` nạp lại toàn bộ 5.600 dòng `post-fix-gate.py` qua `exec_module` mỗi lần gọi `untestable_only()`
- **Vị trí:** [`universal-agent-devkit/bin/push_gate.py#L237-L250`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/push_gate.py#L237-L250), [`#L585`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/push_gate.py#L585)
- **Khuyến nghị sửa:** Cache module đã nạp vào biến toàn cục `_PFG_MOD` ở cấp module.

---

### Slice 02 — Session Lock, Regression Checklist, Health, Config & Installers (`7.997` dòng / 10 file)

**Phạm vi:**
- [`universal-agent-devkit/bin/session_lock.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py) (1.894 dòng)
- [`universal-agent-devkit/bin/session_authorship.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_authorship.py) (418 dòng)
- [`universal-agent-devkit/bin/regression_checklist.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py) (3.112 dòng)
- [`universal-agent-devkit/bin/agent-health.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-health.py) (398 dòng)
- [`universal-agent-devkit/bin/agent-config.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py) (569 dòng)
- [`universal-agent-devkit/bin/instincts.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/instincts.py) (368 dòng)
- [`universal-agent-devkit/bin/ocr-review`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/ocr-review) (366 dòng)
- [`universal-agent-devkit/bin/install.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/install.sh) (748 dòng)
- [`universal-agent-devkit/bin/quick-install.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/quick-install.sh) (119 dòng)
- [`universal-agent-devkit/setup.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/setup.sh) (5 dòng)

#### [S02-P0-01] Race condition TOCTOU ghi đè làm mất bài học trong `instincts.py`
- **Vị trí:** [`universal-agent-devkit/bin/instincts.py#L165-L178`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/instincts.py#L165-L178), [`#L314-L318`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/instincts.py#L314-L318)
- **Cơ chế lỗi:** Trong `cmd_add()`, khối `if not target.exists(): shutil.copyfile(template, target)` (dòng 316–317) chạy **bên ngoài** khóa `fcntl.flock` của `append_lesson()`. Khi 2 tiến trình cùng gọi `instincts.py add` lần đầu, Tiến trình B chạy `shutil.copyfile` cắt cụt (truncate) file đúng lúc Tiến trình A vừa ghi xong bài học đầu tiên.
- **Khuyến nghị sửa:** Đưa logic khởi tạo từ `template` vào bên trong `with open(lock_path, "a+")` sau khi đã lấy `fcntl.flock(lf.fileno(), fcntl.LOCK_EX)`.

#### [S02-P0-02] Đụng độ băm 100% (`_crit_hash`) giữa các tiêu chí đối lập dấu toán học trong `regression_checklist.py`
- **Vị trí:** [`universal-agent-devkit/bin/regression_checklist.py#L756-L761`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L756-L761), [`#L2215-L2216`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L2215-L2216), [`#L2259-L2270`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L2259-L2270)
- **Cơ chế lỗi:** `_crit_hash(t)` băm kết quả của `norm_title(t)`, vốn dùng `re.findall(r"\w+", text, flags=re.UNICODE)` và loại bỏ toàn bộ toán tử so sánh (`<`, `>`, `<=`, `>=`, `==`, `!=`, `-`). Hệ quả: `"Độ trễ < 300ms"` và `"Độ trễ > 300ms"` sinh ra cùng một `_crit_hash`, khiến gate không phát hiện tiêu chí đã bị đảo ngược hoàn toàn mà giữ nguyên trạng thái `PASS`.
- **Khuyến nghị sửa:** Trong `_crit_hash()`, chuẩn hóa khoảng trắng `re.sub(r"\s+", " ", t.strip().lower())` nhưng giữ nguyên mọi ký tự toán tử.

#### [S02-P0-03] Bypass `Trunk Mode` (`_bash_trunk_write`) từ linked worktree ghi thẳng vào `main` qua biến môi trường
- **Vị trí:** [`universal-agent-devkit/bin/session_lock.py#L1522-L1525`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L1522-L1525)
- **Cơ chế lỗi:** Trong `_bash_trunk_write()`, khi đích ghi chứa `$` hoặc `` ` ``, code kiểm tra:
  ```python
  if "$" in t or "`" in t:
      if _lands_in_main(wd or here, main, sw):
          return True
      continue
  ```
  Khi Agent đang đứng trong một linked worktree (`here != main`, `wd is None`), `_lands_in_main(here, main, sw)` trả về `False`, nên vòng lặp `continue` và bỏ qua kiểm tra! Agent trong worktree có thể chạy `MAIN=/Volumes/Data/Toan/agent-workbench; echo x > "$MAIN/src/app.py"` để ghi thẳng vào `main`.
- **Khuyến nghị sửa:** Trước khi tách lệnh, thu thập các phép gán biến tĩnh `VAR=/abs/path` trong câu lệnh để nội suy `$VAR`/`${VAR}`, hoặc nếu đích bắt đầu bằng `$VAR` chưa rõ nguồn gốc thì từ chối (fail-closed).

#### [S02-P1-01] Race condition TOCTOU xóa trạng thái phiên đang chạy giữa `Notification (idle_prompt)` và `PreToolUse`
- **Vị trí:** [`universal-agent-devkit/bin/session_lock.py#L468-L506`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L468-L506), [`#L1588-L1594`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L1588-L1594), [`#L1751-L1834`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L1751-L1834)
- **Cơ chế lỗi:** `heartbeat_session()` và `mark_idle_session()` đọc-sửa-ghi file `{sid}.json` mà **không giữ khóa `_guard(root)`**, đồng thời `heartbeat()` tiết lưu (throttle) 30 giây mới cập nhật `devkit-session.lock` một lần.
- **Khuyến nghị sửa:** Bọc `heartbeat_session` và `mark_idle_session` trong `_guard(root)` hoặc dùng `fcntl.flock` trực tiếp trên `{sid}.json`.

#### [S02-P1-02] `holder_pid()` chỉ hỗ trợ Linux `/proc` (vô tác dụng trên macOS) & lỗ hổng PID recycling
- **Vị trí:** [`universal-agent-devkit/bin/session_lock.py#L546-L582`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L546-L582), [`#L1413-L1445`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L1413-L1445); [`universal-agent-devkit/bin/session_authorship.py#L292-L294`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_authorship.py#L292-L294)
- **Cơ chế lỗi:** `holder_pid()` chỉ đọc `/proc/{pid}/stat` nên luôn trả về `None` trên macOS (Darwin). Ngoài ra `is_pid_alive()` trả `True` khi gặp `PermissionError` (PID đã được hệ điều hành cấp lại cho daemon của `root`), không đối chiếu thời điểm khởi tạo tiến trình (`ps -o lstart= -p <pid>`).
- **Khuyến nghị sửa:** Lưu thêm `pid_start` (`ps -o lstart=`) vào lock file và dùng `ps -o ppid=,comm=` làm fallback trên macOS.

#### [S02-P1-03] 4 lỗi trạng thái trong `regression_checklist.py`: dòng `retired` bị kẹt `STALE` vĩnh viễn, khớp chuỗi con `k not in json.dumps`, bỏ sót `cached` và nuốt trạng thái `FLAKY`
- **Vị trí:** [`universal-agent-devkit/bin/regression_checklist.py#L782-L790`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L782-L790), [`#L1868-L1878`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L1868-L1878), [`#L2561-L2563`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L2561-L2563), [`#L2611-L2618`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L2611-L2618)
- **Cơ chế lỗi:**
  1. Dòng 1871 chỉ gắn `retired = True` khi `r.get("last_status", "UNTESTED") == "UNTESTED"`, nên mọi dòng matrix cũ từng chạy 1 lần sẽ kẹt ở `STALE` mãi mãi sau khi xóa module.
  2. Dòng 2616 kiểm tra `k not in json.dumps(status.get("rows", {}))` — nếu ID ngắn (như `"G1"`) xuất hiện bên trong tên file hoặc command của dòng khác, dòng mồ côi đó không bao giờ được dọn.
  3. Dòng 2561 chỉ xóa `impacted_at` khi `mode == "full"`, bỏ sót `mode == "cached"`.
  4. Dòng 784 kiểm tra `if last.get("status") == "FAIL" and last.get("flaky"): return "FLAKY"`, nhưng khi flaky test pass ở lần retry (`status == "PASS", flaky == True`), nó trả về `"PASS"` thay vì `"FLAKY"`.

#### [S02-P1-04] `sync_guards()` bỏ qua cập nhật `tests` khi `continue` sớm & `_check_journal()` lưu bản hỏng vào `rb["good"]`
- **Vị trí:** [`universal-agent-devkit/bin/regression_checklist.py#L468-L498`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L468-L498), [`#L1294-L1389`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L1294-L1389)
- **Khuyến nghị sửa:** Tách hàm `_sync_guard_tests(row, g, root)` gọi ở mọi nhánh trước `continue`; chỉ đẩy snapshot vào `rb["good"]` khi `problems` ban đầu rỗng.

#### [S02-P1-05] Điểm sức khỏe `agent-health.py` báo khống 100/100 khi `hooks: {}` rỗng, thiếu git hooks hoặc `trust["problem"]` có lỗi
- **Vị trí:** [`universal-agent-devkit/bin/agent-health.py#L218-L318`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-health.py#L218-L318)
- **Cơ chế lỗi:**
  1. Dòng 221 kiểm tra `isinstance(data.get("hooks"), dict)` — ngay cả khi `"hooks": {}` rỗng không có hook nào, vẫn được cộng điểm tối đa.
  2. Dòng 289 cho phép `git_hooks["pre_commit"] == "absent"` vẫn pass (`in ("executable", "absent")`).
  3. Dòng 305 truyền cứng `True` vào `score.check(True, ..., warn_only=True)` khi `trust["problem"]` khác rỗng, nên không bao giờ trừ điểm.

#### [S02-P2-01..05 & S02-P3-01..03] Các lỗi cấp P2/P3 trong Slice 02
- **[S02-P2-01]** [`session_lock.py#L1537-L1548`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_lock.py#L1537-L1548): `_bash_trunk_write` không cập nhật `wd` khi chuỗi lệnh có `cd /tmp && echo x > a.txt`, chặn nhầm lệnh ghi ra `/tmp`.
- **[S02-P2-02]** [`session_authorship.py#L36-L80`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/session_authorship.py#L36-L80): `_git_Checkouts` bỏ sót `env -C <dir> git ...` và `git --work-tree=<dir>`.
- **[S02-P2-03]** [`agent-config.py#L204-L216`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py#L204-L216), [`#L350`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py#L350), [`#L413`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py#L413), [`#L482`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py#L482): Chuyển profile khỏi `game` không gỡ symlink `.claude/hooks/validate-assets.sh`; biến `active-profile_old` tạo symlink gãy `.agents/rules/active-profile_old.md`.
- **[S02-P2-04]** [`ocr-review#L67-L87`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/ocr-review#L67-L87), [`#L172-L185`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/ocr-review#L172-L185): Lần gọi `proc.communicate()` thứ 2 trong `except subprocess.TimeoutExpired` không có `timeout`, treo nếu tiến trình con giữ pipe stdout/stderr; bộ lọc arg bỏ sót dạng `--commit=SHA`.
- **[S02-P2-05]** [`install.sh#L647`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/install.sh#L647) & [`quick-install.sh#L25,L69`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/quick-install.sh#L25): `quick-install.sh` chạy ở chế độ `copy` không copy `profiles/`, `adapters/`, `scripts/` vào `.agents/devkit/`.
- **[S02-P3-01..03]** [`instincts.py#L97`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/instincts.py#L97) (`cmd_add` không gọi `redact_secrets` lên `rule`/`trap`), [`agent-config.py#L72`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/agent-config.py#L72), [`setup.sh#L1-L5`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/setup.sh#L1-L5).

---

### Slice 03 — PreToolUse & Command Guard Hooks (`8.839` dòng / 13 file trên `main` + worktree `agent-aa3f350b6e679b047`)

**Phạm vi:**
- [`universal-agent-devkit/hooks/block-dangerous-git.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh) (1.298 dòng trên `main` / 1.445 dòng trên worktree Guard)
- [`universal-agent-devkit/hooks/hardware_safety_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hardware_safety_gate.sh) (743 dòng trên `main` / 986 dòng trên worktree Guard)
- [`.claude/worktrees/agent-aa3f350b6e679b047/universal-agent-devkit/hooks/shell_norm.py`](file:///Volumes/Data/Toan/agent-workbench/.claude/worktrees/agent-aa3f350b6e679b047/universal-agent-devkit/hooks/shell_norm.py) (249 dòng)
- [`universal-agent-devkit/hooks/security_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/security_gate.sh) (666 dòng)
- [`universal-agent-devkit/hooks/foreign_repo_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/foreign_repo_gate.sh) (187 dòng)
- [`universal-agent-devkit/hooks/worktree_guard.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/worktree_guard.sh) (581 dòng)
- [`universal-agent-devkit/hooks/worktree_merge_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/worktree_merge_gate.sh) (493 dòng)
- [`universal-agent-devkit/hooks/shell_writes.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/shell_writes.py) (642 dòng)
- [`universal-agent-devkit/hooks/bash_write_ledger.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/bash_write_ledger.sh) (98 dòng)
- [`universal-agent-devkit/hooks/read_ledger.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/read_ledger.sh) (268 dòng)
- [`universal-agent-devkit/hooks/precode_gate.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/precode_gate.sh) (1.183 dòng)

#### [S03-P0-01] Bypass hoàn toàn `block-dangerous-git.sh`, `hardware_safety_gate.sh`, `shell_writes.py` và `shell_norm.py` qua bất đồng bộ ANSI-C Quote (`$'\''`)
- **Vị trí:** [`universal-agent-devkit/hooks/block-dangerous-git.sh#L970-L1001`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L970-L1001), [`#L1222`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L1222); [`universal-agent-devkit/hooks/hardware_safety_gate.sh#L596-L645`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hardware_safety_gate.sh#L596-L645); [`universal-agent-devkit/hooks/shell_writes.py#L61-L90`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/shell_writes.py#L61-L90); [`.claude/worktrees/agent-aa3f350b6e679b047/universal-agent-devkit/hooks/shell_norm.py#L186-L246`](file:///Volumes/Data/Toan/agent-workbench/.claude/worktrees/agent-aa3f350b6e679b047/universal-agent-devkit/hooks/shell_norm.py#L186-L246)
- **Cơ chế lỗi & PoC:** Trong Bash/Zsh, `$'\''` là một chuỗi ANSI-C hợp lệ biểu diễn một dấu nháy đơn. Bộ lọc `drop_comments()` cho phép `\` thoát `'` ngay cả khi `q == "'"`, nên hiểu `$'\''` đã đóng nháy. Ngược lại, `shlex.shlex(..., posix=True)` coi `'...'` là nháy đơn thuần túy (không có escape `\` bên trong), nên thấy `$'` mở nháy, `\` là ký tự thường, `'` đóng nháy, và dấu `'` thứ hai **mở một chuỗi nháy đơn mới** nuốt trọn câu lệnh nguy hiểm phía sau thành một đối số văn bản của `echo`!
  - **PoC 1 (`exit 0` trên cả `main` và worktree Guard):** `echo $'\''; git reset --hard HEAD; echo \'`
  - **PoC 2 (`exit 0` trên cả `main` và worktree Guard):** `echo $'\''; rm -rf /Users; echo \'`
- **Khuyến nghị sửa:** Chuẩn hóa (normalize) các token ANSI-C `$'...'` trước khi đưa vào `shlex` hoặc viết state machine chung xử lý riêng trạng thái `q == "$'"` (cho phép `\'`) tách biệt với `q == "'"` (không cho phép `\'`).

#### [S03-P0-02] Bypass qua `\<newline>` nối dòng ngay trước `#` làm lệch pha trạng thái nháy trong `drop_comments`
- **Vị trí:** [`universal-agent-devkit/hooks/block-dangerous-git.sh#L976-L996`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L976-L996) (worktree `#L1081`); [`universal-agent-devkit/hooks/hardware_safety_gate.sh#L602-L622`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hardware_safety_gate.sh#L602-L622) (worktree `#L845`)
- **Cơ chế lỗi & PoC:** Khi một dòng kết thúc bằng `\<newline>` và dòng kế tiếp bắt đầu bằng `# '`, `drop_comments` đặt `esc = True` tại `\`, rồi ở ký tự `\n` kế tiếp **không xóa `esc` về `False`** (`if prev_esc: esc = False` bị trượt vì `prev_esc` của `\n` là `True` chỉ xóa tại `\n`, nhưng nếu trước `#` có `\ ` hoặc `\<newline>` kết hợp comment có chứa dấu `'`), dấu `#` không được nhận diện là comment, khiến dấu `'` bên trong comment mở nháy giả nuốt trọn dòng lệnh nguy hiểm bên dưới:
  - **PoC (`exit 0` trên cả `main` và worktree Guard):**
    ```bash
    echo \
    # '
    git reset --hard HEAD
    # '
    ```
- **Khuyến nghị sửa:** Chạy `fold_continuations()` (gộp `\<newline>` ngoài nháy đơn) **trước khi** chạy `drop_comments()`.

#### [S03-P0-03] Bypass qua `\${` (escaped dollar-brace) làm tăng biến đếm `brace` giả trong `drop_comments`
- **Vị trí:** [`universal-agent-devkit/hooks/block-dangerous-git.sh#L984-L995`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L984-L995) (worktree `#L1089`); [`universal-agent-devkit/hooks/hardware_safety_gate.sh#L610-L621`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hardware_safety_gate.sh#L610-L621) (worktree `#L853`)
- **Cơ chế lỗi & PoC:** Điều kiện `elif c == "{" and i and text[i - 1] == "$": brace += 1` không kiểm tra ký tự `$` trước đó đã bị escape (`\${`) hay chưa. Khi viết `\${`, Bash coi đó là chuỗi văn bản thường và dấu `#` phía sau vẫn là comment; nhưng `drop_comments` lại tăng `brace = 1`, tắt tính năng cắt comment `#` (`not brace`), khiến dấu `'` trong comment mở nháy giả:
  - **PoC (`exit 0` trên cả `main` và worktree Guard):**
    ```bash
    echo \${ # '
    git reset --hard HEAD
    # ' }
    ```
- **Khuyến nghị sửa:** Kiểm tra `$` tại `i - 1` có số lượng dấu `\` đứng liền trước là số chẵn trước khi tăng `brace += 1`.

#### [S03-P0-04] Bypass bộ giải mã inline script (`python -c`, `node -e`, `ruby -e`) bằng cờ gộp (`-ISc`, `--eval=...`) và thiếu `solo_branch_rule` trong `git_in_literals`
- **Vị trí:** [`universal-agent-devkit/hooks/block-dangerous-git.sh#L623-L641`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L623-L641), [`#L716-L724`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/block-dangerous-git.sh#L716-L724); [`universal-agent-devkit/hooks/hardware_safety_gate.sh#L569`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hardware_safety_gate.sh#L569)
- **Cơ chế lỗi & PoC:** `inline_script_code()` chỉ bắt cờ đứng rời `t in ("-c", "-e", "--eval")`, bỏ lọt cờ gộp POSIX (`python3 -ISc "import os; os.system('git reset --hard')"`, `ruby -we "..."`, `node --eval="..."`). Ngoài ra `git_in_literals()` không gọi `solo_branch_rule` và `checkout_path_rule`, nên `python3 -c "import subprocess; subprocess.run(['git','checkout','-b','feat/x'])"` thoát kiểm tra.

#### [S03-P1-01] `worktree_guard.sh` fail-open khi `shell_writes.targets` trả về `None`, gọi `run_bodies=False` và bỏ qua mọi đường dẫn chứa `$`
- **Vị trí:** [`universal-agent-devkit/hooks/worktree_guard.sh#L443-L450`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/worktree_guard.sh#L443-L450); [`universal-agent-devkit/hooks/shell_writes.py#L61-L90`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/shell_writes.py#L61-L90), [`#L331-L355`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/shell_writes.py#L331-L355)
- **Khuyến nghị sửa:** Gọi `shell_writes.targets(cmd, run_bodies=True)`; khi `shell_writes.targets(cmd) is None`, fail-closed thay vì coi là `[]`; nội suy `$PWD` trước khi kiểm tra `_ok()`.

#### [S03-P1-02] `precode_gate.sh` kiểm tra `os.path.exists(path)` trên chuỗi chưa `norm(path)` và bỏ sót `"notebook_path"` ở fast-path Bash
- **Vị trí:** [`universal-agent-devkit/hooks/precode_gate.sh#L100`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/precode_gate.sh#L100), [`#L155-L171`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/precode_gate.sh#L155-L171), [`#L269-L273`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/precode_gate.sh#L269-L273), [`#L292-L299`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/precode_gate.sh#L292-L299)
- **Khuyến nghị sửa:** Dùng `target = norm(path)` cho `os.path.exists(target)` và `os.stat(target)`; bổ sung `notebook_path` vào regex grep dòng 100.

#### [S03-P1-03] `foreign_repo_gate.sh` không chặn tool `Bash` và bỏ qua đường dẫn tương đối (`../other-repo/file.py`)
- **Vị trí:** [`universal-agent-devkit/hooks/foreign_repo_gate.sh#L64-L72`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/foreign_repo_gate.sh#L64-L72)
- **Khuyến nghị sửa:** Chuẩn hóa đường dẫn tương đối qua `os.path.abspath(os.path.join(cwd, fp))` thay vì `if not os.path.isabs(fp): sys.exit(0)`.

#### [S03-P2-01..03 & S03-P3-01] Các lỗi cấp P2/P3 trong Slice 03
- **[S03-P2-01]** [`security_gate.sh#L187,L372,L525`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/security_gate.sh#L187): `ExportedComponentRule` chỉ kiểm tra trong từng hunk thay vì toàn thẻ XML `<activity>` trong `new_text`; `SecretKeyRule` có nguy cơ backtracking chậm trên chuỗi base64 dài không xuống dòng.
- **[S03-P2-02]** [`bash_write_ledger.sh#L53`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/bash_write_ledger.sh#L53): Grep chỉ tìm `"tool_name"` mà bỏ sót `"toolName"` (camelCase).
- **[S03-P2-03]** [`worktree_merge_gate.sh#L90-L148`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/worktree_merge_gate.sh#L90-L148): `extract_worktree_Command` chỉ neo ở đầu lệnh nên bỏ sót `cd .. && git worktree add ...`.
- **[S03-P3-01]** [`read_ledger.sh#L53`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/read_ledger.sh#L53): `SG_TREE` ghi đường dẫn tương đối làm trượt đối chiếu ở `precode_gate.sh`.

---

### Slice 04 — Stop Hooks, Session Lifecycle & Hook Harness (`8.368` dòng / 19 file)

**Phạm vi:** Toàn bộ 19 file trong `universal-agent-devkit/hooks/` liên quan đến Stop hooks, Session lifecycle và harness (`hooks.json`, `devkit_harness.py`, `devkit_profile.py`, `proof_gate.sh`, `regression_gate.sh`, `review_gate.sh`, `review_timing_guard.sh`, `test_evidence_gate.sh`, `testsourceset_gate.sh`, `claim_check.sh`, `comment_claim_guard.sh`, `churn_guard.sh`, `session_context.sh`, `prompt_context.sh`, `session_lock.sh`, `session_worktree.py`, `session_worktree.sh`, `agent_bridge.sh`, `user_project_bridge.sh`).

#### [S04-P0-01] Lỗi quy chụp nhầm quyền tác giả (`_names` thay vì `_writes`) trong `review_gate.sh` gây 43 lần auto-release và 10 lần block oan
- **Vị trí:** [`universal-agent-devkit/hooks/review_gate.sh#L332`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L332), [`#L522-L545`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L522-L545), [`#L590-L613`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L590-L613)
- **Cơ chế lỗi:** Ở dòng 601, khi xét một lệnh Bash trong cửa sổ `BASH_OPEN_MAX_S = 7200` giây (2 giờ) mà file có `_mt is not None`, code viết:
  ```python
  elif _mt is not None and _bstart - 2.0 <= _mt <= _bend + 2.0 and _names(_bcmd, _rel, _base):
      session_touched.add(_rel)
  ```
  Hàm `_names()` chỉ kiểm tra tên file có xuất hiện dưới dạng chuỗi trong câu lệnh hay không (thay vì gọi `_writes(_bcmd, _rel)`). Khi một lệnh chạy lâu hoặc một subagent chạy trong 2 giờ, bất kỳ lệnh chỉ đọc nào (`git diff`, `dotnet test`, `cat`) nhắc tới tên file đang dirty đều làm `session_touched.add(_rel)` kích hoạt oan!
- **Khuyến nghị sửa:** Đổi `_names(_bcmd, _rel, _base)` ở dòng 601 thành `_writes(_bcmd, _rel)` và giảm `BASH_OPEN_MAX_S` từ `7200` xuống `300` giây.

#### [S04-P0-02] `review_gate.sh` và `testsourceset_gate.sh` gọi `work_in_progress(d)` với `status_optional=False`, chặn oan các câu trả lời hội thoại giữa chừng
- **Vị trí:** [`universal-agent-devkit/hooks/review_gate.sh#L131`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L131); [`universal-agent-devkit/hooks/testsourceset_gate.sh#L183`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/testsourceset_gate.sh#L183); đối chiếu [`universal-agent-devkit/hooks/regression_gate.sh#L232`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/regression_gate.sh#L232)
- **Cơ chế lỗi:** `regression_gate.sh` đã dùng `devkit_harness.work_in_progress(d, status_optional=True)` (chỉ coi là lượt bàn giao khi phản hồi mở đầu bằng `XONG`), nhưng `review_gate.sh` và `testsourceset_gate.sh` vẫn gọi `work_in_progress(d)` mặc định (`status_optional=False`), khiến mọi câu trả lời tiến độ thông thường không có chữ `CHƯA XONG` đều bị ép chạy OCR review và test gate.
- **Khuyến nghị sửa:** Đổi cả hai sang `devkit_harness.work_in_progress(d, status_optional=True)`.

#### [S04-P0-03] `review_gate.sh` và `claim_check.sh` thiếu `session_worktree.py`, kiểm tra nhầm `main` thay vì worktree đang làm việc
- **Vị trí:** [`universal-agent-devkit/hooks/review_gate.sh#L43-L68`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L43-L68), [`#L140-L147`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L140-L147); [`universal-agent-devkit/hooks/claim_check.sh#L39-L51`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/claim_check.sh#L39-L51), [`#L279-L305`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/claim_check.sh#L279-L305)
- **Cơ chế lỗi:** Trong khi `proof_gate.sh`, `regression_gate.sh`, `test_evidence_gate.sh`, `testsourceset_gate.sh` đều giải phân giải `session_worktree.py` để chuyển `PROJECT_ROOT` sang worktree của phiên, `review_gate.sh` và `claim_check.sh` lại đọc thẳng `CLAUDE_PROJECT_DIR` (`main`), bỏ lọt toàn bộ diff trong worktree hoặc bắt nhầm file trên `main`.
- **Khuyến nghị sửa:** Thêm bước phân giải `session_worktree.py` vào đầu `review_gate.sh` và `claim_check.sh`.

#### [S04-P0-04] Nghẽn khóa 45 giây ở Stop hook & đứt gãy đồng bộ giữa `main` và worktree A15 (`agent-a89d86b8e80426e23`)
- **Vị trí:** [`universal-agent-devkit/bin/post-fix-gate.py#L5044-L5083`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/post-fix-gate.py#L5044-L5083); [`universal-agent-devkit/hooks/regression_gate.sh#L698-L779`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/regression_gate.sh#L698-L779)
- **Cơ chế lỗi:** Trên `main`, `regression_gate.sh` đặt `TEST_RUN_LOCK_WAIT_S=45` và chờ khóa ngay cả khi mọi suite đã được cache (`nothing_to_run == True`), đồng thời đánh dấu `STALE` giả khi `full_pass.json` được ghi lại hoặc khi working tree có file sửa dở (`exit 2`). Worktree A15 đã sửa các điểm này nhưng lại đang chứa bản cũ của `session_worktree.py` (trước commit `ebfe811b`). Cần rebase/cherry-pick cẩn thận khi merge A15.

#### [S04-P1-01] `test_evidence_gate.sh` bác bỏ `"gate-green"` ở Check 7 (`paired_red_green`) và tính nhầm sửa file test là sửa production code
- **Vị trí:** [`universal-agent-devkit/hooks/test_evidence_gate.sh#L881-L889`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/test_evidence_gate.sh#L881-L889), [`#L1108-L1116`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/test_evidence_gate.sh#L1108-L1116), [`#L1718-L1730`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/test_evidence_gate.sh#L1718-L1730)
- **Cơ chế lỗi:**
  1. Ở dòng 888, Check 2 chấp nhận `r[5] in ("green", "gate-green")`, nhưng ở dòng 1728 (Check 7 — `paired_red_green`), code lại viết `r[5] == "green"`, từ chối toàn bộ bản ghi `"gate-green"` do `post-fix-gate.py` sinh ra!
  2. Ở dòng 1109 và 1115, khi cập nhật `last_src_edit_idx` từ `git commit` hoặc `bash_write_ledger`, code quên kiểm tra `not is_test_path(fp)`, khiến việc commit/sửa một file test làm vô hiệu hóa kết quả chạy test vừa pass.

#### [S04-P1-02] `test_evidence_gate.sh` thiếu kiểm tra `work_in_progress(d)` trước `has_outcome` và trả `exit 2` cho thông báo nhắc nhở 1 lần
- **Vị trí:** [`universal-agent-devkit/hooks/test_evidence_gate.sh#L1787-L1808`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/test_evidence_gate.sh#L1787-L1808), [`#L1913-L1937`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/test_evidence_gate.sh#L1913-L1937)
- **Khuyến nghị sửa:** Thêm `not devkit_harness.work_in_progress(d, status_optional=True)` vào điều kiện kiểm tra `has_outcome`; không trả `exit 2` khi chỉ còn `lesson_reminder` hoặc `bug_link_reminder`.

#### [S04-P1-03] `review_gate.sh` quét nhầm file build `.agents/local/**/obj/*.cs` và `_covers_since` bác bỏ `--commit HEAD` khi có >1 commit mới
- **Vị trí:** [`universal-agent-devkit/hooks/review_gate.sh#L173-L195`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L173-L195), [`#L401-L408`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/review_gate.sh#L401-L408)
- **Khuyến nghị sửa:** Đổi bộ lọc `.agents/` ở dòng 182 thành `rel.startswith(".agents/") and not rel.startswith(".agents/devkit/")`; chấp nhận `mode == "commit" and target == head` trong `_covers_since`.

#### [S04-P1-04] `testsourceset_gate.sh` tạo `LOG_DIR` sai chỗ, thiếu kiểm tra symlink trên `SKIPPED_FILE` và rò rỉ FD 9 tại dòng 337
- **Vị trí:** [`universal-agent-devkit/hooks/testsourceset_gate.sh#L56-L65`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/testsourceset_gate.sh#L56-L65), [`#L163-L166`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/testsourceset_gate.sh#L163-L166), [`#L337`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/testsourceset_gate.sh#L337)
- **Khuyến nghị sửa:** Chuyển khối `mkdir -p "$LOG_DIR"` xuống sau khi đã phân giải `PROJECT_ROOT` từ `session_worktree.py`; thêm `[[ -f "$SKIPPED_FILE" && ! -L "$SKIPPED_FILE" ]]`; đóng FD 9 (`9>&-`) khi gọi tiến trình con.

#### [S04-P2-01..03 & S04-P3-01] Các lỗi cấp P2/P3 trong Slice 04
- **[S04-P2-01]** Fast-path `_SW_CWD` trong 4 Stop hooks chỉ khớp `*/.claude/worktrees/*`, bỏ sót worktree tạo bởi `agent-kit worktree add ../<repo>-<task>`.
- **[S04-P2-02]** [`session_worktree.py#L99`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/session_worktree.py#L99): `shlex.split` với `commenters="#"` cắt cụt đối số chứa `#` không có khoảng trắng đứng trước (như URL hoặc selector).
- **[S04-P2-03]** [`proof_gate.sh#L186,L251`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/proof_gate.sh#L186): `git status --porcelain` không truyền `-uall` nên gộp thư mục untracked mới thành 1 dòng thư mục.
- **[S04-P3-01]** [`comment_claim_guard.sh#L230`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/comment_claim_guard.sh#L230): Bỏ qua việc kiểm tra comment bịa đặt trên file mới tinh được tạo bằng `Write`.

---

### Slice 05 — Git, Worktree Sandbox, Parallel Lanes & Host Adapters (`5.582` dòng / 12 file)

**Phạm vi:**
- [`universal-agent-devkit/scripts/git/worktree.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py) (2.825 dòng)
- [`universal-agent-devkit/scripts/git/worktree_sandbox.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree_sandbox.py) (398 dòng)
- [`universal-agent-devkit/scripts/git/githooks.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/githooks.sh) (136 dòng)
- [`universal-agent-devkit/scripts/git/git-pre-commit.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/git-pre-commit.sh) (66 dòng)
- [`universal-agent-devkit/scripts/git/git-commit-msg.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/git-commit-msg.sh) (98 dòng)
- [`universal-agent-devkit/scripts/git/backup_conflict.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/backup_conflict.sh) (1.031 dòng)
- [`universal-agent-devkit/scripts/governance/lane_plan.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/lane_plan.py) (561 dòng)
- [`universal-agent-devkit/adapters/setup_claude.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_claude.sh), [`setup_codex.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_codex.sh), [`setup_cursor.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_cursor.sh), [`setup_gemini.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_gemini.sh), [`completions/agent-kit.bash`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/completions/agent-kit.bash) (467 dòng)

#### [S05-P0-01] `worktree.py` (`cmd_gc`) xóa mất dữ liệu chưa commit khi nội dung file trùng với một blob lịch sử bất kỳ hoặc là symlink
- **Vị trí:** [`universal-agent-devkit/scripts/git/worktree.py#L2454-L2543`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L2454-L2543), [`#L2602-L2637`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L2602-L2637)
- **Cơ chế lỗi:**
  1. `_gc_unique(wt, blobs)` quyết định một file đã sửa/untracked có cần giữ lại hay không bằng cách kiểm tra `sha not in blobs`, trong đó `blobs` là tập hợp **toàn bộ git object blob trong lịch sử repo** (`git rev-list --objects --all`). Nếu lập trình viên khôi phục nội dung một file về phiên bản cũ hoặc tạo file mới có nội dung trùng một file từng tồn tại (ví dụ `__init__.py` rỗng), `sha not in blobs` trả về `False` và `cmd_gc` xóa thẳng worktree bằng `_rmtree` mà không lưu patch!
  2. Dòng 2529 bỏ qua mọi symlink (`if os.path.islink(full): continue`), nên symlink mới tạo không bao giờ được bảo vệ.
  3. `_gc_young(wt)` (dòng 2454) chỉ kiểm tra `st_mtime` của thư mục gốc `wt`, không kiểm tra mtime của các file trong thư mục con (như `src/foo.py`), nên worktree đang được sửa ở thư mục con vẫn bị coi là đã cũ (>120s) và bị thu dọn.
- **Khuyến nghị sửa:** Bảo vệ mọi worktree có `git status --porcelain` khác rỗng (so sánh với `HEAD` của chính worktree đó thay vì tập `blobs` toàn lịch sử).

#### [S05-P0-02] `_automerge_locked()` chạy `git commit --no-edit` trước `_commit_pending()`, bỏ qua kiểm tra secret và symlink
- **Vị trí:** [`universal-agent-devkit/scripts/git/worktree.py#L2163-L2175`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L2163-L2175)
- **Cơ chế lỗi:** Khi tiếp tục một worktree đang ở trạng thái `busy == "merge"`, dòng 2167 chạy thẳng `git commit --no-edit` để chốt toàn bộ các file đang staged trong index **trước khi** gọi `_commit_pending(wt)` ở dòng 2175 (nơi đặt bộ lọc `_secret_like`, kiểm tra symlink và dọn `BOOKKEEPING`).
- **Khuyến nghị sửa:** Chạy kiểm tra `_secret_like`, symlink và dọn `BOOKKEEPING` trên các file staged trước khi gọi `git commit --no-edit`.

#### [S05-P0-03] Lỗ hổng ghi đè file tùy ý qua symlink thư mục cha trong `backup_conflict.sh` (`restore_old_backups --apply`)
- **Vị trí:** [`universal-agent-devkit/scripts/git/backup_conflict.sh#L500-L525`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/backup_conflict.sh#L500-L525), [`#L967-L995`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/backup_conflict.sh#L967-L995)
- **Cơ chế lỗi:** Trong `restore_old_backups()`, nếu thư mục cha `$(dirname "$dst")` là một symlink trỏ vào `$DEVKIT_ROOT` (do `install.sh` tạo như `.agents/skills`), lệnh `mv -- "$f" "$dst"` đi xuyên qua symlink và ghi đè trực tiếp lên file gốc trong `$DEVKIT_ROOT`.
- **Khuyến nghị sửa:** Gọi `_backup_assert_safe_dir "$(dirname "$dst")" "$root"` trước khi `mv`.

#### [S05-P0-04] `worktree_sandbox.py` (`cleanup_sandbox`) xóa thư mục `shutil.rmtree(s_path)` trước khi kiểm tra commit chưa merge (`ahead`)
- **Vị trí:** [`universal-agent-devkit/scripts/git/worktree_sandbox.py#L291-L316`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree_sandbox.py#L291-L316), [`#L369-L373`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree_sandbox.py#L369-L373)
- **Cơ chế lỗi:** `cleanup_sandbox()` gọi `shutil.rmtree(s_path)` ở dòng 301 **trước khi** chạy `git rev-list --count HEAD..{branch_name}` ở dòng 309, làm mất trắng toàn bộ file chưa commit trong sandbox. Hơn nữa ở dòng 310, nếu `git rev-list` lỗi và trả về `ahead == ""`, nhánh `else` chạy `git branch -D` xóa nốt các commit chưa merge!
- **Khuyến nghị sửa:** Kiểm tra `git status --porcelain` trên `s_path` và `ahead == "0"` **trước khi** xóa thư mục và nhánh.

#### [S05-P1-01..06] Các lỗi cấp P1 trong Slice 05
- **[S05-P1-01]** [`worktree.py#L2249-L2317`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L2249-L2317): Fast-forward `git merge --ff-only` trên `main` không lấy `_test_run_lock(main)`, gây race condition với tiến trình gate đang chạy trên `main`.
- **[S05-P1-02]** [`worktree.py#L2581-L2591`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L2581-L2591): `devkit-gc.lock` dùng `open(lock_path, "w")` + `flock` chặn vô hạn thay vì `_lock_file` (`O_NONBLOCK | O_NOFOLLOW`).
- **[S05-P1-03]** [`worktree_sandbox.py#L63-L178`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree_sandbox.py#L63-L178): `.worktreeinclude` cho phép `symlinks=True` và copy cả file secret chưa có trong `.gitignore`, đồng thời tạo `.sandbox-env.sh` làm dirty git tree.
- **[S05-P1-04]** [`githooks.sh#L64-L82`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/githooks.sh#L64-L82): `CHAIN_LINE` gọi `.agents/devkit/scripts/git/git-pre-commit.sh` với `|| true` khi file không tồn tại; ở chế độ `copy` (`install.sh` không copy `scripts/`), git hook bị vô hiệu hóa âm thầm 100%.
- **[S05-P1-05]** [`backup_conflict.sh#L229,L613,L631`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/backup_conflict.sh#L229): Thiếu `|| return 1` sau `_backup_assert_safe_dir` trong `devkit_place_file` và `devkit_place_skills`.
- **[S05-P1-06]** [`adapters/setup_codex.sh#L1-L40`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_codex.sh#L1-L40) & [`setup_cursor.sh#L1-L41`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/adapters/setup_cursor.sh#L1-L41): Không gọi `devkit_place_skills`, khiến Codex và Cursor thiếu `.agents/skills`.

#### [S05-P2-01..05 & S05-P3-01..02] Các lỗi cấp P2/P3 trong Slice 05
- **[S05-P2-01]** [`worktree.py#L140,L1318,L2762`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/worktree.py#L140): `UNITY_LOCK_DIRS` thiếu `"Bee"` (Unity 6); `cmd_heal` thiếu `copy_unity_library(main, wt)`; `_commit_pending` commit cả file xung đột `_GENERATED_KEYS`.
- **[S05-P2-02]** [`lane_plan.py#L62,L486`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/lane_plan.py#L62): `os.open` không truyền mode tạo file `0o644` (mặc định `0o777`); danh sách `SHARED` thiếu 3 file bookkeeping so với `worktree.py`.
- **[S05-P2-03..05 & P3-01..02]** [`backup_conflict.sh#L466`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/backup_conflict.sh#L466) (`rmdir` thiếu `|| true` dưới `set -e`), [`git-pre-commit.sh#L54`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/git/git-pre-commit.sh#L54) (thiếu mẫu `0:clean`), [`completions/agent-kit.bash`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/completions/agent-kit.bash) (thiếu subcommands `trunk`, `gc`, `heal`, `lanes`).

---

### Slice 06 — Governance, Context Sync, Memory & Nightly Maintenance (`6.554` dòng / 27 file)

**Phạm vi:** 22 file trong `universal-agent-devkit/scripts/governance/` và 5 file trong `universal-agent-devkit/scripts/context/`.

#### [S06-P0-01] Deadlock kép (Catch-22) trong `nightly.py` làm tê liệt hoàn toàn việc trả nợ RED-proof trên mọi repo bật Trunk Mode
- **Vị trí:** [`universal-agent-devkit/scripts/governance/nightly.py#L120-L148`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L120-L148), [`#L165-L185`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L165-L185); đối chiếu [`universal-agent-devkit/bin/regression_checklist.py#L418-L433`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/bin/regression_checklist.py#L418-L433)
- **Cơ chế lỗi:**
  1. Trong `nightly.py`, `checkout_busy(repo)` gọi `session_lock.py --status`. Khi repo bật Trunk Mode (mặc định trên toàn bộ 5 repo), `session_lock.py --status` trả về `exit 5` (`"trunk mode: main chỉ nhận merge"`), khiến `checkout_busy()` kết luận repo đang bận và **bỏ qua 100% bước chạy `red_proof.py`**!
  2. Ngược lại, nếu chạy `nightly.py` bên trong một linked worktree để tránh `exit 5`, thì `regression_checklist.py:skip_bookkeeping()` lại từ chối ghi sổ vì `git-dir != git-common-dir`.
  3. Trong khi đó `red_proof.py` vốn đã chạy tách biệt hoàn toàn trên một detached worktree tạm ở `/tmp/red-proof-*` (khi dùng cờ `--detached`) và chỉ cập nhật file trạng thái `.agents/` ở repo chính!
- **Khuyến nghị sửa:** Trong `nightly.py:checkout_busy()`, coi mã thoát `rc == 5` (Trunk Mode, không có phiên giữ khóa độc quyền) là **không bận** (`return None`), và truyền cờ `--detached` khi gọi `red_proof.py`.

#### [S06-P1-01] `nightly.py` bỏ qua `checkout_busy()` khi chạy `--all` (`named=False`) và gọi `red_proof.py` không có `timeout`
- **Vị trí:** [`universal-agent-devkit/scripts/governance/nightly.py#L141`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L141), [`#L179`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L179)
- **Cơ chế lỗi:** Ở dòng 141, `if named:` khiến việc chạy `nightly.py --all` (`named=False`) **không hề gọi `checkout_busy()`** ở bước đầu! Đồng thời lệnh `subprocess.run` gọi `red_proof.py` ở dòng 179 không có `timeout=`.

#### [S06-P1-02] `devkit_clean.py` không được gắn vào `nightly.py` / `scratch_cleanup.py`, bỏ sót `.jsonl` và xóa mất `.lock` đang sống khi `--days 0`
- **Vị trí:** [`universal-agent-devkit/scripts/governance/devkit_clean.py#L73-L112`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/devkit_clean.py#L73-L112)
- **Cơ chế lỗi:** Giải thích vì sao `.claude/audit-gate` phình tới 15–30 MB mỗi repo:
  1. `devkit_clean.py` không được tự động gọi từ `nightly.py` hay `scratch_cleanup.py`.
  2. `prune_audit_gate()` chỉ dọn `.log`, `.tmp`, `.bak`, bỏ sót các file `.jsonl` lớn (`surfaced.jsonl` 10 MB, `bash_write_ledger.tsv`, `session_worktree/`).
  3. Khi chạy `--days 0`, vòng lặp xóa luôn cả các file `.lock` (`test_run.lock`) và trạng thái phiên đang hoạt động.

#### [S06-P1-03] `fold_agent_file.py` và `context_sync.py` kiểm tra bao hàm bằng phép `in` toàn chuỗi, làm nhân đôi nội dung `AGENTS.md` (>42 KB)
- **Vị trí:** [`universal-agent-devkit/scripts/governance/fold_agent_file.py#L37`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/fold_agent_file.py#L37); [`universal-agent-devkit/scripts/governance/context_sync.py#L126`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/context_sync.py#L126)
- **Cơ chế lỗi:** `if body in target_text:` yêu cầu toàn bộ `CLAUDE.md` phải khớp từng ký tự liên tiếp trong `AGENTS.md`. Chỉ cần sửa 1 dòng trong `AGENTS.md`, lần chạy sau sẽ nối thêm toàn bộ `CLAUDE.md` vào cuối `AGENTS.md` một lần nữa.
- **Khuyến nghị sửa:** Bọc phần được fold bằng cặp thẻ đánh dấu `<!-- folded-from:CLAUDE.md:start -->` ... `<!-- folded-from:CLAUDE.md:end -->` để thay thế idempotent.

#### [S06-P1-04] `antigravity_collab_hint()` trong `enrich_context.py` là dead code 100% do sai tên hằng số Intent
- **Vị trí:** [`universal-agent-devkit/scripts/context/enrich_context.py#L156-L202`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/enrich_context.py#L156-L202), [`#L961`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/enrich_context.py#L961)
- **Cơ chế lỗi:** Bộ phân loại `INTENT_PATTERNS` sinh ra `"ARCHITECTURE_REFACTOR"`, `"SECURITY"`, `"DEPRECATION_MIGRATION"`, nhưng dòng 961 của `antigravity_collab_hint()` lại kiểm tra `intent in ("ARCHITECTURE_CHANGE", "SECURITY_AUDIT", "MIGRATION")` — 3 chuỗi này không hề tồn tại trong codebase!
- **Khuyến nghị sửa:** Đổi dòng 961 thành `intent in ("ARCHITECTURE_REFACTOR", "SECURITY", "DEPRECATION_MIGRATION")`.

#### [S06-P1-05] `relink_check.py` và `enrich_context.py` bỏ qua danh sách `"skills"` của `profile.json`, nạp tràn toàn bộ 21 skills vào mọi repo
- **Vị trí:** [`universal-agent-devkit/scripts/governance/relink_check.py#L54-L60`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/relink_check.py#L54-L60); [`universal-agent-devkit/scripts/context/enrich_context.py#L472`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/enrich_context.py#L472)
- **Khuyến nghị sửa:** Dùng `profile_skills.py:wanted_skills()` để chỉ symlink và nạp các skill thuộc profile đang kích hoạt.

#### [S06-P1-06] `hardware_boundaries.py` dịch glob `**/` thành regex bắt buộc có `/`, bỏ lọt hoàn toàn các file ở thư mục gốc repo
- **Vị trí:** [`universal-agent-devkit/scripts/context/hardware_boundaries.py#L53-L61`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/hardware_boundaries.py#L53-L61)
- **Cơ chế lỗi:** Mẫu `**/*ble*.py` được dịch thành `^.*/[^/]*ble[^/]*\.py$`, không khớp với `ble_service.py` nằm ở thư mục gốc của repo.
- **Khuyến nghị sửa:** Dịch `**/` thành `(?:.*/)?`.

#### [S06-P1-07] `token_cost_tracker.py` thiếu bảng giá Claude 4.x (`opus-4-6`, `sonnet-4-6`) và tính trùng 2 lần `cache_creation_input_tokens`
- **Vị trí:** [`universal-agent-devkit/scripts/governance/token_cost_tracker.py#L21-L55`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/token_cost_tracker.py#L21-L55), [`#L221-L234`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/token_cost_tracker.py#L221-L234)
- **Cơ chế lỗi:** Khi log có `cache_creation.ephemeral_1h_input_tokens = X` nhưng không có khóa `ephemeral_5m_input_tokens`, biểu thức `c5 = cc.get("ephemeral_5m_input_tokens", cw)` gán `c5 = cw = X` rồi cộng `c5 * price_5m + c1 * price_1h`, tính tiền gấp đôi!

#### [S06-P2-01..09 & S06-P3-01..04] Các lỗi cấp P2/P3 trong Slice 06
- **[S06-P2-01]** [`enrich_context.py#L18-L29`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/enrich_context.py#L18-L29), [`#L1096`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/enrich_context.py#L1096): `find_project_root` trả về `None` gây `TypeError` khi chạy ngoài repo; `dedupe_session` lọc mất dòng `Bắt buộc [Claude ↔ Antigravity]` ở các prompt tiếp theo.
- **[S06-P2-02]** [`context_sync.py#L185`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/context_sync.py#L185): Dùng tên file tạm cố định `.tmp` gây race condition khi nhiều tiến trình cùng sync.
- **[S06-P2-03]** [`scratch_cleanup.py#L32,L59`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/scratch_cleanup.py#L32): Chỉ quét 1 thư mục `claude_home()` thay vì cả `~/.claude` và `~/.claude-work`.
- **[S06-P2-04..09 & P3-01..04]** [`rules_index.py#L33`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/context/rules_index.py#L33) & [`index_memory.py#L59`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/index_memory.py#L59) (cắt cụt giá trị YAML frontmatter có dấu `:`), [`devkit_uninstall.py#L540`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/devkit_uninstall.py#L540), [`merge_json.py#L182`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/merge_json.py#L182), [`nightly.py#L358`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/nightly.py#L358), [`memory_stats.py#L218`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/memory_stats.py#L218), [`claude_memory.py#L96`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/claude_memory.py#L96), [`stop_hook_times.py#L78`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/stop_hook_times.py#L78), [`stop_replay.py#L275`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/stop_replay.py#L275).

---

### Slice 07 — Linters, Testing Harnesses, Metrics, Workflows & Dashboard (`7.674` dòng / 18 file)

**Phạm vi:** `scripts/linters/*`, `scripts/testing/*`, `skills/devkit-audit/scripts/devkit_metrics.py`, `workflows/*`, `dashboard/*`.

#### [S07-P0-01] Lỗi ghi đè biến `patch` (Variable Shadowing) trong `red_proof.py` làm hỏng 100% bằng chứng RED ở chế độ `revert`
- **Vị trí:** [`universal-agent-devkit/scripts/testing/red_proof.py#L569`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L569), [`#L673`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L673), [`#L748-L755`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L748-L755)
- **Cơ chế lỗi:** Hàm `prove_one(..., patch: Path | None = None)` nhận tham số `patch` ở dòng 569. Thế nhưng ở dòng 673 (bên trong nhánh `elif mode == "revert":`), code lại gán `patch = git(work, "diff", "--", *prod).stdout` (kiểu `str`). Đến dòng 748–755, câu lệnh `if mode == "patch" and patch:` bị sai logic và `"patch": str(patch) if patch else None` ghi toàn bộ nội dung unified diff dài hàng chục KB vào trường đường dẫn `meta["patch"]` thay vì `None`, đồng thời tính sai `files` hash map!
- **Khuyến nghị sửa:** Đổi tên biến cục bộ ở dòng 673 thành `rev_diff = git(work, "diff", "--", *prod).stdout`.

#### [S07-P1-01] `red_proof.py` (`narrowed`) nối chuỗi `tests` không bọc `shlex.quote` và chặn nhầm lệnh có `${VAR}`
- **Vị trí:** [`universal-agent-devkit/scripts/testing/red_proof.py#L510-L551`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L510-L551)
- **Cơ chế lỗi:** Dòng 514 chặn mọi lệnh test có ký tự `{` (làm gãy các lệnh hợp lệ dùng `${ENV_VAR}`), trong khi các dòng 521, 526, 531 lại nối thẳng `' '.join(tests)` vào chuỗi chạy `bash -c` mà không qua `shlex.quote(t)`.

#### [S07-P1-02] Rò rỉ tiến trình con và thư mục `/tmp/red-proof-*` khi nhận tín hiệu `SIGINT`/`SIGTERM` trong `red_proof.py` & `stale_rerun.py`
- **Vị trí:** [`universal-agent-devkit/scripts/testing/red_proof.py#L310-L335`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L310-L335), [`#L554-L566`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L554-L566); [`universal-agent-devkit/scripts/testing/stale_rerun.py#L81-L115`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/stale_rerun.py#L81-L115)
- **Cơ chế lỗi:** Khi tiến trình cha nhận `SIGTERM` (do timeout của caller hoặc người dùng hủy), Python kết thúc ngay mà không chạy khối `finally` để gọi `os.killpg(p.pid, signal.SIGKILL)` và `git worktree remove --force`, để lại các tiến trình Gradle/Unity/pytest chạy mồ côi.
- **Khuyến nghị sửa:** Đăng ký `signal.signal(signal.SIGTERM, ...)` để chuyển thành `KeyboardInterrupt` nhằm kích hoạt khối `finally`.

#### [S07-P1-03] `red_proof.py` lỗi đường dẫn tương đối với `--patch` khi chạy trên detached worktree và lỗi `.split()` trên đường dẫn có dấu cách
- **Vị trí:** [`universal-agent-devkit/scripts/testing/red_proof.py#L617`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L617), [`#L669`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L669), [`#L801`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L801), [`#L848`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/red_proof.py#L848)
- **Khuyến nghị sửa:** `args.patch.resolve()` trước khi tạo detached worktree; dùng `.splitlines()` thay cho `.split()` ở dòng 617; dùng `git checkout <parent> -- <deleted_files>` thay vì `git show parent:f` khi file được thêm mới trong commit.

#### [S07-P1-04] `stale_rerun.py` bị TOCTOU giữa `watched_mtimes()` và `ts`, đồng thời bị chặn trên `main` khi bật Trunk Mode
- **Vị trí:** [`universal-agent-devkit/scripts/testing/stale_rerun.py#L144-L185`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/stale_rerun.py#L144-L185)
- **Khuyến nghị sửa:** Ghi nhận `run_started_at = int(time.time())` **trước khi** chạy test để gán vào `r["ts"]`.

#### [S07-P1-05] `assertion_lint.py` bị qua mặt bởi chữ `"assert"` trong comment/string, bỏ sót `async def test_*` và lỗi hàm Kotlin expression-body (`@Test fun f() = ...`)
- **Vị trí:** [`universal-agent-devkit/scripts/linters/assertion_lint.py#L18-L42`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/assertion_lint.py#L18-L42), [`#L70-L120`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/assertion_lint.py#L70-L120), [`#L173-L195`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/assertion_lint.py#L173-L195)
- **Cơ chế lỗi:** `_ASSERT` quét trên văn bản thô chưa xóa comment/string (nên `# TODO: assert later` vẫn pass); `_PY_DEF` thiếu `(?:async\s+)?def`; `_brace_functions` đi tìm dấu `{` đầu tiên sau `@Test fun foo() = runTest` nên nuốt nhầm thân của hàm tiếp theo.

#### [S07-P1-06] `lint_unity_gc.py` miễn trừ nhầm cấp phát mảng `new Vector3[N]` / `new RaycastHit[N]` trên heap và rò trạng thái khi gặp `abstract void Update();`
- **Vị trí:** [`universal-agent-devkit/scripts/linters/lint_unity_gc.py#L67-L95`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/lint_unity_gc.py#L67-L95)
- **Cơ chế lỗi:** Trong C#, `new Vector3(x, y, z)` là struct trên stack, nhưng `new Vector3[100]` hay `new RaycastHit[16]` là cấp phát mảng `System.Array` trên **Managed Heap** gây GC spike! Regex `new\s+([A-Z]\w*)\s*[\(\[\{]` gộp chung cả `(` và `[`, nên miễn trừ nhầm mảng struct trong `Update()`.

#### [S07-P1-07..10] Các lỗi cấp P1 khác trong Slice 07
- **[S07-P1-07]** [`devkit_metrics.py#L313-L325`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/devkit-audit/scripts/devkit_metrics.py#L313-L325): Truyền `--repo` không tồn tại vẫn trả về `exit 0` với toàn bộ số liệu bằng `0`.
- **[S07-P1-08]** [`fix-evidence-driver.mjs#L544,L970`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/workflows/fix-evidence-driver.mjs#L544) & [`multi-lens-audit.js#L1261,L1267`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/workflows/multi-lens-audit.js#L1261): Dùng `.sort((a, b) => a.localeCompare(b))` thay vì ASCII code-point `.sort()`, làm lệch thứ tự và SHA-256 fingerprint so với Python `sorted()`.
- **[S07-P1-09]** [`multi-lens-audit.js#L519`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/workflows/multi-lens-audit.js#L519): Hardcode `subagent_type: "exampleapp-code-reviewer"` không tồn tại.
- **[S07-P1-10]** [`dashboard/collect_rows.py#L184-L195`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/dashboard/collect_rows.py#L184-L195): Khi `git rev-parse --git-path hooks/pre-commit` thất bại và trả về `""`, `Path(repo) / ""` chính là thư mục `repo` (luôn có bit thực thi `+x`), khiến `git_hook_exists()` báo `True` giả!

#### [S07-P2-01..09 & S07-P3-01..03] Các lỗi cấp P2/P3 trong Slice 07
- [`capture_3d_proof.py#L35`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/capture_3d_proof.py#L35) (`MIN_DISTINCT_ROWS = 8` được khai báo nhưng không bao giờ được kiểm tra trong `validate_png`), [`proof_phash.py#L58`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/proof_phash.py#L58) (`zlib.decompress` không giới hạn `max_length`), [`lint_compose_stability.py#L62`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/lint_compose_stability.py#L62), [`hardware_source_lint.py#L84`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/hardware_source_lint.py#L84), [`wiring_pin.py#L44`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/linters/wiring_pin.py#L44), [`run_unity_tests.py#L112`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/testing/run_unity_tests.py#L112).

---

### Slice 08 — Rules, Profiles, Skills, Templates & Docs Consistency (`6.657` dòng / 51 file)

**Phạm vi:** `AGENTS.md`, `rules/*.md`, `profiles/*/profile.json`, `profiles/game/{hooks,scripts}/*`, `templates/*`, và 15 file `skills/*/SKILL.md`.

#### [S08-P0-01] Mâu thuẫn trực diện giữa `AGENTS.md` / `handover_rule.vi.md` / `skills` (cấm tự commit/push, bắt `CHỜ DUYỆT`) và `rules/essentials.md` / `core-rules.md` (bắt buộc tự commit & push không hỏi)
- **Vị trí:** [`universal-agent-devkit/AGENTS.md#L84`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/AGENTS.md#L84), [`#L162`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/AGENTS.md#L162); [`universal-agent-devkit/templates/handover_rule.vi.md#L39`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/templates/handover_rule.vi.md#L39); [`universal-agent-devkit/skills/tdd-workflow/SKILL.md#L70`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/tdd-workflow/SKILL.md#L70); [`universal-agent-devkit/skills/verification-before-completion/SKILL.md#L45`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/verification-before-completion/SKILL.md#L45) **VS** [`universal-agent-devkit/rules/essentials.md#L68-L76`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/rules/essentials.md#L68-L76) & [`universal-agent-devkit/rules/core-rules.md#L4`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/rules/core-rules.md#L4)
- **Cơ chế lỗi:** `AGENTS.md` dòng 84 ghi *"Gate 4 — Pre-Commit / Push / PR: Full STOP — Wait for explicit user approval"*, `handover_rule.vi.md` dòng 39 ghi *"Dừng lại chờ lệnh: Không tự ý chạy git commit hay git push"*, trong khi `essentials.md` dòng 68 lại ghi *"Git — commit and push yourself: a finished task is committed and pushed without asking"*. Khi một dự án đồng thời có quy tắc dự án cấm tự commit (như quy tắc FinOS Solo Dev), sự xung đột này làm Agent bối rối giữa hai mệnh lệnh trái ngược.
- **Khuyến nghị sửa:** Đồng bộ nhất quán theo đúng thứ tự ưu tiên: mặc định tuân thủ quy tắc cấp dự án (nếu dự án cấm tự commit thì dừng chờ lệnh; nếu dự án ủy quyền tự động thì commit/push sau khi gate `--full` exit 0) và xóa các câu mẫu mâu thuẫn trong `AGENTS.md` §3 / `handover_rule.vi.md` / `tdd-workflow` / `verification-before-completion`.

#### [S08-P0-02] Lỗ hổng Arithmetic Injection, crash biến chưa khai báo trên `-h`/`--help` và timeout âm trong `unity-bot-marathon.sh`
- **Vị trí:** [`universal-agent-devkit/profiles/game/scripts/unity-bot-marathon.sh#L26-L46`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/scripts/unity-bot-marathon.sh#L26-L46)
- **Cơ chế lỗi:**
  1. Dòng 26–29 chỉ bắt `${1:-}` với `*-*` mà không bắt `-h`/`--help`, dẫn tới `END_LEVEL` chưa được gán và script nổ `END_LEVEL: unbound variable` ở dòng 35 dưới `set -euo pipefail`.
  2. Biểu thức `$((END_LEVEL - START_LEVEL + 1))` trong Bash đánh giá nội dung biến như biểu thức số học (arithmetic evaluation), cho phép thực thi lệnh tùy ý nếu đầu vào không được kiểm tra `^[0-9]+$`.
  3. Nếu truyền khoảng ngược (ví dụ `50-10`), `LEVEL_COUNT` âm khiến `TIMEOUT_SEC` âm và `kill -9` bắn ngay ở giây thứ 0.

#### [S08-P0-03] Vòng lặp vô tận 100% CPU khi thiếu đối số cờ và lỗi đụng độ tiền tố `pgrep` giữa các worktree trong `unity-batch.sh`
- **Vị trí:** [`universal-agent-devkit/profiles/game/scripts/unity-batch.sh#L56-L66`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/scripts/unity-batch.sh#L56-L66), [`#L114`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/scripts/unity-batch.sh#L114)
- **Cơ chế lỗi:**
  1. Dưới `set -uo pipefail` (không có `-e`), khi gọi `unity-batch.sh editmode --filter` (thiếu giá trị sau `--filter`), lệnh `shift 2` khi `$# == 1` thất bại và giữ nguyên `$# == 1`, làm vòng lặp `while [[ $# -gt 0 ]]` treo cứng 100% CPU vô tận!
  2. Dòng 114 dùng `pgrep -fi -- "projectpath[= ]*$ROOT"` không có neo kết thúc từ: khi chạy song song trên worktree `/Volumes/Data/MyGame-wt1`, biểu thức của `/Volumes/Data/MyGame` khớp nhầm tiền tố và chặn worktree gốc.

#### [S08-P1-01] Lỗi lệch pha luồng NUL (`git status -z`) khi đổi tên file (`R`) ra ngoài `Assets/` trong `validate-assets.sh`
- **Vị trí:** [`universal-agent-devkit/profiles/game/hooks/validate-assets.sh#L93-L120`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/hooks/validate-assets.sh#L93-L120)
- **Cơ chế lỗi:** Trong `git status -z`, bản ghi `R` hoặc `C` luôn gồm **2 trường NUL liên tiếp** (`XY new_path\0old_path\0`). Nhưng ở dòng 99, script kiểm tra `if [[ "$path" != Assets/* ]]; then continue; fi` **trước khi** đọc trường `orig_path` thứ hai ở dòng 102! Nếu một file được `git mv` từ `Assets/Foo.cs` ra ngoài `Assets/`, `orig_path` không được tiêu thụ khỏi stdin mà biến thành bản ghi `entry` tiếp theo, làm hỏng toàn bộ phần còn lại của luồng đọc!

#### [S08-P1-02..07] Các lỗi cấp P1 khác trong Slice 08
- **[S08-P1-02]** Đảo ngược thứ tự ưu tiên giữa [`AGENTS.md#L127-L133`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/AGENTS.md#L127-L133) (`core-rules.md` > `.agents/local/rules/`) và [`rules/essentials.md#L13-L19`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/rules/essentials.md#L13-L19) (`.agents/local/rules/` > `essentials.md`).
- **[S08-P1-03]** Tài liệu [`AGENTS.md#L190`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/AGENTS.md#L190), [`rules/core-rules.md#L22`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/rules/core-rules.md#L22) và [`skills/devkit-audit/SKILL.md#L22`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/devkit-audit/SKILL.md#L22) chưa cập nhật mã thoát `exit 5` của Trunk Mode.
- **[S08-P1-04]** [`rules/essentials.md#L111`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/rules/essentials.md#L111) và [`skills/fixbugs/SKILL.md#L97`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/fixbugs/SKILL.md#L97) chưa ghi rõ hành xử khi gate trả về `exit 5` (deferred/impacted) và khi nào dùng `--force-full`.
- **[S08-P1-05]** [`hooks/proof_gate.sh#L408`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/proof_gate.sh#L408) gọi `first_app_source_edit_time()` thiếu đối số `prof`, khiến nhánh miễn trừ `blender_only_turn` trong `proof_gate.sh` chết cứng (luôn đòi ảnh `proof-*.png` cho file `.blend`).
- **[S08-P1-06]** 3 file template cũ ([`claude_injection_block.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/templates/claude_injection_block.md), [`handover_rule.vi.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/templates/handover_rule.vi.md), [`acceptance_report.template.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/templates/acceptance_report.template.md)) đã lỗi thời so với `agents_injection_block.md`.
- **[S08-P1-07]** Nhân bản nguyên văn 8 file `rules/*-rules.md` sang `profiles/*/rules/*-rules.md` (122 KB trùng lặp) không có kiểm tra drift.

#### [S08-P2-01..05 & S08-P3-01] Các lỗi cấp P2/P3 trong Slice 08
- [`unity-bot-marathon.sh#L75`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/scripts/unity-bot-marathon.sh#L75) (`won=0/0` vẫn pass), [`render_game_prop.py#L243`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/profiles/game/scripts/render_game_prop.py#L243) (`angle="side"` đặt camera giống hệt `"iso"` 45°), [`templates/claude_settings.json`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/templates/claude_settings.json) vs [`hooks/hooks.json`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/hooks/hooks.json) (thiếu `MultiEdit`/`NotebookEdit` và `timeout` trên `block-dangerous-git.sh`).

---

### Slice 09 — Antigravity PM MCP Server (`5.821` dòng / 21 file)

**Phạm vi:** Toàn bộ 21 file JS trong `mcp-servers/antigravity-pm-mcp/bin/` và `src/`.

#### [S09-P0-01] Bypass hoàn toàn `forbiddenPaths` và kiểm tra thứ tự thời gian (`lastChangeAtOf`) nếu Worker không tự khai báo file trong `result.files_changed`
- **Vị trí:** [`mcp-servers/antigravity-pm-mcp/src/policy.js#L254-L264`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/policy.js#L254-L264), [`src/tasks.js#L655-L657`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tasks.js#L655-L657), [`src/worktree.js#L81`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/worktree.js#L81), [`#L130-L134`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/worktree.js#L130-L134)
- **Cơ chế lỗi:** Cả `fileCamDungTheoTask()` và `fileCuaTask()` đều chỉ coi một file nằm ngoài `scopeFiles` là của task nếu Worker **tự khai báo** đường dẫn đó trong `result.files_changed` (`claimed`). Nếu một Worker sửa lén file trong `forbiddenPaths` (như `.env`, `build.gradle`) hoặc sửa code production sau khi chạy test nhưng **không liệt kê** vào `result.files_changed`, `fileCamDungTheoTask()` trả về `[]` và `lastChangeAtOf()` bỏ qua hoàn toàn file đó!
- **Khuyến nghị sửa:** Đối chiếu với snapshot `task.baselineDirty` lúc `pm_assign`: mọi file mới xuất hiện hoặc có `mtimeMs > baselineDirty[f].mtimeMs` sau thời điểm giao việc phải bị quy thuộc vào task bất kể Worker có khai báo trong `result.files_changed` hay không.

#### [S09-P0-02] `commitPolicy: 'forbid'` không được kiểm tra trong `gate()`, và `git commit` làm rỗng `snap.wt` khiến toàn bộ `lint-diff` & `lastChangeAt` bị bypass 100%
- **Vị trí:** [`mcp-servers/antigravity-pm-mcp/src/config.js#L242`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/config.js#L242), [`src/worktree.js#L75`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/worktree.js#L75), [`#L81`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/worktree.js#L81), [`src/lint-diff.js#L150-L181`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/lint-diff.js#L150-L181), [`src/tools.js#L993`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tools.js#L993), [`#L1006`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tools.js#L1006)
- **Cơ chế lỗi:**
  1. `GATE_KEYS` trong `config.js` không có `commitPolicy`, và `gate()` trong `policy.js` không hề kiểm tra `snap.head !== task.baseHead` khi `commitPolicy === 'forbid'`.
  2. Nguy hiểm hơn: `gateCtx()` (dòng 75, 81) truyền `snap.wt` (chỉ gồm các file **chưa commit** từ `git status --porcelain`) thay vì `changedFiles` vào `soiThayDoi(projectRoot, snap.wt)` và `lastChangeAtOf(projectRoot, snap.wt, ...)`. Nếu Worker chạy `git commit`, `snap.wt` lập tức bằng `[]`, khiến `lint-diff`, kiểm tra kích thước diff, và kiểm tra sửa code sau test bị vô hiệu hóa hoàn toàn!
- **Khuyến nghị sửa:** Thêm kiểm tra `commitPolicy === 'forbid' && snap.head !== task.baseHead` vào `gate()`, và truyền `changedFiles` (hợp của `snap.wt` + `snap.sinceBase`) vào `soiThayDoi` và `lastChangeAtOf`.

#### [S09-P0-03] Tự khóa chết conversation vĩnh viễn và xúi `kill` chính tiến trình MCP Server khi `agySendMessage` lỗi sau khi thu hồi reservation
- **Vị trí:** [`mcp-servers/antigravity-pm-mcp/src/agentapi.js#L273-L278`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/agentapi.js#L273-L278), [`#L552-L596`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/agentapi.js#L552-L596); [`src/tools.js#L137`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tools.js#L137)
- **Cơ chế lỗi:** Khi `pm_reserve_slot` đặt chỗ (`entry.pid = process.pid`, `reservation: true`) rồi hết hạn TTL 90s, lệnh `agySendMessage` kế tiếp thu hồi slot đó nhưng nếu gửi HTTP thất bại (hoặc gõ sai `conversationId`), khối `catch` ở dòng 590 lại ghi đè lock thành `{ pid: process.pid, reservation: false }` (vì `entry.pid === process.pid` là PID của chính MCP Server đang sống!). Từ thời điểm đó, `entryBusy(cur)` luôn trả về `true` vĩnh viễn và thông báo lỗi hướng dẫn chạy `kill -- -<PM_PID>` (tự sát tiến trình MCP Server!).
- **Khuyến nghị sửa:** Trong `catch` của `agySendMessage`, nếu `entry?.reservation` hoặc `entry?.pid === process.pid`, phải `fs.unlinkSync(lp)` để xóa lock thay vì ghi lại `reservation: false`.

#### [S09-P1-01] `renderReport()` bỏ quên tham số `gateCtx`, khiến mọi báo cáo `pm_accept` / `pm_report` đều in `CHUA DAT`
- **Vị trí:** [`mcp-servers/antigravity-pm-mcp/src/report.js#L7-L10`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/report.js#L7-L10); đối chiếu [`src/tools.js#L817`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tools.js#L817), [`#L971`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tools.js#L971)
- **Cơ chế lỗi:** `tools.js` gọi `renderReport(task, gate(task, gateCtx(task)), gateCtx(task))` truyền 3 đối số, nhưng hàm `renderReport(task, g)` ở `report.js` dòng 7 chỉ khai báo 2 tham số và tự gọi `gate(task)` (không có `ctx`) ở dòng 8, làm mất `lastChangeAt`, `diffCheck`, `citeCheck` và khiến báo cáo nghiệm thu luôn hiển thị `CHUA DAT`!

#### [S09-P1-02] Lỗ hổng Path Traversal & đọc file ngoài `projectRoot` qua symlink trong `proof.js`, `oracle.js`, `worktree.js`, `cite-check.js`
- **Vị trí:** [`mcp-servers/antigravity-pm-mcp/src/proof.js#L278`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/proof.js#L278), [`#L338`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/proof.js#L338); [`src/oracle.js#L77`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/oracle.js#L77); [`src/worktree.js#L100`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/worktree.js#L100); [`src/cite-check.js#L16,L32`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/cite-check.js#L16)
- **Khuyến nghị sửa:** Dùng `fs.realpathSync` và kiểm tra đường dẫn thực phải nằm bên trong `fs.realpathSync(projectRoot) + path.sep`.

#### [S09-P1-03..07] Các lỗi cấp P1 khác trong Slice 09 (kể cả trạng thái 7 mục OpenCodeReview `I.4`)
- **[S09-P1-03]** [`src/proof.js#L256-L270`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/proof.js#L256-L270) & [`src/policy.js#L51`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/policy.js#L51): Provider `qa-visual` (`playwright`) luôn báo lỗi `qa-visual ran but produced no PNG` vì regex tìm ảnh trong stdout nhưng `capture.mjs` chỉ in JSON summary; đồng thời `PROVIDER_TYPE_KHONG_THIET_BI` thiếu `'playwright'`.
- **[S09-P1-04]** [`src/tasks.js#L199-L215`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/tasks.js#L199-L215): Lỗi số 3 trong OpenCodeReview `I.4` (race condition khi thu hồi lock hết hạn bằng `unlinkSync`) đã được sửa ở `agentapi.js` nhưng **bị bỏ quên trong `tasks.js`**.
- **[S09-P1-05]** [`src/lint-diff.js#L82`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/lint-diff.js#L82): Regex `/b\/(.+)$/` không neo ở đầu chuỗi nên cắt hỏng mọi đường dẫn có thư mục kết thúc bằng chữ `b` (`src/lib/foo.js` bị cắt thành `foo.js`, khiến `soiThayDoi` bỏ qua toàn bộ các file trong `lib/`, `web/`, `db/`!).
- **[S09-P1-06]** [`src/policy.js#L280-L286`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/policy.js#L280-L286): `cungFile()` dùng khớp hậu tố `.endsWith('/' + x)`, cho phép `tests/fake/src/auth.js` khớp giả với `src/auth.js`.
- **[S09-P1-07]** [`src/proof.js#L88-L96,L157`](file:///Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/src/proof.js#L88-L96): `spawnDetached('emulator', ...)` không gắn listener `.on('error')` (sập tiến trình MCP Server nếu thiếu binary `emulator`) và không kill emulator mồ côi khi hết timeout 120s.

---

### Slice 10 — Test Suite, Impacted Runner & Unparseable Test Files (`6.358` dòng / 24 file cốt lõi)

**Phạm vi:** `tests/run_impacted.sh`, `tests/impact_map.txt`, `tests/lib/*`, 11 file test bị `codebase-memory-mcp` báo `parse_unusable`, 2 file báo `parse_partial`, cùng các test trong `hooks/tests/*` và `tests/worktree_git/*`.

#### [S10-P1-01] Race condition trong `test_gate_run_log.sh` subtest `(g)` và lệch schema `check_fields` giữa `main` và worktree A15
- **Vị trí:** [`universal-agent-devkit/tests/gates/test_gate_run_log.sh#L289`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/gates/test_gate_run_log.sh#L289), [`#L782-L804`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/gates/test_gate_run_log.sh#L782-L804)
- **Cơ chế lỗi:** Subtest `(g)` bắn đồng thời 12 tiến trình `post-fix-gate.py --run-tests --full --brief` với `TEST_RUN_LOCK_WAIT_S=0` và đòi mọi bản ghi log phải có `verdict in ("PASS", "BUSY", "REUSED")`. Khi `full_pass.json` bị xóa/ghi lại giữa chừng bởi tiến trình giữ khóa, các tiến trình đến sau có thể ghi verdict `STALE` hoặc `UNTESTED` làm flaky test. Đồng thời `check_fields` ở dòng 289 đang lệch giữa `main` và worktree A15 ở hai trường `"suites_cut"` và `"steps"`.

#### [S10-P1-02] Lỗ hổng ánh xạ trong `tests/impact_map.txt` làm lọt lưới kiểm thử khi sửa các script production
- **Vị trí:** [`universal-agent-devkit/tests/run_impacted.sh#L57-L72`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L57-L72); [`universal-agent-devkit/tests/impact_map.txt#L1-L59`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/impact_map.txt#L1-L59)
- **Cơ chế lỗi:** Các script production sau đây không có dòng ánh xạ tương ứng trong `impact_map.txt`, nên khi sửa chúng, `run_impacted.sh` chỉ chạy `test_repo_consistency.sh` mà bỏ qua hoàn toàn bộ test chức năng:
  - `scripts/governance/fold_agent_file.py` → thiếu `tests/governance/test_fold_agent_file.sh`
  - `scripts/governance/devkit_i18n.py` → thiếu `tests/governance/test_i18n_en.sh`
  - `profiles/game/scripts/unity-bot-marathon.sh` → thiếu `tests/profiles/test_unity_scripts.sh`
  - `dashboard/collect_rows.py` → thiếu `tests/governance/test_dashboard_smoke.sh`
  - `profiles/android/scripts/qa/*` → không có rule trong `impact_map.txt`

#### [S10-P2-01] Nguyên nhân gốc của 11 file `parse_unusable` và 2 file `parse_partial` trên `codebase-memory-mcp`
- **Vị trí:**
  - **11 file `parse_unusable`:** [`test_gate_run_log.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/gates/test_gate_run_log.sh), [`test_gate_runs_report.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/governance/test_gate_runs_report.sh), [`test_hook_python_static_ratchet.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/governance/test_hook_python_static_ratchet.sh), [`test_lane_plan.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/governance/test_lane_plan.sh), [`test_proof_capture_lock.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/gates/test_proof_capture_lock.sh), [`test_session_lock_resolve.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/locks/test_session_lock_resolve.sh), [`test_state_fifo_no_hang.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/locks/test_state_fifo_no_hang.sh), [`test_stop_hook_times.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/governance/test_stop_hook_times.sh), [`test_testsourceset_gate_lock.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/gates/test_testsourceset_gate_lock.sh), [`test_evidence_runners.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/testing/test_evidence_runners.sh), [`test_red_proof_patch_cap.sh`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/testing/test_red_proof_patch_cap.sh)
  - **2 file `parse_partial`:** [`test_session_lock_robust.sh#L64`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/locks/test_session_lock_robust.sh#L64), [`test_session_lock_sh_parent.sh#L24`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/locks/test_session_lock_sh_parent.sh#L24)
- **Cơ chế lỗi:**
  1. Cả 11 file `.sh` bị `parse_unusable` đều đặt 100% logic bên trong một khối `python3 -I - ... <<'PY'` ở cấp cao nhất mà không khai báo bất kỳ hàm Bash nào (`main() { ... }`), khiến bộ trích xuất ký hiệu Bash của `codebase-memory-mcp` thu được 0 symbol.
  2. Hai file `parse_partial` viết `python3 - "$REPO" <<'PY' &` (đặt toán tử chạy nền `&` ngay trên dòng tiêu đề heredoc `<<'PY'`), làm bộ phân tích cú pháp tree-sitter-bash báo lỗi tại dòng đó.
- **Khuyến nghị sửa:** Bọc thân script trong hàm `run_test() { ... }; run_test "$@"` cho 11 file trên, và tách khối heredoc chạy nền thành hàm hoặc subshell `( python3 - "$REPO" <<'PY' ... PY ) &` cho 2 file `parse_partial`.

#### [S10-P2-02] `run_impacted.sh` tách từ không có `set -f` và không dọn tiến trình con `xargs -P` khi bị hủy giữa chừng
- **Vị trí:** [`universal-agent-devkit/tests/run_impacted.sh#L57`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L57), [`#L73`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L73), [`#L84`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L84), [`#L115`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L115), [`#L129`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/tests/run_impacted.sh#L129)
- **Khuyến nghị sửa:** Bật `set -f` khi lặp qua danh sách hoặc chuyển sang mảng Bash (`read -r -a`), và bổ sung `pkill -P $$ || true` vào `cleanup()`.

---

## 3. Lộ Trình Khắc Phục Ưu Tiên (Roadmap To 100/100)

Để đưa toàn bộ hệ thống lên mức **100/100 tuyệt đối** và triệt tiêu hoàn toàn hiện tượng kẹt/chặn giả, cần thực thi theo 4 đợt (lanes) độc lập sau:

1. **Đợt 1 — Vá ngay 5 lỗi P0 gây nghẽn vận hành hàng ngày (High-Impact Unblockers):**
   - **Fix 1A (`review_gate.sh`):** Đổi `_names(_bcmd, _rel, _base)` thành `_writes(_bcmd, _rel)` tại dòng 601, giảm `BASH_OPEN_MAX_S` xuống `300`, bật `status_optional=True` và thêm `session_worktree.py` cho `review_gate.sh` & `claim_check.sh` (**S04-P0-01, P0-02, P0-03**).
   - **Fix 1B (`nightly.py` & `red_proof.py`):** Cho phép `checkout_busy()` chạy `red_proof.py --detached` khi `session_lock.py --status` trả về `exit 5` (Trunk Mode), và đổi tên biến cục bộ `patch` ở dòng 673 của `red_proof.py` thành `rev_diff` (**S06-P0-01, S07-P0-01**).
   - **Fix 1C (`test_evidence_gate.sh`):** Chấp nhận `"gate-green"` ở Check 7 (`paired_red_green`, dòng 1728) và thêm `not is_test_path(fp)` ở dòng 1109/1115 (**S04-P1-01, P1-02**).
2. **Đợt 2 — Khóa chặt Parser & Worktree Isolation (Zero Fail-Open):**
   - Chuẩn hóa ANSI-C quote `$'...'`, nối dòng `\<newline>` trước `drop_comments()`, kiểm tra escape trước `\${` và bắt cờ gộp `-ISc` trong `block-dangerous-git.sh`, `hardware_safety_gate.sh`, `shell_writes.py`, `shell_norm.py` (**S03-P0-01..04**).
   - Sửa `_bash_trunk_write` trong `session_lock.py`, `_crit_hash` trong `regression_checklist.py`, và `flock` trong `instincts.py` (**S02-P0-01..03**).
   - Bảo vệ worktree có `git status --porcelain` khác rỗng trong `worktree.py:cmd_gc` và kiểm tra `ahead` trước `rmtree` trong `worktree_sandbox.py` (**S05-P0-01..04**).
3. **Đợt 3 — Gia cố Antigravity PM MCP Server (`mcp-servers/antigravity-pm-mcp`):**
   - Truyền `changedFiles` thay vì `snap.wt` vào `soiThayDoi`/`lastChangeAtOf`, kiểm tra `commitPolicy === 'forbid'` trong `gate()`, sửa regex `/b\/(.+)$/` trong `lint-diff.js`, truyền `ctx` vào `renderReport()`, và `unlinkSync` lock khi `agySendMessage` lỗi trên reservation (**S09-P0-01..03, P1-01..07**).
4. **Đợt 4 — Đồng bộ Tài liệu, Dọn rác tự động & Làm sạch AST Index:**
   - Gắn `devkit_clean.py` vào `nightly.py`, sửa `fold_agent_file.py`, sửa hằng số intent trong `enrich_context.py`, cập nhật `impact_map.txt`, và bọc hàm cho 13 file test `parse_unusable`/`parse_partial` (**S06-P1-02..07, S08-P0-01..03, S10-P1-01..02, S10-P2-01**).
