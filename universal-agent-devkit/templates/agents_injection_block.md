# Universal Agent DevKit
Loaded at every session start. Claude Code and Gemini CLI expand the `@` lines. Grok, Codex and Cursor read this same file: open each path after the @ before any work. Grok has no separate directory.
- DevKit essentials (always apply): @.agents/context/essentials.md
- Domain profile rules: @.agents/context/profile-rules.md
- Project rules index (`.agents/local/rules/`): @.agents/context/rules-index.md

On demand — everything agent-related lives in `.agents/`: master rules `.agents/devkit/AGENTS.md` · engineering standards `.agents/devkit/rules/core-rules.md` · skills `.agents/skills/` · traps from past bugs `.agents/instincts.md` · profile `.agents/active-profile.json`.
Post-fix gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full` — only exit `0` counts as PASS. Every prompt also attaches a real device proof PNG from this turn before the reply may open with XONG. Standing text: the top of this file and `.agents/context/essentials.md` ("Every prompt"). A serial in `.adb-denylist`, or forbidden by a project rule, is never captured.
