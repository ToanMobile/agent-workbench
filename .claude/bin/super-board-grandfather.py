#!/usr/bin/env python3
"""TEMPORARY grandfather window for the signed 4-way review verdict (super-board-merge-gate.sh, BUG-REV-merge-gate-grandfather).

PR #742 made the merge gate require a signed review-fanout PASS for the PR head. PRs opened BEFORE #742 (createdAt < CUTOFF) were
built and reviewed under the old rules, so until EXPIRY the gate skips only that verdict check for them; every other check (CI
checks readable + green, --match-head-commit, merge lock, scratch verify, merge policy / machine_gate) still applies, and a
machine-gated PR never gets the window. After EXPIRY, or for a PR created at/after CUTOFF, or when createdAt is missing or
unparsable, the answer is "not grandfathered" (fail-closed). The constants are hardcoded on purpose: no env var or flag can widen
the window, and the CLI always uses the real clock (decide() takes `now` only for unit tests).
Remove this file and its call in the gate after 2026-11-01.

  super-board-grandfather.py --created <ISO-8601>   exit 0 + one log line = grandfathered; exit 1 = full rules
"""
import sys
from datetime import datetime, timezone

CUTOFF = "2026-10-31T08:21:22Z"          # createdAt of PR #742 (gh pr view 742 --json createdAt)
EXPIRY = "2026-11-01T06:00:00+07:00"     # window closes by itself


def parse(ts):
    if not isinstance(ts, str) or not ts.strip():
        raise ValueError("empty timestamp")
    t = datetime.fromisoformat(ts.strip().replace("Z", "+00:00"))
    if t.tzinfo is None:
        raise ValueError("timestamp without a zone: %r" % ts)
    return t


def decide(created, now):
    """(True, line) when the PR is inside the window, else (False, reason). Never raises."""
    try:
        c = parse(created)
    except (ValueError, TypeError) as e:
        return False, "createdAt unreadable (%s): full rules" % e
    cutoff, expiry = parse(CUTOFF), parse(EXPIRY)
    if now >= expiry:
        return False, "grandfather window expired at %s: full rules" % EXPIRY
    if c >= cutoff:
        return False, "created %s, not before cutoff %s: full rules" % (created, CUTOFF)
    return True, "created %s < cutoff %s), expires %s" % (created, CUTOFF, EXPIRY)


def main(argv):
    if len(argv) != 2 or argv[0] != "--created":
        print("usage: super-board-grandfather.py --created <ISO-8601>", file=sys.stderr)
        return 2
    ok, line = decide(argv[1], datetime.now(timezone.utc))
    print(line)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
