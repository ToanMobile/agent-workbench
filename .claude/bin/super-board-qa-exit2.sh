#!/usr/bin/env bash
# Phân loại một dòng JSON của post-fix-gate (#643): in đúng một từ pass, review hoặc qa-fail. Luôn thoát 0.
# --root DIR: mọi tests_touched phải là file thường nằm dưới DIR (path tuyệt đối hoặc có ".." thì qa-fail).
root=""
if [ "${1:-}" = "--root" ]; then
  root="${2:-}"
fi
export QA_EXIT2_ROOT="$root"
python3 -c "$(cat <<'PY'
import json, os, sys
from pathlib import Path

def last_obj(text):
    found = None
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("{"):
            continue
        try:
            o = json.loads(s)
        except (ValueError, TypeError):
            continue
        if isinstance(o, dict) and "exit_code" in o:
            found = o
    return found

def review(o, root):
    need = ("test_mode", "tests_touched", "matrix_problem", "unreadable", "uncovered",
            "orphan_tests", "findings", "regression_tests", "busy", "budget_exhausted")
    if any(k not in o for k in need):
        return False
    if o["test_mode"] not in ("impacted", "full"):
        return False
    touched = o["tests_touched"]
    if not isinstance(touched, list) or not touched:
        return False
    if root:
        base = Path(root)
        for p in touched:
            if not isinstance(p, str) or p.startswith("/") or ".." in Path(p).parts:
                return False
            if not (base / p).is_file():
                return False
    if o["matrix_problem"] not in ("", None):
        return False
    for k in ("unreadable", "uncovered", "orphan_tests", "findings"):
        v = o[k]
        if not isinstance(v, list) or v:
            return False
    regs = o["regression_tests"]
    if not isinstance(regs, list) or not regs:
        return False
    kept = False
    for item in regs:
        if not isinstance(item, dict):
            return False
        if item.get("matrix_added") is not True:
            kept = True
        if item.get("status") == "UNTESTED" and item.get("label") != "EDITED":
            return False
    if not kept:
        return False
    return o["busy"] is False and o["budget_exhausted"] is False

def word(text, root):
    o = last_obj(text)
    if o is None:
        return "qa-fail"
    code = o.get("exit_code")
    if code == 0:
        return "pass"
    if code != 2:
        return "qa-fail"
    return "review" if review(o, root) else "qa-fail"

print(word(sys.stdin.read(), os.environ.get("QA_EXIT2_ROOT") or ""))
PY
)" || printf '%s\n' qa-fail
exit 0
