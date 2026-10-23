#!/usr/bin/env python3
"""Git merge driver for .agents/regression_matrix.active.json (agent-workbench #221).

The gate trusts a matrix change only when the new rules sit at the END of "rules" (post-fix-gate.matrix_additions),
so two PRs that each append a rule edit the same last lines and the second one to merge goes CONFLICTING.
This driver merges the two sides as a union of appended rules: base rules, then what `ours` appended, then what
`theirs` appended — still append-only against the base, so the gate keeps trusting it. The gate compares with
origin/main, so the side that IS origin/main's matrix (merging main into a PR branch: `theirs`) goes first.

  matrix_merge_driver.py %O %A %B %P      (base, ours — the result is written here —, theirs, path)

exit 0  merged (result in %A)
exit 1  conflict: the same test id appended on both sides with different content (named on stderr), or a change
        that is not an append (existing rule edited, top-level key changed on both sides): git's own text merge
        runs instead, so an overlap leaves the usual conflict markers.
"""
import json
import subprocess
import sys


def _load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and isinstance(data.get("rules"), list) else None


def _test_ids(rule):
    tests = rule.get("mandatory_regression_tests") if isinstance(rule, dict) else None
    return [t["id"] for t in tests or [] if isinstance(t, dict) and isinstance(t.get("id"), str)]


def _top(d):
    return {k: v for k, v in d.items() if k != "rules"}


def _origin_rules(path):
    """Rules of the matrix on origin/<default branch>, or None when there is no such ref (a bare test repo)."""
    for ref in ("refs/remotes/origin/HEAD", "refs/remotes/origin/main"):
        try:
            out = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True, timeout=10)
            if out.returncode == 0:
                data = json.loads(out.stdout)
                return data.get("rules") if isinstance(data, dict) else None   # a non-object matrix is "no origin"
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    return None


def merge(base, ours, theirs, origin_rules=None):
    """(merged dict, None) or (None, reason). A reason starting with 'id:' is a real duplicate, not a fallback."""
    if origin_rules is not None and theirs["rules"] == origin_rules and ours["rules"] != origin_rules:
        ours, theirs = theirs, ours   # main's additions first, the branch's after: append-only against origin/main
    n = len(base["rules"])
    if ours["rules"][:n] != base["rules"] or theirs["rules"][:n] != base["rules"]:
        return None, "an existing rule was edited"
    top_b, top_o, top_t = _top(base), _top(ours), _top(theirs)
    if top_o != top_b and top_t != top_b and top_o != top_t:
        return None, "a top-level key changed on both sides"
    add_o, add_t = ours["rules"][n:], theirs["rules"][n:]
    taken = {i for r in add_o for i in _test_ids(r)}
    kept = []
    for rule in add_t:
        if rule in add_o:   # the same rule appended on both sides: once
            continue
        dup = sorted(set(_test_ids(rule)) & taken)
        if dup:
            return None, f"id: test id {', '.join(dup)} added on both sides with different content"
        kept.append(rule)
    merged = dict(top_t if top_o == top_b else top_o)
    merged["rules"] = base["rules"] + add_o + kept
    return merged, None


def main(argv):
    if len(argv) < 4:
        print("usage: matrix_merge_driver.py BASE OURS THEIRS [PATH]", file=sys.stderr)
        return 2
    base_p, ours_p, theirs_p = argv[1:4]
    base, ours, theirs = _load(base_p), _load(ours_p), _load(theirs_p)
    merged, reason = (None, "a side is not a matrix") if not (base and ours and theirs) else merge(base, ours, theirs, _origin_rules(argv[4] if len(argv) > 4 else ".agents/regression_matrix.active.json"))
    if merged is not None:
        with open(ours_p, "w", encoding="utf-8") as f:
            f.write(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
        return 0
    label = argv[4] if len(argv) > 4 else "regression matrix"
    print(f"matrix_merge_driver: {label}: {reason[4:] if reason.startswith('id:') else reason}", file=sys.stderr)
    # Not an append: git's text merge decides (clean when the edits do not overlap, markers when they do). A duplicate
    # id fails whatever it says, but it still writes the markers, so a `git add` right after cannot keep only ours' rule.
    text_conflict = subprocess.run(["git", "merge-file", ours_p, base_p, theirs_p]).returncode
    return 1 if text_conflict or reason.startswith("id:") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
