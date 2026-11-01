#!/usr/bin/env bash
# BUG-REV-ci-dep-scans / BUG-REV-ci-triggers — the CI review layer (.github/workflows/pr-review.yml) scans dependencies
# (dependency-review, osv-scanner, pip-audit, npm audit), pins every tool exactly (no ranges), and also runs on push to
# main and in the merge queue (audit 31/10: a PR-only workflow let a direct push or a queued merge skip it).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(cd "$HERE/../../.." && pwd)/.github/workflows/pr-review.yml"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$W" ] || { echo "skip: no $W (devkit outside the monorepo)"; exit 0; }
python3 - "$W" <<'PY' || FAILS=$((FAILS + 1))
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
on = s.split("\npermissions:")[0]
checks = {
    "runs on pull_request": "\n  pull_request:" in on,
    "runs on push to main": re.search(r"\n  push:\n    branches: \[main\]", on) is not None,
    "runs in the merge queue": "\n  merge_group:" in on,
    "dependency-review pinned to a commit": re.search(r"actions/dependency-review-action@[0-9a-f]{40}\b", s) is not None,
    "osv-scanner with a checksum": "osv-scanner" in s and re.search(r"osv-scanner[\s\S]{0,400}sha256sum -c", s) is not None,
    "pip-audit pinned exactly": re.search(r"pip-audit==\d+\.\d+\.\d+", s) is not None,
    "npm audit": "npm audit --omit=dev --audit-level=high" in s,
    "semgrep pinned exactly": re.search(r"semgrep==\d+\.\d+\.\d+", s) is not None and "semgrep>=" not in s,
    "ocr-review --strict enabled (#751)": "ocr-review --strict --from" in s and "@alibaba-group/open-code-review@1.13.3" in s and "TẠM TẮT theo" not in s,
    "every action pinned to a commit": all(re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", u) for u in re.findall(r"uses:\s*(\S+)", s)),
}
# BUG-REV-ci-npm-ci-no-lockfile (run 41185270960): `npm ci` exits EUSAGE without a lockfile, and the root .gitignore drops
# package-lock.json, so every directory the workflow runs `npm ci` in must have its lockfile tracked by git.
import os, subprocess
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(sys.argv[1]))))
tracked = set(subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True).stdout.splitlines())
for d in sorted(set(re.findall(r"cd\s+(\S+?)\s*&&\s*npm ci\b", s))):
    checks["npm ci lockfile tracked: " + d] = any(d + "/" + f in tracked for f in ("package-lock.json", "npm-shrinkwrap.json"))
bad = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("✔ " if v else "✖ ") + k)
sys.exit(1 if bad else 0)
PY
[ "$FAILS" -eq 0 ] && echo "pr-review workflow: all checks passed" || { echo "pr-review workflow: FAILED"; exit 1; }
