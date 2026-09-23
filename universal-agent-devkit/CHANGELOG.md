# Changelog

All notable changes to Universal Agent DevKit. Versions follow `.claude-plugin/plugin.json`.

## Unreleased

### Gates
- **post-fix gate — dependency check (6th static check):** floating versions (Gradle `1.+` /
  `latest.release`, version catalogs, npm `latest`/`*` outside `peerDependencies`, Cargo/Poetry `*`,
  pubspec `any`, Maven `LATEST`/`RELEASE`) and plain-`http://` / TLS-off package sources (Gradle
  `maven { url }`, `allowInsecureProtocol`, `.npmrc`, pip `--index-url`/`--trusted-host`, Podfile
  `source`, pom `<repository>`) now REJECT. Rules are anchored to declaration shapes: license URLs,
  loopback repositories, caret ranges and test fixtures are not flagged.
- **post-fix gate `--staged`:** the 6 static checks on the staged blobs (not the working tree), for
  pre-commit use. Clean is exit 2 (tests not run), never PASS.
- **`agent-kit githooks install|uninstall|status`:** git pre-commit hook running `--staged` on every
  commit, also outside any agent. Honours `core.hooksPath`; never overwrites a project's own hook
  (prints the line to chain it); fails closed when the gate gives no verdict. `agent-kit uninstall`
  removes it.
- **post-fix gate `--json` `findings`:** every static finding also comes as
  `{category, rule, message, file, line, snippet}`, so an agent can go straight to `file:line`
  instead of parsing the colored log. Secrets carry their line but never a snippet.
- **`hardware_safety_gate.sh` device policy:** an adb command that reaches a serial on the denylist
  (`ADB_DENY_SERIALS`, `~/.config/universal-agent-devkit/adb-denylist`, `<repo>/.adb-denylist`) or
  outside a non-empty allowlist (`ADB_ALLOW_SERIALS`, `adb-allowlist`, `.adb-allowlist`) is refused
  (exit 2). Without `-s`, the serial adb would pick (`-d`/`-e`/`-t`, `ANDROID_SERIAL`, the only
  device online) comes from `adb get-serialno`; an unresolvable one (`$VAR`, adb timeout) is
  refused. Host-only subcommands (`devices`, `connect`, `kill-server` …) are never checked. Keep
  personal serials in the per-user file, not in the repo. No policy set = no change.
- **`adb-safe-exec.sh`:** checks the device policy against the serial it actually picks (one device
  plugged in may be a personal phone). On a native crash it keeps the whole tombstone that
  debuggerd logged since the command started (never an older one) and, with `--symbols DIR` /
  `ANDROID_SYMBOLS` plus `ndk-stack`, prints it decoded to function and `file:line`; otherwise
  the raw `#NN pc` frames. Refuses to run when a device policy is set but the gate is missing.

### Memory
- **`agent-kit learn "<title>" --cause=… --rule=…`** (`bin/instincts.py`): adds a lesson to
  `.agents/instincts.md` under the next `[INSTINCT-NNN]` id, refuses a title already recorded
  (`--force` to add anyway), escapes Markdown, and refuses to write through a link into the DevKit.
  `post-fix-gate --record-lesson` uses the same writer, so it no longer stamps `[INSTINCT-AUTO]`.

### Install
- **Project-tier rules are no longer silent:** the rule files moved to `.agents/local/rules/` are
  listed as `@.agents/local/rules/<file>` imports in the DevKit block of `CLAUDE.md`, `GEMINI.md`,
  `.cursorrules`, `CODEX.md` and a project's own `AGENTS.md`, refreshed on every install (dated
  copies left out). `AGENTS.md` §4 says how they rank: they add project rules; where one
  contradicts §6 or `rules/core-rules.md`, the DevKit rule wins and the conflict is reported.
- **Project tier `.agents/local/` replaces the 1.1.0 `commands_old/`, `skills_old/`, `agents_old/`,
  `hooks_old/` backups.**
  DevKit is the core: a project skill/command/agent/hook with a DevKit name moves to
  `.agents/local/<kind>/<name>` and the DevKit item is installed. The folder is committed (not
  git-ignored), never written by later installs, and its items with a free name are linked back into
  the agent folders (relative links); when a DevKit update later claims such a name, the DevKit wins
  and the project's copy stays in place, inactive. In copy mode an edited DevKit copy keeps only the
  edited files there (a later edit gets a dated folder, never overwriting the first); root `rules/`
  edits land in `.agents/local/rules/` instead of `rules_old/`. `list-old` shows active/shadowed items;
  `restore-old --apply` puts items back and removes consumed ledgers and empty folders. Top-level
  `*_old` snapshots (`CLAUDE_old.md`, …) are unchanged. Existing `*_old` folders from earlier installs
  are not migrated.
- **Root `rules/`, `skills/`, `commands/` owned by the project are no longer skipped** (1.1.0 left them
  in place without the DevKit one, so DevKit paths like `@rules/core-rules.md` broke). Agent material
  (`*.md`, `SKILL.md` folders) moves to `.agents/local/<dir>/`; a source-code dir (e.g. `commands/build.js`)
  stays and gets every DevKit item placed inside it (a same-named file moves to the tier). `uninstall`
  removes those placed items. Fixed on the way: `has_user_content` leaked its loop variable `item`.

- **`bin/quick-install.sh` re-runs update instead of nesting.** The first run moved
  `universal-agent-devkit/` out of a temp clone and deleted the clone, so `~/.universal-agent-devkit` had
  no `.git`; a second run cloned again and `mv` put the new copy *inside* the old one — never updated.
  Now `~/.agent-workbench` is a sparse git checkout of only `universal-agent-devkit/` (re-runs `git pull
  --ff-only`, local edits skip the update) and `~/.universal-agent-devkit` is a stable link to it, so
  existing CLI/project links keep working. An old non-git copy is kept as `.old-<time>`;
  `DEVKIT_LOCAL_SOURCE` links a local checkout in place instead of copying the whole monorepo.
  `tests/test_quick_install.sh` covers it against a local remote.

### Automation (what runs without the model choosing to)
- **Regression gate actually runs.** `regression_gate.sh` never looked at
  `.agents/regression_matrix.active.json` (what `agent-kit profile` writes), so the Stop-time regression
  run was silently skipped on every real project. It now reads it first; profile matrices marked
  `"enforce_as_is": true` (web, backend — they auto-detect the project's own runner) are enforced as
  installed; a copy-mode hook finds the gate via `$DEVKIT_ROOT` / `~/.universal-agent-devkit`, and a
  missing gate is reported once per session instead of skipped silently.
- **"Đã fix" is satisfiable.** `test_evidence_gate.sh` check 7 accepted only a multi-lens-audit workflow
  result the installer never ships, so every true "fixed" claim was blocked. It now also accepts the
  paired RED→GREEN the rules require, seen in the session's own tool results: a test run that failed
  before the last source edit and one that passed after it (npm/jest/pytest/cargo/go/gradle…). A green
  run alone still blocks.
- **The agent cannot skip the pre-commit gate:** `block-dangerous-git.sh` blocks `commit|push
  --no-verify`, `commit -n`, `git -c core.hooksPath=…` and `DEVKIT_PRECOMMIT=0 git commit`. `agent-kit
  init` installs the pre-commit gate in git projects (`--no-githooks` to skip).
- **`git restore <file>` is allowed after an automatic backup** to `.claude/audit-gate/restore-backup/`,
  so the agent can undo its own bad edit without costing uncommitted work; `.`, directories, globs and
  unknown options stay blocked.
- **New hooks `session_context.sh` (SessionStart) and `prompt_context.sh` (UserPromptSubmit):** a session
  starts with the profile, the line-numbered map of `.agents/instincts.md` (the index is regenerated
  above 20 KB instead of loading the file) and the regression-checklist state; every request gets the
  matching traps with their `sed -n` range, intent-specific requirements and, for a bug fix, the
  RED→GREEN rule. Questions and chit-chat get nothing. `enrich_context.py` ranks traps (stopwords and
  syllables common to many entries ignored, intent terms added, template/commented entries skipped)
  and has `--compact`.
- **Review and comment checks follow the profile:** `review_gate.sh` and `comment_claim_guard.sh` use the
  active profile's new `source_extensions` (`hooks/devkit_profile.py`) instead of Kotlin/Java only —
  `.ts` on web, `.swift` on iOS, `.py/.go/.rs` on backend, every language without a profile.
  `open-code-review` counts as a review; the block message names the reviewer the DevKit installs.
- **Codex, Gemini CLI and Cursor get the gates too:** `hooks/agent_bridge.sh` translates their hook
  protocols; `scripts/agent_hooks.py` registers session/prompt context, the git & device guards and the
  Stop regression run in `.codex/hooks.json`, `.gemini/settings.json` and `.cursor/hooks.json` (only
  entries running the bridge are ever touched; JSONC files are left alone). `agent-kit uninstall`
  removes them. Transcript-based gates (review, test evidence, claims) stay Claude-only.
- **Regression matrix from the project's own runner** (`scripts/matrix_detect.py`, `agent-kit matrix`):
  when the profile ships only an illustrative sample (android, ios, universal, …), `agent-kit profile` /
  `init` writes a matrix that runs what the project really has — `./gradlew testDebugUnitTest` / `test`,
  `swift test`, the package.json test script via pnpm/yarn/bun/npm, pytest, `go test ./...`, `cargo test`,
  flutter/dart — watching every source file of the profile. The post-fix gate trusts it uncommitted only
  while byte-identical to a fresh generation (edit `exit 1` → `true` and it becomes UNVERIFIED); an edited
  one is kept as `*_old` on regeneration; `uninstall` removes it while unchanged.
- **RED-check beyond Kotlin/Java:** a test file written this session in JS/TS, Python, Go, Swift, Dart or
  Ruby that ran green must have been run red after its last edit (runner output naming the file when the
  runner names files), mutate/restore pairs handled as for the JVM.
- **Lesson reminder:** after a proven fix ("đã fix" backed by RED→GREEN or workflow proof) with no
  `agent-kit learn` / `--record-lesson` in the session, the Stop is held once with the command to run;
  the next stop passes. `LESSON_REMINDER=0` turns it off.
- `agent-kit index-memory` defaults to the current project's `.agents/instincts.md`, not the DevKit's.
- **Found by a 100-scenario end-to-end simulation, fixed:** a passing `node --test` run ("ℹ fail 0")
  and a test named "shows error message" read as RED (the failure regex was case-insensitive), so a
  correct TDD flow on a Node project was held forever; `agent-kit learn` called through a quoted path
  did not count as a recorded lesson; chit-chat ("cảm ơn…", "thời tiết…") pulled in unrelated traps —
  with no intent detected, a trap now needs a strong match (3+ points).
- **Found by a 100-scenario Android/iOS simulation, fixed:** the device gate now blocks `adb shell pm
  uninstall|disable-user|hide` of system packages (SystemUI, GMS, vendor), `fastlane match nuke`,
  `security delete-keychain|identity|certificate`, removing provisioning profiles / keychains and
  `xcrun simctl erase|delete all`; the post-fix gate rejects committed `local.properties` /
  `keystore.properties` (core-rules §1), SwiftPM dependencies on a `branch:` and secrets in property
  lists (`<key>API_KEY</key><string>…</string>`, `$(BUILD_SETTING)` references allowed); prompt context
  recognises "giật", jank, recomposition, memory leak / retain cycle, TestFlight / App Store.
- **Fast path in the Bash gates:** `block-dangerous-git.sh` and `hardware_safety_gate.sh` read the
  command with a bash builtin regex and allow it at once when it has no trigger word
  (case-insensitive) and no backslash, quote, `$`, backtick or glob character — ~73 ms and ~91 ms per
  Bash call down to ~5 ms for `ls`, `npm test`, `./gradlew …`. Anything else still goes to the full
  parser. Found while testing it and fixed in the parsers: `GIT reset --hard`, `/usr/bin/g?t …`
  (git guard) and `ADB remount`, `a?b remount`, `a""db remount`, `Fastboot flash`, `RM -rf /system`
  (device gate) got through — macOS resolves upper-case names and the shell expands globs/quotes.
- **`agent-kit clean [path] [--days=N] [--apply] [--old-installs]`** (`scripts/devkit_clean.py`):
  removes hook logs, per-session state, `restore-backup/` copies and `adb-safe-exec/` evidence in
  `.claude/audit-gate` older than N days (default 14), trims logs over 5 MB to their last 2000 lines;
  `--old-installs` also removes old `~/.universal-agent-devkit.old-*` copies. Dry-run unless
  `--apply`; never touches code, `.agents/` or `.gitignore`.
- Docs: `AGENTS.md` §7 lists what each platform actually enforces; §8.2 and `core-rules.md` §16 mark
  hook-enforced steps `[hook]` and drop the "Zero Manual Effort" / "CỔNG BẮT BUỘC" claims no hook backed;
  §2.3 asks for real evidence (screenshot for UI, test output for CLI/backend) instead of a PASS
  screenshot for every report.

### Android
- **`profiles/android/scripts/qa/adb-safe-exec.sh`:** runs an adb command and FAILs on error text adb
  prints with exit 0 (`Error type 3`, `Failure [`, `INSTRUMENTATION_FAILED`) and on a FATAL
  EXCEPTION / ANR / fatal signal of the package in logcat since the command started (device clock).
  No or several devices ⇒ exit 3, never a pass; commands `hardware_safety_gate.sh` blocks are refused.
- **`anr-logcat-triage.sh`:** no online device is now exit 3 (UNVERIFIED) instead of exit 0.

### Docs
- **`AGENTS.md` §7.1 — parallel agents, one git worktree each:** how to create one (Claude Code
  `isolation: "worktree"` / `EnterWorktree`, else `git worktree add ../<repo>-<task>`), what a new
  worktree lacks (untracked local config, a symlink-mode DevKit install → `agent-kit init` inside
  it), one device per agent at a time, acceptance only on a gate run inside the worktree with
  `CLAUDE_PROJECT_DIR` pointing at it, bringing the result back as a patch unless commits were
  asked for, and which clean-up steps are the user's (the git guard blocks `--force` removal).

## 1.1.0 — 2026-09-23

A PO + QA review of the whole DevKit found 58 verified defects (1 critical, 13 high) and a gap
between what the docs claimed and what the code did. This release fixes them.

### Security / gates
- **post-fix gate:** test commands are read from the regression matrix at `HEAD`; a matrix or an
  existing test edited in the same change is UNVERIFIED, never PASS (previously an agent could turn
  `exit 1` into `true` and pass). Secret scan whitelists only exact example suffixes, detects AWS/GitHub/
  Slack/Google keys, JWTs, private keys, base64 and unquoted values; test files are recognised by
  directory/suffix, not by the substring "test". `--diff` values starting with `-` are refused. Lessons
  are recorded only after a PASS. DevKit-installed links no longer count as user changes. Output labels
  each section BLOCKING or REMINDER.
- **hooks:** `block-dangerous-git` catches subshells, `if`/`{}` blocks, `timeout`/`nice`/`sudo -u`/`watch`/
  `find -exec`/`xargs` wrappers, `$var` commands, git aliases and `os.system`/`subprocess`; `git restore
  --staged` is allowed. `hardware_safety_gate` handles flags before subcommands, `rm -fr /system`,
  `dd of=/dev/…`, and fails closed on bad JSON. `security_gate` only accepts a real review (not `echo
  security-check`) and sees Bash writes to sensitive files. `precode_gate`/`security_gate` fail closed
  without python3; the rest warn. Stop gates block one re-stop, then release with a logged warning.
  Hooks create `.claude/audit-gate/.gitignore`. `contract_facts_test.sh` rewritten for this repo.

### Installer / CLI
- `agent-kit init [path] [opts]` works with a path and with flags, and without a TTY.
- Unknown options, profiles, modes and languages exit 2 before writing anything.
- A project's own `commands/`, `rules/`, `skills/` directories are left in place (skipped with a warning)
  instead of being renamed to `*_old`.
- The installer no longer writes into the DevKit checkout; copy mode is honoured by every adapter;
  per-file hash ledger (`.devkit-files`) so upgrades only back up files the user edited; backups of
  commands/hooks go to a sibling `<dir>_old/` (no more `/fix_old` commands); same-second backups never
  clobber each other; `.gitignore` entries are added to git projects; symlink mode warns in git repos.
- `make install` / `agent-kit install-global` also install `postfix-gate`.
- New `agent-kit restore-old [path] [--apply]` puts recorded `*_old` backups back (dry-run by default,
  never overwrites content that is not the DevKit's; recreates install dirs `uninstall` removed).
- New `agent-kit uninstall [path] [--apply]` (`scripts/devkit_uninstall.py`, dry-run by default) removes
  only DevKit content: links into the DevKit, copies still matching `.devkit-files`/`.devkit-copy`,
  DevKit hook entries in `.claude/settings.json`, unchanged DevKit MCP servers, marker blocks, and
  unmodified template files. JSON files are backed up (`*_old.uninstall-<time>`) and written atomically.
  `tests/test_uninstall.sh`: install + uninstall + restore-old gives back the original project.

### Profiles / health / scripts
- `agent-kit profile` writes to the git root of the current directory (refuses the DevKit itself), backs
  up instead of deleting, accepts positional/case-insensitive names and aliases, writes the matrix to
  `.agents/regression_matrix.active.json`.
- `agent-kit health` no longer prints hard-coded test results; tests are "not run" unless `--run-tests`.
- Councils: one list of 10, duplicates removed; profiles reference only existing councils and MCPs
  (Unity/Blender MCPs are listed as external for the game profile).
- `voice-assistant` profile gained `DESIGN.md` and `instincts.md`.
- Linters are documented as regex-based, support multi-line signatures and exit 2 on a missing path.
- The `scripts/audit_*` "agent" scripts are relabelled as grep-based self-consistency checks.
- **New profiles `web` and `backend`** (rules, `DESIGN.md`, `instincts.md`, regression matrix that
  detects pnpm/yarn/bun/npm, go, cargo or pytest and fails when no runner is found). `-y` maps the
  detected web/backend domain to them; aliases `frontend/react/nextjs` and `server/api`.
- **Skills filtered per profile:** `profile.json` takes `exclude_skills` (or an allow-list `skills`);
  only allowed skills and their commands are linked. universal/web/backend/ios drop the Android/Unity
  skills, game drops the Android ones.
- **i18n:** installer, adapters, `agent-config`, `agent-health` and the post-fix gate print English or
  Vietnamese: `--lang` > `$DEVKIT_LANG` > `lang` in `.active-profile.json` > `vi`.
- Fixed: the gate did not read `.agents/regression_matrix.active.json` (the new matrix location); an
  uncommitted matrix byte-identical to a DevKit profile matrix is trusted, an edited one is UNVERIFIED.
- `hooks/regression_gate.sh` and `bin/regression_checklist.py` (regression checklist gate) were added in
  a parallel change during this release.
- `profiles/ios/regression_matrix.json` moved from a `checklist` list (silently ignored by the gate) to
  the `rules`/`watch_files`/`mandatory_regression_tests` schema; REG-MEM-01 ran `… || true` and could never
  fail — it now runs `swift test --filter RetainCycleTests`. `test_repo_consistency.sh` checks every
  profile matrix has the schema the gate reads and no test command ends in `|| true`.

### CI (`.github/workflows/devkit-ci.yml` in the monorepo)
- Step names no longer carry fixed counts or retired claims; `actions/setup-node` pinned to a commit SHA
  (v4.4.0); Node 22 (Node 20 is end-of-life; `workflows/*.test.mjs` pass on 20.20.2 and 22.23.2).
- `py_compile` covers `bin/*.py` and `scripts/*.py`; `bash -n` covers `bin`, `hooks`, `hooks/tests`,
  `scripts`, `adapters` and `tests`; a step prints whether ruby (strict YAML frontmatter check) exists.

### Catalog / docs
- 10 documented aliases now exist (`/adr /android-qa /deprecate /enrich /grill /logging /module-design
  /postfix-gate /skill-author /step`).
- `skills/giao` frontmatter is valid YAML; references to another repo's `.Codex/` and `rulebook/` removed;
  `qc` detects the build tool for non-Gradle projects; `qc`/`deploy` state their Android scope.
- README EN/VI: Quick Start moved to the top; counts and claims corrected ("8-layer" gate, "AST linter",
  "50 agents", fixed test totals removed); new sections: which QA command when, Team/CI, uninstall/
  restore, troubleshooting.
- MCP npm packages pinned to exact versions.
- Added `LICENSE` (MIT) and this changelog; plugin version 1.1.0.
- New `tests/test_repo_consistency.sh` keeps links, JSON, frontmatter, documented commands and
  documented counts honest; `agent-kit test` also runs `contract_facts_test.sh`.
- **QA ladder / renamed commands:** the QA commands now run as `/plan-tests` (qa-review) →
  `/review-code` (open-code-review) → `/check` (qc) → `/done` (verification-before-completion) +
  `/audit-gate`. **Deprecated:** `/review` → `/plan-tests` (it collided with the agent's built-in
  `/review`), `/qa` and `/test` → `/check`, `/bugs` and `/crashlytics` → `/fix`. The old names are
  kept for this release only as stub commands (marked `<!-- devkit:deprecated-alias -->`, generated by
  `scripts/sync_commands.sh` from `DEPRECATED_ALIASES`) that run the same skill and tell the user the
  new name; they are **removed in 1.2.0**.
- **Rulebook de-duplicated:** `AGENTS.md` and `rules/core-rules.md` (both `@`-imported every session)
  no longer repeat the same sections; each rule lives in one place and the other file points to it.
  No MUST/NEVER rule was dropped.

### Action needed by maintainers
- Local state files are still tracked from earlier commits. `.gitignore` now lists them; untrack them
  once with:
  `git rm --cached .active-profile.json .antigravity-pm.json .claude/settings_old.json templates/regression_matrix.active.json templates/last_postfix_audit_report.md`
- Symlinks committed before this release were absolute; the working tree now uses relative links —
  commit them.

## 1.0.0

Initial release.
