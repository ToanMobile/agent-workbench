# Universal Agent DevKit Standards
Before any other work, read every file listed below in full — they are this project's rules. Paths are relative to the repository root. Claude Code imports the `@` lines by itself; Codex, Cursor, Gemini and any other agent: open each path after the @ with your file-read tool (an `@` line that is not expanded, or shows "Import failed", has NOT been loaded).
- Central Engineering Rules & SSOT: @AGENTS.md
- Active Domain Profile: @.active-profile.json
- High-Performance & Security Standards: @rules/core-rules.md
- Post-Fix Verification Gate: `postfix-gate --run-tests` (installed on PATH by `make install` in the DevKit; without it: `python3 <DevKit dir>/bin/post-fix-gate.py --run-tests`). Only exit `0` counts as PASS.
