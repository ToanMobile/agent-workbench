# Super Review — when to use

Use this skill for:

- PR or branch review before merge.
- Code, architecture, security, data-model, or migration judgment.
- Release-readiness checks after Super Build, Super QA, or a human's `/ui-refine-loop` pass.
- The Review lane of a `super-board run`.
- A final pass that needs risks, blockers, and human gates summarized.

Do **not** use this as the primary implementation workflow. Route fixes to:

- **Super Build** for feature/task implementation from GitHub Project `Ready` issues.
- **Super QA** for functional bugs, broken behavior, failing Playwright paths, or missing QA coverage.
- Visual fidelity, layout, screenshots, wireframes, or design-system drift: file a UI ticket; a human can run `/ui-refine-loop`. The board never triggers it.

