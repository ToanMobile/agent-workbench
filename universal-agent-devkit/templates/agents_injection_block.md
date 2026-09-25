# Universal Agent DevKit
Loaded at every session start. Claude Code and Gemini CLI expand the `@` lines. Antigravity, Grok, Codex and Cursor read this same file as plain text: open each path after the @ before any work. Grok has no separate directory.
- DevKit essentials (always apply): written out in full at the end of this block, so an agent that expands no `@` import (Antigravity, measured 2026-09-25) has them too.
- Domain profile rules: @.agents/context/profile-rules.md
- Project rules index (`.agents/local/rules/`): @.agents/context/rules-index.md

On demand — everything agent-related lives in `.agents/`: master rules `.agents/devkit/AGENTS.md` · engineering standards `.agents/devkit/rules/core-rules.md` · skills `.agents/skills/` · traps from past bugs `.agents/instincts.md` · profile `.agents/active-profile.json`.
Post-fix gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full` — only exit `0` counts as PASS. A turn that changes app source on a profile with a screen also attaches a real proof PNG from this turn before the reply may open with XONG. Standing text: the top of this file and the essentials below ("Every prompt"). A serial in `.adb-denylist`, or forbidden by a project rule, is never captured.

<!-- devkit-essentials:start — generated from the DevKit's rules/essentials.md by scripts/context_sync.py; do not edit -->
<!-- devkit-essentials:end -->
