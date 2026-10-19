# QA v4 — issue #13, head 94e7b75

Lệnh: bash universal-agent-devkit/tests/context_memory/test_session_lock*.sh + tests/gates/test_worktree_guard_shell_writes.sh
Kết quả: 10/10 file exit 0 (suite của Builder PASS).

Probe đối kháng (trunk_write từ linked worktree, 38 dạng): 33 đúng. Lọt (mong đợi chặn, thực tế ALLOWED):
- M=<main>/README.md; sed -i s/r/x/ "$M"        (đích là biến trần, không có "/")
- M=<main>/README.md; perl -pi -e s/r/x/ "${M}"
- M=<main>; cd "$M" && echo x > README.md        (cd qua biến)
- M=<main>; cd "$M" && sed -i s/r/x/ README.md
Đối chứng đúng: redirect tới "$M" trần bị chặn; O=/tmp/o; sed -i "$O/f" vẫn được phép.
Probe: .git/super-board/evidence/issue-13/qa-v4-probe.py (ngoài branch).
