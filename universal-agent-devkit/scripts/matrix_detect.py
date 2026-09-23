#!/usr/bin/env python3
"""matrix_detect.py — a regression matrix built from the project's own test runner.

Usage: matrix_detect.py <project_dir> [--write]
  prints the generated matrix (or "none" and exit 3 when no runner is found);
  --write stores it as <project>/.agents/regression_matrix.active.json

The profile sample matrices of android / ios / universal name illustrative tests
(`*.TransactionDebounceTest`) that do not exist in a real project, so the Stop-time
regression gate could never enforce them. This detects what the project really runs
— gradle, swift test, the package.json test script (pnpm/yarn/bun/npm by lockfile),
pytest, go, cargo, flutter/dart — and writes one rule that watches every source file
of the active profile (hooks/devkit_profile.py) and runs that suite.

The output is deterministic for a given project + profile: post-fix-gate trusts an
uncommitted matrix only when it is byte-identical to a fresh generation, so an agent
cannot turn a test command into `true` without the gate noticing.
"""

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hooks"))
sys.dont_write_bytecode = True
from devkit_profile import source_exts  # noqa: E402

MARKER = "agent-kit (scripts/matrix_detect.py)"
NPM_DEFAULT_TEST = "no test specified"


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def detect(project):
    """[(name, command)] for every test runner the project root declares."""
    has = lambda *names: any(os.path.exists(os.path.join(project, n)) for n in names)  # noqa: E731
    found = []
    if has("gradlew"):
        gradle = " ".join(_read(p) for p in glob.glob(os.path.join(project, "*", "build.gradle*"))
                          + glob.glob(os.path.join(project, "build.gradle*")))
        android = "com.android.application" in gradle or "com.android.library" in gradle
        found.append(("Gradle unit tests", "./gradlew testDebugUnitTest" if android else "./gradlew test"))
    if has("Package.swift"):
        found.append(("Swift package tests", "swift test"))
    pkg = os.path.join(project, "package.json")
    if os.path.isfile(pkg):
        try:
            test_script = (json.loads(_read(pkg)).get("scripts") or {}).get("test", "")
        except ValueError:
            test_script = ""
        if test_script and NPM_DEFAULT_TEST not in test_script:
            runner = ("pnpm test" if has("pnpm-lock.yaml") else "yarn test" if has("yarn.lock")
                      else "bun run test" if has("bun.lockb", "bun.lock") else "npm test")
            found.append(("package.json test script", runner))
    py_cfg = _read(os.path.join(project, "pyproject.toml")) + _read(os.path.join(project, "setup.cfg"))
    if (has("pytest.ini", "conftest.py", "tox.ini") or "pytest" in py_cfg
            or glob.glob(os.path.join(project, "tests", "test_*.py"))
            or glob.glob(os.path.join(project, "test", "test_*.py"))):
        found.append(("pytest", "python3 -m pytest -q"))
    if has("go.mod"):
        found.append(("Go tests", "go test ./..."))
    if has("Cargo.toml"):
        found.append(("Cargo tests", "cargo test"))
    if has("pubspec.yaml"):
        found.append(("Flutter/Dart tests", "flutter test" if "flutter" in _read(os.path.join(project, "pubspec.yaml")) else "dart test"))
    return found


def generate(project):
    """The matrix as bytes, or None when the project declares no test runner."""
    runners = detect(project)
    if not runners:
        return None
    exts = sorted(source_exts(project))
    matrix = {
        "version": "1.0.0",
        "generated_by": MARKER,
        "project": os.path.basename(os.path.abspath(project)),
        "description": "Generated from the project's own test runner(s). Edit freely and commit it "
                       "(a committed matrix is used as is); re-run `agent-kit profile <id>` to regenerate.",
        "rules": [{
            "component": "ProjectTestSuite",
            "watch_files": [f"**/*{e}" for e in exts],
            "mandatory_regression_tests": [
                {"id": f"REG-AUTO-{i:02d}", "name": name, "command": cmd}
                for i, (name, cmd) in enumerate(runners, 1)
            ],
        }],
    }
    return (json.dumps(matrix, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def is_generated_unchanged(project, content: bytes) -> bool:
    return content is not None and content == generate(project)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    project = os.path.abspath(argv[1])
    data = generate(project)
    if data is None:
        print("none — no test runner found (gradlew, Package.swift, package.json test script, pytest, go.mod, Cargo.toml, pubspec.yaml)")
        return 3
    if "--write" in argv[2:]:
        dest = os.path.join(project, ".agents", "regression_matrix.active.json")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
        print(f"wrote {dest}")
    else:
        sys.stdout.write(data.decode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
