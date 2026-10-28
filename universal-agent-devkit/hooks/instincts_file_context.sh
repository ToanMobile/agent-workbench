#!/usr/bin/env bash
# PreToolUse(Read|Edit): thin bash entry for hooks/instincts_file_context.py (every hook is registered through bash; #555). Never blocks.
# Registered through a .claude/hooks/ symlink: resolve it so the .py next to the real file is found.
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do
  DIR="$(cd "$(dirname "$SRC")" && pwd)"
  SRC="$(readlink "$SRC")"
  case "$SRC" in /*) ;; *) SRC="$DIR/$SRC" ;; esac
done
python3 -I "$(cd "$(dirname "$SRC")" && pwd)/instincts_file_context.py"
exit 0
