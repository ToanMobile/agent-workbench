#!/usr/bin/env python3
"""matrix_detect.py — a regression matrix built from the project's own test runner.

Usage: matrix_detect.py <project_dir> [--write]
  prints the generated matrix (or "none" and exit 3 when no runner is found);
  --write stores it as <project>/.agents/regression_matrix.active.json

Monorepos: first-level folders with their own runner (CarConnect/gradlew,
PCConnect/go.mod …) each get a rule that watches only that folder and runs
`cd <folder> && <runner>`, so a change runs only the suites it can affect. A folder
the root runner already covers (JS workspaces, Cargo workspace, Gradle settings
include) is left to the root. A folder a module pulls in with includeBuild("../shared")
is also watched by that module's rule, so a change in shared/ runs its consumers too.

The profile sample matrices of android / ios / universal name illustrative tests
(`*.TransactionDebounceTest`) that do not exist in a real project, so the Stop-time
regression gate could never enforce them. This detects what the project really runs
— Unity EditMode (via the game profile's unity-batch.sh), gradle, swift test, the
package.json test script (pnpm/yarn/bun/npm by lockfile), pytest, go, cargo,
flutter/dart, dotnet — and writes one rule that watches every source file of the
active profile (hooks/devkit_profile.py) and runs that suite.

Android Gradle: Android is recognised by com.android.* / alias(libs.plugins.android.*) /
a convention plugin id containing android.application|android.library, or a module's
src/main/AndroidManifest.xml (modules = first-level folders + settings.gradle includes).
It runs ./gradlew testDebugUnitTest, and names a module's own task only when the build
file proves it exists: `testBuildType = "<x>"` → :<module>:test<X>UnitTest (if it has
src/test), productFlavors → :<module>:test, Kotlin Multiplatform → testAndroidHostTest
(withHostTest) / jvmTest (jvm()) / allTests.

The output is deterministic for a given project + profile: post-fix-gate trusts an
uncommitted matrix only when it is byte-identical to a fresh generation, so an agent
cannot turn a test command into `true` without the gate noticing.
"""

import glob
import json
import os
import re
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


def gradle_modules(project):
    """Sorted module dirs (relative, "/"-separated) of a Gradle build: every first-level
    folder with a build.gradle* plus every `include(":a:b")` / `include ':a'` of the
    settings file (":feature:home" → "feature/home"). Reads only the settings file and
    globs one level, so build/ and node_modules/ are never walked."""
    mods = {os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(project, "*", "build.gradle*"))}
    settings = "\n".join(line for line in (_read(os.path.join(project, "settings.gradle"))
                                           + "\n" + _read(os.path.join(project, "settings.gradle.kts"))).splitlines()
                         if not line.lstrip().startswith("//"))
    for args in re.findall(r"\binclude\b\s*(?:\(([^)]*)\)|([^\n]*))", settings):
        for name in re.findall(r"""["']:?([\w.:-]+)["']""", args[0] or args[1]):
            mods.add(name.replace(":", "/"))
    return sorted(m for m in mods if os.path.isdir(os.path.join(project, m)))


ANDROID_MARKERS = ("android.application", "android.library", "libs.plugins.android.")
# kotlin.multiplatform / kotlin("multiplatform") / com.android.kotlin.multiplatform.library /
# android.kmp — not org.jetbrains.compose (compose.multiplatform), which an Android app uses.
KMP_RX = re.compile(r"kotlin\W{0,3}multiplatform|android\.kmp")


def _code(text):
    """A build file without its comment lines and without plugins declared `apply false`
    (a root build declares every plugin that way for its modules): a comment or an
    unapplied plugin must not change the command."""
    return "\n".join(line for line in text.splitlines()
                     if not line.lstrip().startswith(("//", "*", "/*"))
                     and not re.search(r"\bapply\s*\(?\s*false\b", line))


def _test_build_type(code):
    """The `testBuildType = "x"` / `testBuildType 'x'` of a build file, or None."""
    m = re.search(r"""\btestBuildType\s*=?\s*["'](\w+)["']""", code)
    return m.group(1) if m else None


def _kmp_tasks(code):
    """Kotlin Multiplatform has no testDebugUnitTest and no `test`: the Android host tests
    when withHostTest is on, jvmTest for an unnamed jvm() target, else allTests (always
    registered by the plugin)."""
    tasks = (["testAndroidHostTest"] if "withHostTest" in code else []) \
        + (["jvmTest"] if re.search(r"\bjvm\s*\(\s*\)", code) else [])
    return tasks or ["allTests"]


def _gradle_command(project):
    """./gradlew test for a JVM build. For Android, only task names that the build files
    prove exist: testDebugUnitTest (matched by name in every module that has it), plus per
    module — testBuildType <x> ≠ debug → :<module>:test<X>UnitTest (AGP creates unit-test
    variants only for the testBuildType; the name match would skip it silently; a module
    without src/test has nothing to skip); productFlavors → :<module>:test (each variant is
    test<Flavor><Type>UnitTest, testDebugUnitTest does not exist); Kotlin Multiplatform →
    its host/JVM test task or allTests. A single-project build is its own only module."""
    mods = gradle_modules(project)
    units = mods or [""]
    code = {m: _code(" ".join(_read(p) for p in sorted(glob.glob(os.path.join(project, m, "build.gradle*")))))
            for m in units}
    everything = " ".join([_code(_read(p)) for p in sorted(glob.glob(os.path.join(project, "build.gradle*")))]
                          + list(code.values()))
    # com.android.application, alias(libs.plugins.android.application), a convention
    # plugin id("acme.android.library"), or just a module manifest.
    android = (any(k in everything for k in ANDROID_MARKERS)
               or any(os.path.isfile(os.path.join(project, m, "src", "main", "AndroidManifest.xml")) for m in units))
    if not android and not KMP_RX.search(everything):
        return "./gradlew test"
    tasks, by_name = [], False
    for m in units:
        c, path = code[m], f":{m.replace('/', ':')}:" if m else ""
        tbt = _test_build_type(c)
        if KMP_RX.search(c):
            tasks += [path + t for t in _kmp_tasks(c)]
        elif "productFlavors" in c or "flavorDimensions" in c:
            tasks.append(path + "test")
        elif tbt and tbt != "debug":
            if os.path.isdir(os.path.join(project, m, "src", "test")):
                tasks.append(f"{path}test{tbt[0].upper() + tbt[1:]}UnitTest")
        else:
            by_name = True
    tasks = (["testDebugUnitTest"] if by_name else []) + tasks
    return "./gradlew " + " ".join(shlex.quote(t) for t in tasks or ["test"])


def is_unity(project):
    return (os.path.isdir(os.path.join(project, "Assets"))
            and os.path.isfile(os.path.join(project, "ProjectSettings", "ProjectVersion.txt")))


def detect(project):
    """[(name, command)] for every test runner the project root declares."""
    has = lambda *names: any(os.path.exists(os.path.join(project, n)) for n in names)  # noqa: E731
    found = []
    # Unity first: Rider/VS generate *.sln/*.csproj inside a Unity project, and `dotnet test`
    # does not run Unity tests. EditMode through the profile script (it also compiles and
    # fails on `error CS…`). A project's own scripts/unity-test.sh is not used: it is free-form
    # (the Goods one is a multi-phase acceptance run with a PlayMode bot, far past the gate's
    # per-test timeout) — edit the generated matrix to point at it.
    unity = is_unity(project)
    if unity:
        found.append(("Unity EditMode tests", "bash .agents/active-profile/scripts/unity-batch.sh editmode"))
    if has("gradlew"):
        found.append(("Gradle unit tests", _gradle_command(project)))
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
    if not unity and (glob.glob(os.path.join(project, "*.sln")) or glob.glob(os.path.join(project, "*.csproj"))
                      or glob.glob(os.path.join(project, "*", "*.csproj"))):
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
        # A Gradle build with no test sources at all (a KMP `shared/` library) would run
        # zero tests and report green: no rule of its own — the modules that includeBuild
        # it watch it, and anything else it changes shows up as uncovered.
        runners = [(n, c) for n, c in runners if n != "Gradle unit tests" or gradle_has_tests(path)]
        if runners:
            out.append((entry, runners))
    return out


def gradle_has_tests(build_dir):
    """Any test source set in the build: src/test, src/androidTest, src/commonTest,
    src/jvmTest … in the build's root project or modules up to two levels deep."""
    return any(glob.glob(os.path.join(build_dir, *(["*"] * depth), "src", pat))
               for depth in (0, 1, 2) for pat in ("test", "*Test", "*Tests"))


def included_builds(project, module):
    """Sorted folders (relative to the project, inside it) that a module's settings file
    pulls in as a composite build — includeBuild("../shared") / includeBuild '../shared'.
    A change there changes what the module builds, so the module's rule watches them too."""
    out = set()
    for name in ("settings.gradle", "settings.gradle.kts"):
        for line in _read(os.path.join(project, module, name)).splitlines():
            if line.lstrip().startswith("//"):
                continue
            for arg in re.findall(r"""\bincludeBuild\s*\(?\s*["']([^"']+)["']""", line):
                rel = os.path.normpath(os.path.join(module, arg)).replace(os.sep, "/")
                if rel != module and not rel.startswith("..") and not os.path.isabs(rel) \
                        and os.path.isdir(os.path.join(project, rel)):
                    out.add(rel)
    return sorted(out)


def _untested(cmd):
    """unity-batch.sh exits 2 when it cannot run here (no Unity Editor, project open in
    one): the gate reports UNTESTED for it — never PASS, and not a failing test."""
    return {"untested_exit": 2} if "unity-batch.sh" in cmd else {}


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
                {"id": f"REG-AUTO-{i:02d}", "name": name, "command": cmd, **_untested(cmd)}
                for i, (name, cmd) in enumerate(runners, 1)
            ],
        })
    # One rule per module: a change in PCConnect/ runs only PCConnect's suite. fnmatch's
    # `*` crosses `/`, so "<module>/*.kt" covers every depth inside the module. Modules of
    # a monorepo can be in any language (a Go service next to Android apps), so they watch
    # every common source extension, not only the active profile's. A composite build the
    # module includes (includeBuild("../shared")) is watched too: a change in shared/ runs
    # every consumer's suite, not only shared's own.
    mod_exts = sorted(set(DEFAULT_EXTS) | set(exts))
    for mod, mod_runners in modules:
        tag = "".join(ch if ch.isalnum() else "-" for ch in mod).upper()
        rules.append({
            "component": mod,
            "watch_files": [f"{d}/*{e}" for d in [mod] + included_builds(project, mod) for e in mod_exts],
            "mandatory_regression_tests": [
                {"id": f"REG-AUTO-{tag}-{i:02d}", "name": f"{mod}: {name}", "command": f"cd {shlex.quote(mod)} && {cmd}",
                 **_untested(cmd)}
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
              "(Unity Assets/ + ProjectSettings/ProjectVersion.txt, gradlew, Package.swift, package.json test "
              "script, pytest, go.mod, Cargo.toml, pubspec.yaml, *.sln/*.csproj)")
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
