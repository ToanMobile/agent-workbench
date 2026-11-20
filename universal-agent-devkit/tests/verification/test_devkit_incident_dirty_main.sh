#!/usr/bin/env bash
# #1388: "self-reload: main stays <sha>, behind origin/<base> <sha>: uncommitted edits in the way: <files>" là cảnh báo cho chủ repo
# (file sửa dở của người dùng chặn ff), không phải lỗi kit: devkit_incident không được biến nó thành thẻ 🐛.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$DEVKIT_DIR/scripts/governance" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import devkit_incident as d
dirty = "[11:10:14] ⚠ self-reload: main stays 6e3a038, behind origin/main 32a795b: uncommitted edits in the way: Assets/Foo.cs .gitignore "
assert d.classify_board(dirty) is None, d.classify_board(dirty)
# guard: lỗi kit thật của cùng luật vẫn thành sự cố
real = "[11:10:15] ⚠ self-reload: cannot create worktree .claude/worktrees/self-reload-1-2: boom"
assert d.classify_board(real) is not None
# ff-only hỏng không tìm ra file chặn là lỗi kit thật, vẫn báo
ffbad = "[11:10:16] ⚠ self-reload: git merge --ff-only origin/main failed with no blocking file found; main stays 6e3a038"
assert d.classify_board(ffbad) is not None
PY
rc=$?
[ "$rc" = 0 ] && { echo "PASS test_devkit_incident_dirty_main"; exit 0; }
echo "FAIL test_devkit_incident_dirty_main"; exit 1
