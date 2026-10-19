# QA v5 — issue #13, head ba4183e — FAIL

Lệnh: bash universal-agent-devkit/tests/context_memory/test_session_lock*.sh + universal-agent-devkit/tests/gates/test_worktree_guard_shell_writes.sh
Kết quả suite của Builder: 10/10 file exit 0; py_compile OK.
probe.py: 53 dạng, 52 đúng, 1 dương tính giả Low (`cd "$M"; cd /tmp; echo x > f` bị chặn thừa). Các ca này dùng README.md, có ở cả main lẫn worktree.

Gap High (bảo mật), do reviewer context sạch tìm ra và đã chạy lại (probe-cd-relative.py): sau `cd "$VAR"`, `sed -i`/`perl -pi` chỉ phát operand khi `_exists(a, wd)` đúng ở worktree (shell_writes.py), nên đích tương đối chỉ có ở main không sinh target; `cd_unsafe` không được xét.
- `M=<main>; cd "$M" && sed -i s/r/x/ only.txt` (only.txt chỉ có ở main), cwd worktree → ALLOWED
- `M=<main>; cd "$M" && perl -pi -e s/r/x/ only.txt` → ALLOWED
- `cd $(echo <main>) && sed -i s/r/x/ only.txt` → ALLOWED
- `M=<main>; cd "$M" && sed -i s/r/x/ README.md`, cwd = <worktree>/sub → ALLOWED
- Đối chứng: `cd "$M" && echo x > only.txt` → BLOCKED
Sửa đúng: khi đã gặp `cdvar`, phát mọi operand không phải script của `sed -i`/`perl -i` làm target, không cần `_exists`; thêm ca test có file chỉ ở main và cwd là thư mục con.
Lưu ý: kết luận "0 lọt" ở bản nháp trước của summary này là sai.
