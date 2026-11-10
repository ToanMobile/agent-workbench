#!/usr/bin/env bash
# #781: the CI job that runs the whole DevKit suite (run_impacted.sh --all) must exist on main, run on macOS (the tests are
# written for BSD tools, launchctl, xcrun: 35 files were red on ubuntu, run 41209128293), set a git identity (the
# worktree/automerge tests commit), pin its action to a commit, and be enabled (not a comment).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(cd "$HERE/../../.." && pwd)/.github/workflows/pr-review.yml"
[ -f "$W" ] || { echo "✖ missing $W"; exit 1; }
python3 - "$W" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
live = "\n".join(l for l in s.splitlines() if not l.lstrip().startswith("#"))
on = live.split("\npermissions:")[0]
checks = {
    "runs on pull_request": "\n  pull_request:" in on,
    "runs on push to main": re.search(r"\n  push:\n    branches: \[main\]", on) is not None,
    "job runs on macos-latest": "runs-on: macos-latest" in live,
    "no ubuntu runner for the DevKit suite": "ubuntu" not in live,
    "run_impacted.sh --all is enabled (not commented)": "bash universal-agent-devkit/tests/run_impacted.sh --all" in live,
    "git user.name set before the tests": re.search(r"git config --global user\.name[\s\S]*run_impacted\.sh --all", live) is not None,
    "git user.email set before the tests": re.search(r"git config --global user\.email[\s\S]*run_impacted\.sh --all", live) is not None,
    "job has a timeout": re.search(r"timeout-minutes:\s*\d+", live) is not None,
    "every action pinned to a commit": all(re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", u) for u in re.findall(r"uses:\s*(\S+)", live)),
}
for k, v in checks.items():
    print(("✔ " if v else "✖ ") + k)
sys.exit(1 if not all(checks.values()) else 0)
PY
