---
name: ps-parsing-traps-macos
description: Two measured traps when parsing macOS `ps` output in Python — UnicodeDecodeError escapes SubprocessError catches, and Homebrew python shows as Python.app in argv0
metadata:
  type: project
---

Measured 2026-10-24 on the user's Mac (Homebrew python 3.14):
- `subprocess.run(["ps",...], text=True)` raises UnicodeDecodeError when any process has non-UTF-8 bytes in argv; it is a ValueError, NOT caught by `except (OSError, subprocess.SubprocessError)`.
- `/opt/homebrew/bin/python3 script.py` appears in `ps command=` as `.../Python.app/Contents/MacOS/Python script.py`, so any `.app/Contents/MacOS/` regex that overrides argv0 classification hides python scripts.
- `ps -o pcpu=` follows the locale: `LC_ALL=de_DE.UTF-8` prints `33,4` (float() fails); vi_VN and C print `33.4`. Pass `env={..., "LC_ALL": "C"}`.
- Node CLIs without `process.title` (Gemini CLI, checked in its bundle) show as `node /opt/homebrew/bin/gemini`; an "interpreter → only look at the script" rule must still match the script basename.
- Measured: `ps -Ao` via a pipe is NOT width-truncated on macOS (9244-char lines seen); `[^/]+\.app` regex on 50k-char args runs in ~5 ms (no catastrophic backtracking).

**Why:** both slipped past fixture-based tests (fixtures used `/usr/bin/python3` and ASCII lines).
**How to apply:** when reviewing code that parses `ps`, probe a real process with a scratch script instead of trusting fixtures; check decode errors and the Python.app path.
