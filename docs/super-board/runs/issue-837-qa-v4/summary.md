# QA #837 v4 — head ba4e8edd (rebuild lần 2 sau audit T0311)

- Lệnh AC: `bash universal-agent-devkit/tests/gates/test_guard_remote_ref_forge.sh`
- Hook cũ (origin/main): rc=1, 27 ca ✖ (ĐỎ). Hook PR: rc=0 `OK` (XANH).
- `test_guard_shell_norm.sh`: ALL PASS. `test_hook_cached_python.sh`: rc 0.
- Dò tay qua `hooks/block-dangerous-git.sh`: `update-ref refs/remotes/...` (kể cả `refs/Remotes`, nháy kép, `-c`, `$B`, `--stdin`), `symbolic-ref -m`, `remote set-head -a --no-auto`, `set-head -a feat` rc 2; `set-head --auto`, `--no-auto --auto`, `symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null`, lệnh đọc trong `python3 -c`, fetch, pull rc 0.
- Gate `--scoped --json` qua `super-board-qa-exit2.sh` = `review` (exit 2: `tests/impact_map.txt` là test đã có bị sửa, cần duyệt chéo; chỉ thêm tên test mới vào dòng của `block_dangerous_git_main.py`).
- `run_impacted.sh` chạy tay: 592 test ✔, có 9 test đỏ ngoài phạm vi PR (không chạm file nào của chúng): `test_uninstall`, `test_guard_nested_c_quotes` (ca `hardware_safety_gate`, không phải hook git), `contract_facts_test` (F4 `hooks/hooks.json` guard-protected-push), `test_worktree_lane`, `test_relink_new_kit_items`, `test_agent_health_score_inflation`, `test_install_claude_only`, `test_session_card_hook`, `test_evidence_unity`. Chưa đối chiếu từng cái với main.
- Ngoài AC (đã ghi trước): `git branch -r -d`, `git remote remove|rename`, `git push .`/`fetch .` ghi refs/remotes.
