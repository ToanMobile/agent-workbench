#!/usr/bin/env python3
"""Git merge driver for .agents/regression_matrix.active.json (agent-workbench #221).

The gate trusts a matrix change when it only INSERTS rules: the base rules stay, in order, as a subsequence
(bin/matrix_slot.py, the one classifier the gate, this driver and `agent-kit matrix add` share). New rules go in at the
hashed slot of their component, not at the end, so two PRs with different slots merge clean with plain git — GitHub does
not run this driver. This driver merges by slot: before base rule k it puts what each side inserted there, the side that
IS origin/main's matrix first (merging main into a PR branch: `theirs`; the gate compares with origin/main), then the
other side. With no overlap that is exactly `git merge-file`'s result; with the same slot on both sides (or both
appending at the end, the old way) it still merges where the text merge conflicts.

  matrix_merge_driver.py %O %A %B %P      (base, ours — the result is written here —, theirs, path)

exit 0  merged (result in %A)
exit 1  conflict: the same test id inserted on both sides with different content (named on stderr), or a change
        that is not insert-only (existing rule edited, top-level key changed on both sides): git's own text merge
        runs instead, so an overlap leaves the usual conflict markers.
"""
import json
import subprocess
import sys
from pathlib import Path

# bin/matrix_slot.py của chính kit này (đường dẫn thật qua symlink .agents/devkit); không nạp được thì merge-file như cũ
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
try:
    import matrix_slot
except ImportError:
    matrix_slot = None


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
    if matrix_slot is None:
        return None, "bin/matrix_slot.py not found next to the driver"
    if origin_rules is not None and theirs["rules"] == origin_rules and ours["rules"] != origin_rules:
        ours, theirs = theirs, ours   # main's insertions first, the branch's after: insert-only against origin/main
    base_rules = base["rules"]
    # [(k, rule)] per side; a side whose rules did not change inserts nothing (it may have changed a top-level key)
    add_o, add_t = ([] if side["rules"] == base_rules else matrix_slot.split(base_rules, side["rules"]) for side in (ours, theirs))
    if add_o is None or add_t is None:
        return None, "an existing rule was edited (or an inserted rule is not insert-only)"
    top_b, top_o, top_t = _top(base), _top(ours), _top(theirs)
    if top_o != top_b and top_t != top_b and top_o != top_t:
        return None, "a top-level key changed on both sides"
    rules_o = [rule for _, rule in add_o]
    taken = {i for r in rules_o for i in _test_ids(r)}
    at = {}   # k -> rules inserted before base rule k (k == len(base): appended)
    for k, rule in add_o:
        at.setdefault(k, []).append(rule)
    for k, rule in add_t:
        if rule in rules_o:   # the same rule inserted on both sides: once, where ours put it
            continue
        dup = sorted(set(_test_ids(rule)) & taken)
        if dup:
            return None, f"id: test id {', '.join(dup)} added on both sides with different content"
        at.setdefault(k, []).append(rule)
    merged = dict(top_t if top_o == top_b else top_o)
    merged["rules"] = [r for k in range(len(base_rules) + 1) for r in at.get(k, []) + base_rules[k:k + 1]]
    if (add_o or add_t) and matrix_slot.split(base_rules, merged["rules"]) is None:
        # mỗi phía hợp lệ nhưng bản gộp thì không (vd. cùng một component thêm ở cả hai phía): để merge-file quyết như GitHub
        return None, "the merged insertions are not insert-only together (the same component added on both sides)"
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
