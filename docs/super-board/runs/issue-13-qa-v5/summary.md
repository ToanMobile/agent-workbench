# QA v5 — issue #13, head ba4183e

Lệnh: bash universal-agent-devkit/tests/context_memory/test_session_lock*.sh + tests/gates/test_worktree_guard_shell_writes.sh
Kết quả: 10/10 file exit 0; py_compile session_lock.py + shell_writes.py OK.

Probe đối kháng (trunk_write từ linked worktree, 53 dạng, `python3 -I`): 52 đúng, 0 lọt.
Đã đóng: `sed -i`/`perl -pi` với `"$M"`/`"${M}"` trần, `cd "$M"`/`pushd`/`cd ${M}`/`cd $(…)`/backtick rồi ghi tương đối,
`sed -i.bak`, `-i ''`, `--in-place`, `-ni`, `-e` lặp, `-f`, `--`, `tee`/`cp`/`mv`/`rm`/`touch`/`ln`/`install`/`truncate`, `exec 3>`,
subshell/nhóm `{}`, `for d in main; do cd "$d"`, xuống dòng giữa `cd` và ghi.
Đối chứng vẫn được phép: `O=/tmp/o` (sed -i, cd + ghi), `sed -i '$d'`, `cd "$M" && git status`, đọc main, `cd /tmp`.
Dương tính giả duy nhất (chặn thừa, fail-closed, Low): `M=<main>; cd "$M"; cd /tmp; echo x > f` bị chặn
(`cd_unsafe` không được xoá khi có `cd` literal sau đó).
Probe: docs/super-board/runs/issue-13-qa-v5/probe.py (chạy `python3 -I probe.py <universal-agent-devkit>`).
