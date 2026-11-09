#!/usr/bin/env bash
# #1034: halt_path() gọi `git rev-parse --git-common-dir` với timeout=5; máy tải nặng làm git chậm thì
# subprocess.TimeoutExpired thoát thẳng ra ngoài (Traceback ở start.log của runner). Phải rơi về đường dẫn mặc định.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
out="$(python3 - "$READ" <<'PY' 2>&1
import importlib.util, os, subprocess, sys, tempfile
os.environ.pop('SB_GITHUB_HALT_FILE', None)
spec = importlib.util.spec_from_file_location('ghread', sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
def slow(*a, **k): raise subprocess.TimeoutExpired(a[0], 5)
mod.subprocess.run = slow
d = tempfile.mkdtemp(); os.environ['SB_REPO_PATH'] = d
p = mod.halt_path()
assert str(p) == os.path.join(d, '.claude/super-board/github-halt.json'), p
mod.check_halt()  # không có file halt: phải trả về êm
print('OK')
PY
)"
rc=$?
if [ "$rc" = 0 ] && [ "$out" = "OK" ]; then echo "✔ halt_path chịu được git timeout"; echo OK; exit 0; fi
echo "✖ halt_path lỗi khi git timeout (rc=$rc): $(echo "$out" | tail -2)"; exit 1
