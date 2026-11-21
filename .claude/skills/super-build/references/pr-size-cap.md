# Super Build — PR size cap (only when `merge_policy.auto_max_lines` is positive)

Moved verbatim from SKILL.md → "Keep each PR small" (#1420). Unset `auto_max_lines` is 0: no cap, skip this file.

When the cap is a positive number, check `git diff --shortstat origin/<base>...HEAD` (minus excluded
files) before each push. If the change grows past that cap mid-build, **stop — do not push on**.
Commit and push what you have on the branch, leave the PR as a draft, and post a PR comment
proposing the split: the vertical slices (each thin end to end, under the cap, with its own ACs),
which slice this PR keeps, and `/to-tickets` as the way to file the rest. Then move the card to
Blocked with `❓` ("too big — split proposed in PR #<P>", `block-template.md`). Never pad past the
cap to "finish" the ticket. When the cap is 0, do not stop or split for line count.

