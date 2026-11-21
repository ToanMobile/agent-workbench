#!/usr/bin/env bash
# #1392 audit (Antigravity, 21/11/2026): super-board-status.py picks the config whose repo.remote matches origin when
# several configs exist. A config that is valid JSON but not an object (`[]`, `null`) or has a non-object "repo"
# raised AttributeError and killed the status command instead of being skipped.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/r/.claude/super-board/configs"
git -C "$T/r" init -q
git -C "$T/r" remote add origin git@github.com:acme/widget.git
echo '[]' > "$T/r/.claude/super-board/configs/a.json"
echo '{"repo": "x"}' > "$T/r/.claude/super-board/configs/b.json"
echo '{"repo": {"remote": "https://github.com/acme/widget"}}' > "$T/r/.claude/super-board/configs/c.json"

out="$(python3 - "$ROOT/.claude/bin/super-board-status.py" "$T/r" <<'PY' 2>&1
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.resolve_config_slug(["super-board-status.py"], Path(sys.argv[2])))
PY
)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | tail -1)" = "c" ]; then
  echo "✅ test_status_config_non_dict_1392: non-object configs skipped, matching config c chosen"; exit 0
fi
echo "❌ test_status_config_non_dict_1392: rc=$rc out=$(printf '%s' "$out" | tail -3)"; exit 1
