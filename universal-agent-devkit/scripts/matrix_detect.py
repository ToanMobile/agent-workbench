#!/usr/bin/env python3
"""matrix_detect.py — a regression matrix built from the project's own test runner.

Usage: matrix_detect.py <project_dir> [--write]
  prints the generated matrix (or "none" and exit 3 when no runner is found);
  --write stores it as <project>/.agents/regression_matrix.active.json

Monorepos: first-level folders with their own runner (CarConnect/gradlew,
PCConnect/go.mod …) each get a rule that watches only that folder and runs
`cd <folder> && <runner>`, so a change runs only the suites it can affect. A folder
the root runner already covers (JS workspaces, Cargo workspace, Gradle settings
include) is left to the root.

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
import shlex
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hooks"))
sys.dont_write_bytecode = True
from devkit_profile import DEFAULT_EXTS, source_exts  # noqa: E402

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
    if glob.glob(os.path.join(project, "*.sln")) or glob.glob(os.path.join(project, "*.csproj")) or glob.glob(os.path.join(project, "*", "*.csproj")):
        found.append((".NET tests", "dotnet test"))
    return found


# Folders that are never a project module.
NOT_MODULES = {"node_modules", "build", "dist", "out", "target", "vendor", "venv", "Pods", "DerivedData",
               "__pycache__", "coverage", "tmp", "docs", "scripts", "tools"}
WORKSPACE_FILES = ("pnpm-workspace.yaml", "lerna.json", "nx.json", "turbo.json", "rush.json")


def _root_covers(project, module, name):
    """Does the root runner already run this module's tests? (JS workspaces, a Cargo
    workspace, a Gradle build whose settings include the module)."""
    if name == "package.json test script":
        if any(os.path.exists(os.path.join(project, f)) for f in WORKSPACE_FILES):
            return True
        try:
            return bool(json.loads(_read(os.path.join(project, "package.json"))).get("workspaces"))
        except ValueError:
            return False
    if name == "Cargo tests":
        return "[workspace]" in _read(os.path.join(project, "Cargo.toml"))
    if name == "Gradle unit tests":
        settings = _read(os.path.join(project, "settings.gradle")) + _read(os.path.join(project, "settings.gradle.kts"))
        return f'"{module}"' in settings or f"'{module}'" in settings or f":{module}" in settings
    return False


def detect_modules(project):
    """[(module, [(name, command)])] for first-level subfolders that declare their own
    test runner — a monorepo like CarConnect/gradlew + PhoneConnect/gradlew + PCConnect/go.mod.
    A module the root runner already covers is left to the root."""
    root = {name for name, _ in detect(project)}
    out = []
    for entry in sorted(os.listdir(project)):
        path = os.path.join(project, entry)
        if entry.startswith(".") or entry in NOT_MODULES or not os.path.isdir(path) or os.path.islink(path):
            continue
        runners = [(n, c) for n, c in detect(path) if not (n in root and _root_covers(project, entry, n))]
        if runners:
            out.append((entry, runners))
    return out


def generate(project):
    """The matrix as bytes, or None when neither the project root nor any first-level
    module declares a test runner."""
    runners = detect(project)
    modules = detect_modules(project)
    if not runners and not modules:
        return None
    exts = sorted(source_exts(project))
    rules = []
    if runners:
        rules.append({
            "component": "ProjectTestSuite",
            "watch_files": [f"**/*{e}" for e in exts],
            "mandatory_regression_tests": [
                {"id": f"REG-AUTO-{i:02d}", "name": name, "command": cmd}
                for i, (name, cmd) in enumerate(runners, 1)
            ],
        })
    # One rule per module: a change in PCConnect/ runs only PCConnect's suite. fnmatch's
    # `*` crosses `/`, so "<module>/*.kt" covers every depth inside the module. Modules of
    # a monorepo can be in any language (a Go service next to Android apps), so they watch
    # every common source extension, not only the active profile's.
    mod_exts = sorted(set(DEFAULT_EXTS) | set(exts))
    for mod, mod_runners in modules:
        tag = "".join(ch if ch.isalnum() else "-" for ch in mod).upper()
        rules.append({
            "component": mod,
            "watch_files": [f"{mod}/*{e}" for e in mod_exts],
            "mandatory_regression_tests": [
                {"id": f"REG-AUTO-{tag}-{i:02d}", "name": f"{mod}: {name}", "command": f"cd {shlex.quote(mod)} && {cmd}"}
                for i, (name, cmd) in enumerate(mod_runners, 1)
            ],
        })
    matrix = {
        "version": "1.0.0",
        "generated_by": MARKER,
        "project": os.path.basename(os.path.abspath(project)),
        "description": "Generated from the project's own test runner(s). Edit freely and commit it "
                       "(a committed matrix is used as is); re-run `agent-kit profile <id>` to regenerate.",
        "rules": rules,
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
        print("none — no test runner found in the project root or its first-level folders "
              "(gradlew, Package.swift, package.json test script, pytest, go.mod, Cargo.toml, pubspec.yaml)")
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
