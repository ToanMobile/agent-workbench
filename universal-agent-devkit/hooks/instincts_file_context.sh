#!/usr/bin/env bash
# PreToolUse(Read|Edit): thin bash entry for hooks/instincts_file_context.py (every hook is registered through bash; #555). Never blocks.
exec python3 -I "$(dirname "$0")/instincts_file_context.py"
