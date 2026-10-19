#!/usr/bin/env python3
"""REG-GAME-01 compile is skipped only when an edit/play suite is in the same run.

Drives unity_suite_compiles and skip_separate_unity_compile from post-fix-gate.py,
using the commands in profiles/game/regression_matrix.json.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "bin" / "post-fix-gate.py"
MATRIX = ROOT / "profiles" / "game" / "regression_matrix.json"


def load_gate():
    spec = importlib.util.spec_from_file_location("post_fix_gate_under_test", GATE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    gate = load_gate()
    matrix = json.loads(MATRIX.read_text(encoding="utf-8"))
    commands = {
        test["id"]: test["command"]
        for rule in matrix["rules"]
        for test in rule.get("mandatory_regression_tests", [])
    }
    compile_cmd = commands["REG-GAME-01"]
    edit_cmd = commands["REG-GAME-02"]
    play_cmd = commands["REG-GAME-03"]
    same_run = [compile_cmd, edit_cmd, play_cmd]
    will = any(gate.unity_suite_compiles(cmd) for cmd in same_run)
    fails = 0

    def check(cond, label):
        nonlocal fails
        if cond:
            print("✔", label)
        else:
            print("✖", label)
            fails += 1

    check(will, "editmode/playmode in the game matrix counts as a compiling suite")
    check(gate.skip_separate_unity_compile(compile_cmd, will), "REG-GAME-01 compile is skipped when editmode is in the same run")
    check(not gate.skip_separate_unity_compile(compile_cmd, False), "REG-GAME-01 is not skipped when no edit/play suite will run")
    check(not gate.skip_separate_unity_compile(edit_cmd, will), "REG-GAME-02 editmode is not marked as a compile skip")
    check("compile" in compile_cmd and "editmode" in edit_cmd, "matrix commands are the real compile and editmode lines")
    if fails:
        print("test_unity_compile_skip: FAIL (%s)" % fails)
        return 1
    print("test_unity_compile_skip: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
