#!/usr/bin/env python3
"""
red_proof.py — prove that a bug's regression test would have caught the bug: seen RED on
the unfixed code, GREEN with the fix, both in one sandbox (a throw-away git worktree — the
working tree is never touched).

  red_proof.py <project> (--bug ID[,ID…] | --pending) [--fix-commit SHA] [--heavy] [--wait]

  RED run   = base code + the bug's test files        → must fail AND name one of the tests
  GREEN run = base code + the test files + the fix    → must pass (the sandbox works)
  RED + GREEN → PROVEN · GREEN + GREEN → VACUOUS (the test does not depend on the fix)
  anything else → INCONCLUSIVE with the reason; never a guess.

  Session mode (default): base = HEAD, fix = the uncommitted non-test changes. No such
  change → INCONCLUSIVE (the fix is committed; pass --fix-commit).
  --fix-commit SHA (or, with --pending, the ONE commit the bug's evidence names that changes
  non-test code — two or more → INCONCLUSIVE "mơ hồ"): RED = HEAD with that commit reverted
  by `git revert` in the worktree (three-way, so later edits of the same file merge; a real
  conflict → INCONCLUSIVE with the files), the current test files copied back; GREEN = HEAD.

  The sandbox gets what a build needs and git does not hold, copied (never linked, never
  written back): well-known ignored build inputs (local.properties, google-services.json,
  key.properties, *.jks, libs/*.aar|jar, .env) plus the globs in .agents/local/red_proof.json
  {"copy": [...]}; node_modules / .venv / vendor linked read-mostly; a Unity Library/ cloned
  copy-on-write (APFS `cp -c`), never linked.
  Only the bug's tests run when its suite declares "impacted_command" ({gradle_tests},
  {gradle_module_tests:<task>}, {unity_filter}, {pytest_nodes}, {jest_paths}); else the full
  command. A run that executed no test ("No tests found", "Ran 0 tests") is INCONCLUSIVE.
  Suites naming Gradle / Unity / xcodebuild are PENDING unless --heavy.
  --pending: every fixed bug/REQ with a linked test and no current proof; a past bug needs its
  fix commit (--fix-commit or one named in its evidence) — never the tree's uncommitted work.
  --patch FILE (one --bug): RED = HEAD + a patch that puts the bug BACK (forward, three-way),
  GREEN = HEAD — for old bugs whose fix commit is unknown, huge or no longer reverts. The
  patch may touch production code only (a proof never edits the test) and is kept at
  .agents/local/red-patches/<ID>.patch, which --pending then uses by itself (ahead of any fix
  commit); editing it makes the proof OUTDATED. A patch that no longer applies → INCONCLUSIVE.
  The DevKit links git does not hold (.agents/active-profile, .agents/devkit…) are re-created
  in the sandbox, so matrix commands that call through them run.
  An unknown id → exit 2 with close matches (an id is also found with or without "BUG-").
  The result goes to the row (red_proof: status, reason, mode, test file hashes, log); the log
  keeps both runs under .agents/evidence/. RED_PROOF=0 turns it off.
Without --wait the work detaches and the command returns at once. Standard library only.
"""

from __future__ import annotations

import contextlib
import difflib
import fnmatch
import hashlib
import json
import os
import re
import shutil
import shlex
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEVKIT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DEVKIT / "bin"))
sys.dont_write_bytecode = True
import regression_checklist as rc  # noqa: E402

HEAVY = re.compile(r"gradlew|\bgradle\b|unity|-runTests|xcodebuild", re.I)
TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec)/|/src/(test|androidTest)/|/Tests?/|(^|/)test_[^/]*\.py$"
                       r"|_test\.(py|go|dart)$|\.(test|spec)\.[cm]?[jt]sx?$|Tests?\.(kt|java|swift|cs)$")
# Read-mostly dependency folders linked into the sandbox so a JS / Python suite can run. Never
# a build cache a runner writes into (Unity Library/, .gradle/): through a link the sandbox run
# would rewrite the real project's cache.
DEP_DIRS = ("node_modules", ".venv", "venv", "vendor")
# Build inputs git does not hold (ignored on purpose) that a build cannot do without.
DEFAULT_INPUTS = ("local.properties", "**/local.properties", "google-services.json", "**/google-services.json",
                  "**/GoogleService-Info.plist", "key.properties", "**/key.properties", "**/keystore.properties",
                  "**/*.jks", "**/*.keystore", "**/libs/*.aar", "**/libs/*.jar", ".env", ".env.*", "**/.env")
SKIP_WALK = {".git", "build", ".gradle", "node_modules", "Library", "Temp", "Logs", "obj", ".venv", "venv",
             "__pycache__", ".idea", ".agents", ".claude", "dist", "out", ".cxx", ".kotlin"}
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
NOT_CODE = (".agents/", ".claude/", ".gemini/", "docs/", ".github/")
SOURCE_EXT = (".kt", ".kts", ".java", ".cs", ".py", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".swift", ".m", ".mm",
              ".go", ".rs", ".dart", ".c", ".cc", ".cpp", ".h", ".hpp", ".xml", ".gradle", ".json", ".yaml", ".yml")
# A RED run that failed to BUILD the tests proves nothing about behaviour, even when the error
# names the test file (the revert removed a symbol the test calls).
COMPILE_RED = re.compile(r"Compilation error|compile\w*(?:Kotlin|Java)\w* FAILED|error CS\d{4}|error: cannot find symbol|"
                         r"Unresolved reference|ImportError|ModuleNotFoundError|SyntaxError|Cannot find module|"
                         r"error TS\d{4}|error\[E\d{4}\]|\bundefined: \w+|Scripts have compiler errors")
# A line that reports a failing test (Gradle "Cls > m FAILED", unittest "FAIL: t (mod.Cls)", pytest
# "FAILED path::t", Unity "[Failed] Ns.Cls.M", jest "FAIL path"): a linked test file counts as red
# only when its name sits on such a line — not merely somewhere in the output.
FAIL_LINE = re.compile(r"\bFAIL(?:ED)?\b|\[Failed\]|\bFailed\b|\bERROR\b|\bError:|✗|✖|^not ok|AssertionError")


ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def failed_stems(output: str, stems: set, names: dict | None = None) -> set:
    """Test files (by stem) with a failing line naming them. `names` maps a stem to every test class the
    file holds: a failure of AccessControlJvmTest reds CarTcpServerJvmLoopbackTest.kt, which declares it."""
    text = ANSI.sub("", output or "")      # runners colour their output even when piped (Python 3.14)
    bad = [line for line in text.splitlines() if FAIL_LINE.search(line)]
    return {s for s in stems if any(n in line for n in (names or {}).get(s, {s}) for line in bad)}


NO_TESTS = re.compile(r"No tests found for given includes|Ran 0 tests|no tests ran|collected 0 items|"
                      r"No tests found|(?<!\d)0 tests completed", re.I)
PATCH_DIR = Path(".agents") / "local" / "red-patches"


def patch_rel(bid: str) -> Path:
    """.agents/local/red-patches/<ID>.patch — the id made safe for a file name."""
    return PATCH_DIR / (re.sub(r"[^A-Za-z0-9._-]", "_", bid) + ".patch")


def patch_of(project: Path, bid: str) -> Path | None:
    p = project / patch_rel(bid)
    return p if p.is_file() else None


def patch_files(patch: Path) -> list:
    """Paths a patch touches (both sides), via `git apply --numstat` (no repo needed)."""
    r = subprocess.run(["git", "apply", "--numstat", str(patch)], capture_output=True, text=True)
    if r.returncode != 0:
        return []
    return [line.split("\t", 2)[2] for line in r.stdout.splitlines() if line.count("\t") >= 2]


def git(project: Path, *args, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(project), *args], capture_output=True, text=True, **kw)


def file_hash(path: Path) -> str | None:
    try:
        return hashlib.sha1(path.read_bytes()).hexdigest()[:16]
    except OSError:
        return None


def resolve_id(data: dict, ref: str) -> str | None:
    for cand in (ref, f"BUG-{ref}", ref[4:] if ref.upper().startswith("BUG-") else None):
        if cand and (data["items"].get(cand) or {}).get("kind") in ("bug", "req"):
            return cand
    return None


def test_paths(project: Path, item: dict) -> list:
    refs = list(item.get("runs_in_suite", [])) + list(item.get("test_refs", []))
    out = []
    for ref in refs:
        for p in rc.ref_paths(project, ref):
            if p not in out:
                out.append(p)
    return out


def fix_commit_of(project: Path, item: dict) -> tuple:
    """(sha, None) when the evidence names exactly ONE commit that changes non-test code;
    (None, reason) when it names several (reverting the wrong one gives a false verdict);
    (None, None) when it names none."""
    found = []
    for sha in dict.fromkeys(SHA.findall(str(item.get("evidence") or ""))):
        if git(project, "cat-file", "-t", sha).stdout.strip() != "commit":
            continue
        full = git(project, "rev-parse", sha).stdout.strip()
        files = git(project, "show", "--name-only", "--format=", sha).stdout.split()
        if full not in [f for _, f in found] and any(not TEST_PATH.search(f) for f in files):
            found.append((sha, full))
    if len(found) == 1:
        return found[0][0], None
    if len(found) > 1:
        return None, f"commit fix mơ hồ — evidence nêu {len(found)} commit đổi code: {', '.join(s for s, _ in found)} (chạy --fix-commit <sha>)"
    return None, None


def jobs_of(project: Path) -> int:
    """How many proofs may run at once for this project: RED_PROOF_JOBS, else "jobs" in
    .agents/local/red_proof.json, else 1 (each proof is two full builds)."""
    try:
        return max(1, int(os.environ["RED_PROOF_JOBS"]))
    except (KeyError, ValueError):
        pass
    try:
        cfg = json.loads((project / ".agents" / "local" / "red_proof.json").read_text(encoding="utf-8"))
        return max(1, int(cfg.get("jobs", 1)))
    except (OSError, ValueError, TypeError, AttributeError):
        return 1


def proof_slot(state: Path, jobs: int, wait: bool = True):
    """Hold one of `jobs` proof slots (flock on red_proof.lock, red_proof.2.lock, …), or None when
    all are busy and wait is False. Slot 1 is the file other tools already queue on."""
    import fcntl
    while True:
        for i in range(max(1, jobs)):
            f = open(state / ("red_proof.lock" if i == 0 else f"red_proof.{i + 1}.lock"), "w")
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return f
            except OSError:
                f.close()
        if not wait:
            return None
        time.sleep(2)


@contextlib.contextmanager
def worktree(project: Path):
    """A detached worktree at HEAD, removed afterwards whatever happens."""
    box = Path(tempfile.mkdtemp(prefix="red-proof-"))
    r = git(project, "worktree", "add", "--detach", "--quiet", str(box), "HEAD")
    if r.returncode != 0:
        shutil.rmtree(box, ignore_errors=True)
        raise RuntimeError(f"không tạo được worktree: {r.stderr.strip()[:160]}")
    try:
        yield box
    finally:
        git(project, "worktree", "remove", "--force", str(box))
        shutil.rmtree(box, ignore_errors=True)
        git(project, "worktree", "prune")


def build_inputs(project: Path) -> list:
    """Ignored / untracked files a build needs: DEFAULT_INPUTS + .agents/local/red_proof.json."""
    pats = list(DEFAULT_INPUTS)
    try:
        pats += list(json.loads((project / ".agents" / "local" / "red_proof.json").read_text(encoding="utf-8")).get("copy", []))
    except (OSError, ValueError, AttributeError):
        pass
    out = []
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_WALK]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), project)
            if any(fnmatch.fnmatch(rel, p) for p in pats):
                out.append(rel)
    return out


def devkit_links(project: Path) -> list:
    """Symlinks the DevKit install keeps out of git (.agents/active-profile, .agents/devkit,
    .agents/skills/<x>, root links…): a worktree lacks them, and matrix commands call through
    them (bash .agents/active-profile/scripts/unity-batch.sh)."""
    out = []
    for base in (project, project / ".agents"):
        if not base.is_dir():
            continue
        for entry in os.scandir(base):
            if entry.name in ("evidence", "archive", ".git"):
                continue
            if entry.is_symlink():
                out.append(os.path.relpath(entry.path, project))
            elif base != project and entry.is_dir(follow_symlinks=False):
                out += [os.path.relpath(e.path, project) for e in os.scandir(entry.path) if e.is_symlink()]
    return out


def furnish(project: Path, box: Path) -> None:
    for rel in devkit_links(project):
        dst = box / rel
        if not os.path.lexists(dst):
            dst.parent.mkdir(parents=True, exist_ok=True)
            target = os.readlink(project / rel)
            if not os.path.isabs(target):
                target = os.path.normpath(os.path.join(os.path.dirname(project / rel), target))
            os.symlink(target, dst)
    for rel in build_inputs(project):
        dst = box / rel
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(project / rel, dst)
    for d in DEP_DIRS:
        if (project / d).is_dir() and not (box / d).exists():
            (box / d).symlink_to(project / d)
    if (project / "ProjectSettings" / "ProjectVersion.txt").is_file() and (project / "Library").is_dir() \
            and not (box / "Library").exists():
        subprocess.run(["cp", "-c", "-R", str(project / "Library"), str(box / "Library")], capture_output=True)


def copy_in(project: Path, box: Path, files: list) -> None:
    for f in files:
        src, dst = project / f, box / f
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        elif dst.exists():
            dst.unlink()        # deleted by the fix


def _jvm_fqn(project: Path, path: str) -> str | None:
    try:
        m = re.search(r"^\s*package\s+([\w.]+)", (project / path).read_text(encoding="utf-8", errors="replace"), re.M)
    except OSError:
        return None
    return f"{m.group(1)}.{Path(path).stem}" if m else Path(path).stem


# A top-level class at column 0 that can hold tests (not abstract/data/enum/sealed/annotation).
_JVM_CLASS = re.compile(r"^(?:(?:public|internal|private|open|final)\s+)*class\s+([A-Za-z_]\w*)", re.M)


def _jvm_filters(project: Path, path: str) -> list:
    """`--tests` names for one test file: the file's class plus every other top-level test class in
    it (a Kotlin file may hold two — the filter on the file name alone never runs the second)."""
    first = _jvm_fqn(project, path)
    try:
        src = (project / path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return [first]
    pkg = first.rsplit(".", 1)[0] + "." if first and "." in first else ""
    names = [first] + [pkg + c for c in _JVM_CLASS.findall(src) if c != Path(path).stem]
    return list(dict.fromkeys(names))


def test_names(project: Path, path: str) -> set:
    """Short names a runner prints for a test file's failures: the file stem, plus every top-level
    class of a Kotlin/Java file (the same classes `_jvm_filters` runs)."""
    names = {Path(path).stem}
    if path.endswith((".kt", ".java")):
        names |= {n.rsplit(".", 1)[-1] for n in _jvm_filters(project, path) if n}
    return names


_RUNNER_EXT = (("pytest", (".py",)), ("unittest", (".py",)), ("jest", (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs")),
               ("vitest", (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs")), ("go test", (".go",)))


def selects(project: Path, path: str, cmd: str) -> bool:
    """Does this (narrowed) suite command really run the linked test file at path? Only those
    must go red for PROVEN: a linked script no suite runs, or a class outside `--tests`, can
    never turn red, so requiring it would block every proof of that bug."""
    c = cmd or ""
    if "gradlew" in c or re.search(r"(^|\s)gradle\s", c):
        if not path.endswith((".kt", ".java")) or not rc._runs_source_set(path, c, project):
            return False
        filters = [f.split("#")[0] for f in re.findall(r"--tests\s+['\"]?([^'\"\s]+)", c)]
        if not filters:
            return True
        names = test_names(project, path)
        return any("*" in f or f.rsplit(".", 1)[-1] in names for f in filters)
    m = re.search(r"--filter\s+['\"]?([^'\"]+)", c)
    if m and path.endswith(".cs"):
        return Path(path).stem in {f.rsplit(".", 1)[-1] for f in m.group(1).split(";")}
    if path.endswith(".cs"):
        return rc._runs_source_set(path, c, project)
    exts = tuple(e for runner, es in _RUNNER_EXT if runner in c for e in es)
    pmod = path[:-3].replace("/", ".") if path.endswith(".py") else None
    named, cwd = False, ""
    for part in re.split(r"&&|\|\||;", c):
        try:
            words = shlex.split(part)
        except ValueError:
            words = part.split()
        if words[:1] == ["cd"] and len(words) > 1:
            cwd = os.path.normpath(os.path.join(cwd, words[1]))
            continue
        for w in words[1:]:
            if w.startswith("-"):
                continue
            t = os.path.normpath(os.path.join(cwd, w)).lstrip("./") if not os.path.isabs(w) else w
            dotted = "unittest" in c and "." in w and re.fullmatch(r"[\w.]+", w) is not None
            if not ("/" in w or w.endswith(SOURCE_EXT) or dotted or (project / t).is_dir()):
                continue
            named = True
            if path == t or (dotted and pmod and (pmod == w or pmod.startswith(w + "."))):
                return True
            if path.startswith(t.rstrip("/") + "/") and exts and path.endswith(exts):
                return True
    return False if named else rc._runs_source_set(path, c, project)


def _cs_name(project: Path, path: str) -> str:
    try:
        m = re.search(r"^\s*namespace\s+([\w.]+)", (project / path).read_text(encoding="utf-8", errors="replace"), re.M)
    except OSError:
        m = None
    return f"{m.group(1)}.{Path(path).stem}" if m else Path(path).stem


def _gate_gradle_root():
    """post-fix-gate's own _gradle_root (nearest settings.gradle(.kts) above a module): one
    rule for both, so a module path is what the command's `cd <gradle root>` expects."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("post_fix_gate", DEVKIT / "bin" / "post-fix-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod._gradle_root


def _gradle_path(project: Path, test: str) -> str | None:
    """":app" for CarConnect/app/src/test/… when CarConnect/ holds settings.gradle.kts."""
    mod = rc._gradle_module(project, test)            # ":CarConnect:app" — from the project root
    if not mod:
        return None
    try:
        groot = _gate_gradle_root()(project, mod[1:].replace(":", "/"))
    except Exception:  # noqa: BLE001 — cannot tell the Gradle root: run the full command
        return None
    mod_dir = project / mod[1:].replace(":", "/")
    rel = mod_dir.relative_to(groot).as_posix() if mod_dir != groot else ""
    return ":" + rel.replace("/", ":") if rel else ""


def narrowed(project: Path, template: str | None, tests: list, scope: str | None = None) -> str | None:
    """The suite's impacted_command filled with ONLY the bug's tests, or None (run it all).
    scope = the suite's full command: a bug linked to several suites puts in each only the tests
    of the modules that suite runs (`:app` may have only testReleaseUnitTest, `:core:ui` only
    testDebugUnitTest — the other task does not exist there and the build fails)."""
    if not template:
        return None
    # androidTest classes need a device: in a JVM unit-test task their filter matches nothing
    jvm = [t for t in tests if t.endswith((".kt", ".java")) and "/src/androidTest/" not in t]
    cs = [t for t in tests if t.endswith(".cs")]
    out = template
    if "{gradle_tests}" in out:
        if not jvm:
            return None
        out = out.replace("{gradle_tests}", " ".join(f"--tests '{n}'" for t in jvm for n in _jvm_filters(project, t)))
    m = re.search(r"\{gradle_module_tests:([A-Za-z0-9_]+)\}", out)
    if m:
        # One task per module, all its --tests after it: Gradle runs a task named twice once, and
        # each occurrence's --tests REPLACES the filter, so only the last test would run.
        by_mod: dict = {}
        for t in jvm:
            mod = _gradle_path(project, t)
            if mod is None:
                return None
            by_mod.setdefault(mod, []).extend(f"--tests '{n}'" for n in _jvm_filters(project, t))
        if scope and any(f"{mod}:" in scope for mod in by_mod):
            by_mod = {mod: f for mod, f in by_mod.items() if f"{mod}:" in scope}
        if not by_mod:
            return None
        out = out.replace(m.group(0), " ".join(f"{mod}:{m.group(1)} " + " ".join(f) for mod, f in by_mod.items()))
    if "{unity_filter}" in out:
        if not cs:
            return None
        out = out.replace("{unity_filter}", "--filter '" + ";".join(_cs_name(project, t) for t in cs) + "'")
    for ph in ("{pytest_nodes}", "{jest_paths}"):
        if ph in out:
            out = out.replace(ph, " ".join(tests))
    return None if "{" in out and "}" in out else out


def run(cmd: str, cwd: Path, timeout: float) -> tuple:
    proc = subprocess.Popen(cmd, shell=True, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors="replace", start_new_session=True)
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out or ""
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return None, (proc.communicate()[0] or "") + "\n(TIMEOUT)"


def prove(project: Path, data: dict, bid: str, *, fix_commit: str | None, heavy: bool,
          fix_reason: str | None = None, patch: Path | None = None) -> dict:
    item = data["items"][bid]
    suites = [data["items"].get(t) or {} for t in item.get("tests", [])]
    base = {"at": rc._now(), "ts": time.time()}
    if not [s for s in suites if s.get("command")]:
        return {**base, "status": "INCONCLUSIVE", "reason": "chưa link suite nào của ma trận"}
    tests = test_paths(project, item)
    if not tests:
        return {**base, "status": "INCONCLUSIVE", "reason": "không biết file test nào (link bằng file/class test)"}
    cmds = []
    for s in suites:
        if s.get("command"):
            c = narrowed(project, s.get("impacted_command"), tests, scope=s["command"]) or s["command"]
            if c not in cmds:
                cmds.append(c)
    if not heavy and any(HEAVY.search(c) for c in cmds):
        return {**base, "status": "PENDING",
                "reason": "suite nặng (Gradle/Unity) — chạy với --heavy (`agent-kit nightly` nếu đã cài, hoặc tay: red_proof.py . --pending --heavy --wait)"}
    fix_commit = None if patch else (fix_commit or item.get("fix_commit"))
    if not fix_commit and not patch and fix_reason:
        return {**base, "status": "INCONCLUSIVE", "reason": fix_reason}
    if patch:
        mode, fix = "patch", []
        touched = patch_files(patch)
        if not touched:
            return {**base, "status": "INCONCLUSIVE", "mode": mode, "reason": f"patch rỗng hoặc hỏng: {patch.name}"}
        in_tests = [f for f in touched if f in tests or TEST_PATH.search(f)]
        if in_tests:
            return {**base, "status": "INCONCLUSIVE", "mode": mode,
                    "reason": "patch sửa file test (" + ", ".join(in_tests[:4]) + ") — chứng minh chỉ được đổi code sản xuất"}
    elif fix_commit:
        mode, fix = "revert", []
    else:
        mode = "session"
        changed = git(project, "diff", "--name-only", "HEAD").stdout.split() + \
            git(project, "ls-files", "--others", "--exclude-standard").stdout.split()
        fix = [f for f in dict.fromkeys(changed) if f not in tests and not TEST_PATH.search(f)
               and not f.startswith((".agents/", ".claude/"))]
        if not fix:
            return {**base, "status": "INCONCLUSIVE",
                    "reason": "không có bản sửa chưa commit — fix đã commit: chạy với --fix-commit <sha>"}
    try:
        timeout = float(os.environ.get("RED_PROOF_TIMEOUT_S", "1800"))
    except ValueError:
        timeout = 1800.0
    stems = {Path(t).stem for t in tests}
    log, red_all_green, green_ok, ran_nothing, red_compile = [], True, True, False, False
    red_stems = set()
    try:
        with worktree(project) as red_box, worktree(project) as green_box:
            if mode == "patch":
                # Put the bug back: the patch applies FORWARD on HEAD (three-way, so small drift
                # since it was written merges); a real mismatch → INCONCLUSIVE naming the files.
                r = subprocess.run(["git", "apply", "-3", "--whitespace=nowarn", str(patch.resolve())],
                                   cwd=str(red_box), capture_output=True, text=True)
                if r.returncode != 0:
                    bad = git(red_box, "diff", "--name-only", "--diff-filter=U").stdout.split()
                    return {**base, "status": "INCONCLUSIVE", "mode": mode, "patch": str(patch_rel(bid)),
                            "reason": "patch không áp được lên code hiện tại: " +
                                      (", ".join(bad[:6]) or r.stderr.strip()[:160])}
            if mode == "revert":
                # Take back only the fix's PRODUCTION code, three-way (later edits merge): test
                # files and helpers other tests import, and the commit's notes (.agents/,
                # .claude/, docs, *.md) stay at HEAD — reverting them breaks the build or
                # conflicts over text that is no part of the fix.
                files = git(project, "show", "--name-only", "--format=", fix_commit).stdout.split()
                # Source code only (not data, binaries, tool output), and only what still exists:
                # a file deleted since the fix has nothing left to take the fix out of.
                prod = [f for f in files if not TEST_PATH.search(f) and not f.startswith(NOT_CODE)
                        and f.endswith(SOURCE_EXT) and git(project, "cat-file", "-e", f"HEAD:{f}").returncode == 0]
                if not prod:
                    return {**base, "status": "INCONCLUSIVE", "mode": mode, "fix_commit": fix_commit,
                            "reason": f"commit {fix_commit} không đổi code sản xuất"}
                patch = git(project, "diff", "--binary", f"{fix_commit}^", fix_commit, "--", *prod).stdout
                pf = red_box / ".red_proof.patch"
                pf.write_text(patch, encoding="utf-8")
                r = subprocess.run(["git", "apply", "-3", "-R", "--whitespace=nowarn", pf.name], cwd=str(red_box),
                                   capture_output=True, text=True)
                pf.unlink()
                if r.returncode != 0:
                    conflicts = git(red_box, "diff", "--name-only", "--diff-filter=U").stdout.split()
                    return {**base, "status": "INCONCLUSIVE", "mode": mode, "fix_commit": fix_commit,
                            "reason": f"revert {fix_commit} xung đột với code hiện tại: " +
                                      (", ".join(conflicts[:6]) or r.stderr.strip()[:160])}
            for box in (red_box, green_box):
                furnish(project, box)
            copy_in(project, red_box, tests)
            copy_in(project, green_box, tests + fix)
            for cmd in cmds:
                code, out = run(cmd, red_box, timeout)
                log.append(f"## RED run (không có bản sửa) — {cmd} — exit {code}\n{out}")
                ran_nothing = ran_nothing or bool(NO_TESTS.search(out))
                if code != 0:
                    red_all_green = False
                    if COMPILE_RED.search(out):
                        red_compile = True
                    elif code is not None:
                        red_stems |= failed_stems(out, stems, {Path(t).stem: test_names(project, t) for t in tests})
                code, out = run(cmd, green_box, timeout)
                log.append(f"## GREEN run (có bản sửa) — {cmd} — exit {code}\n{out}")
                ran_nothing = ran_nothing or bool(NO_TESTS.search(out))
                green_ok = green_ok and code == 0
    except RuntimeError as e:
        return {**base, "status": "INCONCLUSIVE", "mode": mode, "reason": str(e)}
    red_ok = bool(red_stems)
    # Only the linked tests these commands actually run must go red (selects(): an androidTest
    # ref under a JVM unit task, a script no suite runs, a class outside `--tests` never can).
    runnable = {Path(t).stem for t in tests if any(selects(project, t, c) for c in cmds)} or stems
    still_green = sorted(runnable - red_stems)
    if ran_nothing:
        status, reason = "INCONCLUSIVE", "lệnh không chạy test nào (bộ lọc không khớp?) — xem log"
    elif red_compile and not red_ok:
        status, reason = "INCONCLUSIVE", ("đỏ vì lỗi biên dịch/import khi bỏ bản sửa (test gọi thứ chỉ bản sửa mới có) — "
                                          "test không chạy trên code cũ, chưa phải bằng chứng")
    elif red_ok and green_ok and still_green:
        status, reason = "INCONCLUSIVE", (f"chỉ {len(red_stems & runnable)}/{len(runnable)} file test đỏ khi bỏ bản sửa — còn xanh: "
                                          f"{', '.join(still_green[:4])} (phần bug đó chưa được chứng minh: tách bug, sửa test, "
                                          "hoặc bỏ link)")
    elif red_ok and green_ok:
        status, reason = "PROVEN", "đỏ khi bỏ bản sửa, xanh khi có"
    elif red_all_green and green_ok:
        status, reason = "VACUOUS", "test vẫn xanh khi bỏ bản sửa — không bảo vệ gì"
    elif not green_ok:
        status, reason = "INCONCLUSIVE", ("sandbox không chạy xanh được kể cả có bản sửa (thiếu file build bị ignore? "
                                          "khai trong .agents/local/red_proof.json {\"copy\": [...]})")
    else:
        status, reason = "INCONCLUSIVE", "đỏ khi bỏ bản sửa nhưng output không nêu tên test — đỏ vì lý do khác?"
    if mode == "patch":
        reason = {"PROVEN": "đỏ khi áp patch đưa bug trở lại, xanh trên HEAD",
                  "VACUOUS": "test vẫn xanh khi áp patch đưa bug trở lại — test (hoặc patch) không bắt đúng bug"
                  }.get(status, reason.replace("bỏ bản sửa", "áp patch").replace("có bản sửa", "HEAD"))
    meta = {"bug": bid, "mode": mode, "fix_commit": fix_commit, "status": status, "tests": ", ".join(tests)}
    files = {t: file_hash(project / t) for t in tests}
    if patch:
        meta["patch"] = str(patch_rel(bid))
        files[str(patch_rel(bid))] = file_hash(project / patch_rel(bid))   # patch edited → OUTDATED
    rel = rc.write_evidence(project, f"redproof-{bid}", "\n\n".join(log), meta)
    out = {**base, "status": status, "reason": reason, "mode": mode, "fix_commit": fix_commit, "files": files, "log": rel}
    if patch:
        out["patch"] = str(patch_rel(bid))
    return out


def pending_ids(data: dict, project: Path | None = None) -> list:
    """Fixed bugs/REQs with a linked test and no current proof — plus INCONCLUSIVE ones that got
    a kept patch since (their proof failed only for want of a way to put the bug back)."""
    out = []
    for bid, it in sorted(data["items"].items()):
        if it.get("kind") not in ("bug", "req") or it.get("fixed") is False or not it.get("tests"):
            continue
        proof = it.get("red_proof") or {}
        if proof.get("status") in (None, "PENDING", "OUTDATED"):
            out.append(bid)
        elif proof.get("status") == "INCONCLUSIVE" and project is not None and proof.get("mode") != "patch" \
                and patch_of(project, bid):
            out.append(bid)
    return out


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if os.environ.get("RED_PROOF", "1") == "0":
        return 0
    wait = "--wait" in args
    heavy = "--heavy" in args
    pending = "--pending" in args
    rest = [a for a in args if a not in ("--wait", "--heavy", "--pending")]
    bugs, fix_commit, project, patch_arg = [], None, None, None
    i = 0
    while i < len(rest):
        if rest[i] == "--bug" and i + 1 < len(rest):
            bugs += [b for b in rest[i + 1].split(",") if b]; i += 2
        elif rest[i] == "--fix-commit" and i + 1 < len(rest):
            fix_commit = rest[i + 1]; i += 2
        elif rest[i] == "--patch" and i + 1 < len(rest):
            patch_arg = Path(rest[i + 1]).expanduser().resolve(); i += 2
        else:
            project = project or rest[i]; i += 1
    if patch_arg is not None:
        if fix_commit:
            print("✖ --patch và --fix-commit loại trừ nhau (patch đưa bug trở lại; fix-commit gỡ bản sửa)", file=sys.stderr)
            return 2
        if len(bugs) != 1 or pending:
            print("✖ --patch cần đúng một --bug (mỗi bug một patch riêng)", file=sys.stderr)
            return 2
        if not patch_arg.is_file():
            print(f"✖ không có file patch {patch_arg}", file=sys.stderr)
            return 2
    project = Path(project or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    if not (project / rc.STATUS_FILE).is_file():
        print(f"✖ {project} không có .agents/regression_status.json", file=sys.stderr)
        return 2
    if not (bugs or pending):
        return 0
    data = rc.load(project)
    resolved, unknown = [], []
    for b in bugs:
        rid = resolve_id(data, b)
        (resolved.append(rid) if rid else unknown.append(b))
    if unknown:
        ids = [i for i, it in data["items"].items() if it.get("kind") in ("bug", "req")]
        for u in unknown:
            near = difflib.get_close_matches(u, ids, n=3, cutoff=0.5) or \
                difflib.get_close_matches(u.removeprefix("BUG-"), ids, n=3, cutoff=0.5)
            print(f"✖ không có bug/REQ {u!r} trong checklist" + (f" — ý là: {', '.join(near)}?" if near else ""),
                  file=sys.stderr)
        return 2
    if patch_arg is not None:
        # Keep the patch with the project, so the proof can be re-run (--pending) and an edit of
        # the patch is seen (its hash is in the proof → OUTDATED).
        kept = project / patch_rel(resolved[0])
        if patch_arg != kept.resolve():
            kept.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(patch_arg, kept)
    if not wait:
        subprocess.Popen([sys.executable, __file__, *args, "--wait"], cwd=str(project),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    state = project / ".claude" / "audit-gate"
    state.mkdir(parents=True, exist_ok=True)
    # jobs_of() proofs at a time per project (default 1: each is two full builds)
    with proof_slot(state, jobs_of(project)):
        data = rc.load(project)
        mf = project / ".agents" / "regression_matrix.active.json"
        if mf.is_file():
            rc.sync_from_matrix(data, json.loads(mf.read_text(encoding="utf-8")))
        ids = resolved + (pending_ids(data, project) if pending else [])
        for bid in dict.fromkeys(ids):
            # A kept patch that puts the bug back beats any fix commit: it does not depend on
            # history (old fixes are huge or no longer revert). --fix-commit given → that wins.
            bug_patch = None if fix_commit else patch_of(project, bid)
            if bug_patch:
                result = prove(project, data, bid, fix_commit=None, heavy=heavy, patch=bug_patch)
                with rc.locked(project):
                    fresh = rc.load(project)
                    if bid in fresh["items"]:
                        fresh["items"][bid]["red_proof"] = result
                        rc.save(project, fresh)
                print(f"{bid}: {result['status']} — {result.get('reason', '')}")
                continue
            fc, why = (fix_commit, None) if fix_commit or not pending else fix_commit_of(project, data["items"][bid])
            if pending and not fix_commit and not fc and not why and bid not in resolved:
                # A past bug: the uncommitted changes in the tree are the user's current work,
                # not this bug's fix — session mode would compare against the wrong "fix".
                why = ("không có commit fix trong evidence — bug cũ không lấy thay đổi chưa commit làm bản sửa; "
                       "chạy --bug <ID> --fix-commit <sha>")
            result = prove(project, data, bid, fix_commit=fc, heavy=heavy, fix_reason=why)
            with rc.locked(project):
                fresh = rc.load(project)
                if bid in fresh["items"]:
                    fresh["items"][bid]["red_proof"] = result
                    rc.save(project, fresh)
            print(f"{bid}: {result['status']} — {result.get('reason', '')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
