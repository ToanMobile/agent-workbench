#!/usr/bin/env bash
# Oracle cho issue #1401:
#   1. Gradle test suite thoát 0 nhưng không chạy test nào (NO-SOURCE / SKIPPED / 0 tests / --dry-run / thiếu task test)
#      -> UNTESTED (exit 4, exit_reason=no_tests_ran), không ghi FAIL vào suite_cache;
#      phân biệt UP-TO-DATE / FROM-CACHE (PASS hợp lệ) và lệnh không chạy unit test (ktlintCheck, detekt, lint, assemble).
#   2. Flaky (cả flaky_retry cùng lượt lẫn đỏ-rồi-xanh hai lượt cùng fp) -> ghi `flaky` vào runs.jsonl + báo cáo gate,
#      loại lượt trước có infra / env_blocked / killed_from_outside / exit_reason != fail, không đổi exit code, không bị _run_log_fit cắt.
#   3. rerun_skip_miss_reason ghi riêng cho cửa rerun_skip (base, local_sha, pool_busy, unkeyed_suite, force...), không trộn vào reuse_miss_reason.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"

python3 -I - "$GATE" "$TMP" "$SB_HEAVY_SLOT_DIR" <<'PYEND'
import json, os, shutil, subprocess, sys, time

GATE, TMP, SLOT_DIR = sys.argv[1], sys.argv[2], sys.argv[3]
PY = sys.executable
fails = 0


def ok(msg):
    print("✔ " + msg, flush=True)


def bad(msg):
    global fails
    fails += 1
    print("✖ " + msg, flush=True)


def chk(cond, good, why=""):
    if cond:
        ok(good)
    else:
        bad(f"{good}: {why}")
    return bool(cond)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=120).stdout.decode("utf-8", "replace").strip()


def put(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    if mode is not None:
        os.chmod(path, mode)


def read_runs(root):
    gd = git(root, "rev-parse", "--git-common-dir")
    p = os.path.join(root, gd, "postfix-gate", "runs.jsonl")
    if not os.path.isfile(p):
        return []
    return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]


def read_report(root):
    gd = git(root, "rev-parse", "--absolute-git-dir")
    p = os.path.join(gd, "postfix-gate", "last_report.md")
    return open(p, encoding="utf-8").read() if os.path.isfile(p) else ""


def run_gate(root, flags, extra_env=None):
    drop = ("CI", "POSTFIX_GATE_FULL", "POSTFIX_GATE_FORCE_FULL", "DEVKIT_GATE_CACHE", "DEVKIT_SESSION_ID",
            "CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID", "GATE_TOTAL_BUDGET_S", "TEST_RUN_LOCK_WAIT_S",
            "DEVKIT_GATE_SLOTS", "DEVKIT_GATE_SLOT_HELD", "DEVKIT_SLOT_PRIORITY", "SB_HEAVY_SLOT_HELD",
            "DEVKIT_SLOT_ADVISORY_HELD")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k not in drop}
    env.update({
        "CLAUDE_PROJECT_DIR": root,
        "VACUITY_REVERT": "0",
        "FLAKY_RETRY": "0",
        "INFRA_RETRY": "0",
        "DEVKIT_SUITE_CACHE": "1",
        "DEVKIT_GATE_SLOTS": "0",
    })
    if extra_env:
        env.update(extra_env)
    p = subprocess.run([PY, GATE, "--matrix", os.path.join(root, "matrix.json"), "--lang", "en",
                        "--no-checklist", "--run-tests"] + list(flags),
                       cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    return p.returncode, p.stdout.decode("utf-8", "replace")


def make_gradle_repo(name, cmd="./gradlew :app:testDebugUnitTest", extra_suites=0):
    root = os.path.join(TMP, name)
    os.makedirs(root)
    git(root, "init", "-q", "-b", "main", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    put(os.path.join(root, "settings.gradle.kts"), 'include(":app")\n')
    put(os.path.join(root, "app/build.gradle.kts"), 'plugins { id("com.example.app") }\n')
    put(os.path.join(root, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 1 }\n")
    put(os.path.join(root, ".claude/audit-gate/.gitignore"), "*\n")
    put(os.path.join(root, "gradlew"), "#!/bin/sh\necho \"$GRADLE_OUT\"\nexit \"${GRADLE_RC:-0}\"\n", 0o755)
    tests = [{"id": "REG-GRADLE", "name": "gradle suite", "command": cmd}]
    for i in range(extra_suites):
        tests.append({"id": f"REG-EX-{i:03d}-{'x'*16}", "name": f"ex {i}", "command": f"true # {i}"})
    put(os.path.join(root, "matrix.json"), json.dumps({
        "project": "t",
        "rules": [{"component": "App", "watch_files": ["app/*"], "mandatory_regression_tests": tests}]
    }))
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    put(os.path.join(root, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 2 }\n")
    return root


# ── 1. Oracle 1: Gradle PASS không chạy test nào ─────────────────────────────────────────────────────────────
# 1a. NO-SOURCE / SKIPPED -> UNTESTED (exit 4), exit_reason=no_tests_ran, không ghi FAIL vào suite_cache
r1a = make_gradle_repo("g_nosrc")
rc, out = run_gate(r1a, ["--full", "--json"], {
    "GRADLE_OUT": "> Task :app:compileDebugUnitTestKotlin UP-TO-DATE\n> Task :app:testDebugUnitTest NO-SOURCE\n\nBUILD SUCCESSFUL in 1s"
})
runs = read_runs(r1a)
sc_dir = os.path.join(r1a, ".git", "postfix-gate", "suite_cache")
sc_fail = False
if os.path.isdir(sc_dir):
    for fn in os.listdir(sc_dir):
        if len(fn) == 69 and fn.endswith(".json"):
            d = json.load(open(os.path.join(sc_dir, fn), encoding="utf-8"))
            if (d.get("fail_n") or 0) > 0:
                sc_fail = True
chk(rc == 4 and runs and runs[-1].get("exit_reason") == "no_tests_ran" and runs[-1].get("verdict") == "UNTESTED" and not sc_fail,
    "1a. Gradle test task NO-SOURCE -> UNTESTED (exit 4, exit_reason=no_tests_ran, no FAIL in suite_cache)",
    f"rc={rc} last={runs[-1] if runs else None} sc_fail={sc_fail} out={out[-240:]}")

# 1b. SKIPPED / 0 tests completed / No tests found for given includes (exit 0) -> exit 4
for tag, g_out in [
    ("SKIPPED", "> Task :app:testDebugUnitTest SKIPPED\n\nBUILD SUCCESSFUL in 1s"),
    ("0 tests completed", "> Task :app:testDebugUnitTest\n0 tests completed, 0 failed\n\nBUILD SUCCESSFUL in 1s"),
    ("No tests found for given includes", "> Task :app:testDebugUnitTest\nNo tests found for given includes: [*Core*]\n\nBUILD SUCCESSFUL in 1s"),
    ("missing test task line", "> Task :app:compileDebugUnitTestKotlin UP-TO-DATE\n\nBUILD SUCCESSFUL in 1s"),
]:
    rx = make_gradle_repo("g_" + tag.replace(" ", "_"))
    rc, out = run_gate(rx, ["--full"], {"GRADLE_OUT": g_out})
    runs = read_runs(rx)
    chk(rc == 4 and runs and runs[-1].get("exit_reason") == "no_tests_ran",
        f"1b. Gradle ({tag}) -> exit 4, exit_reason=no_tests_ran",
        f"rc={rc} reason={runs[-1].get('exit_reason') if runs else None}")

# 1c. --dry-run on Gradle test command -> exit 4
r1c = make_gradle_repo("g_dry", cmd="./gradlew :app:testDebugUnitTest --dry-run")
rc, out = run_gate(r1c, ["--full"], {"GRADLE_OUT": ":app:testDebugUnitTest SKIPPED\nBUILD SUCCESSFUL in 1s"})
chk(rc == 4, "1c. Gradle --dry-run -> exit 4", f"rc={rc}")

# 1e/1f. Controls: UP-TO-DATE and FROM-CACHE are valid previous results -> PASS (exit 0)
for tag, g_out in [
    ("UP-TO-DATE", "> Task :app:compileDebugUnitTestKotlin UP-TO-DATE\n> Task :app:testDebugUnitTest UP-TO-DATE\n\nBUILD SUCCESSFUL in 1s"),
    ("FROM-CACHE", "> Task :app:testDebugUnitTest FROM-CACHE\n\nBUILD SUCCESSFUL in 1s"),
    ("mixed NO-SOURCE + ran", "> Task :lib:testDebugUnitTest NO-SOURCE\n> Task :app:testDebugUnitTest\n\nBUILD SUCCESSFUL in 1s"),
    ("plain stub (empty stdout)", ""),
]:
    rx = make_gradle_repo("g_ok_" + tag.replace(" ", "_"))
    rc, out = run_gate(rx, ["--full"], {"GRADLE_OUT": g_out})
    chk(rc == 0, f"1e. Gradle ({tag}) -> PASS (exit 0)", f"rc={rc} out={out[-240:]}")

# 1g. Non-test Gradle command (ktlintCheck / detekt / lint / assemble) -> PASS even if NO-SOURCE/SKIPPED
for tname in ("ktlintCheck", "detekt", "lintDebug", "assembleDebug"):
    rx = make_gradle_repo(f"g_nontest_{tname}", cmd=f"./gradlew :app:{tname}")
    rc, out = run_gate(rx, ["--full"], {"GRADLE_OUT": f"> Task :app:{tname} NO-SOURCE\n\nBUILD SUCCESSFUL in 1s"})
    chk(rc == 0, f"1g. Gradle non-test ({tname}) NO-SOURCE -> PASS (exit 0)", f"rc={rc}")

# 1i. keyed_full / stale_rerun returning NO-SOURCE must NOT become stale_skipped (exit 4)
r1i = make_gradle_repo("g_keyed_nosrc", cmd="true")
put(os.path.join(r1i, "docs.md"), "hi\n")
put(os.path.join(r1i, "matrix.json"), json.dumps({
    "project": "t",
    "rules": [
        {"component": "Doc", "watch_files": ["docs.md"],
         "mandatory_regression_tests": [{"id": "REG-DOC", "name": "doc", "command": "true"}]},
        {"component": "App", "watch_files": ["app/*"],
         "mandatory_regression_tests": [{"id": "REG-GRADLE", "name": "gradle", "command": "./gradlew :app:testDebugUnitTest"}]}
    ]
}))
git(r1i, "add", "docs.md", "matrix.json")
git(r1i, "commit", "-qm", "two rules")
put(os.path.join(r1i, "docs.md"), "hi 2\n")
rc, out = run_gate(r1i, ["--full"], {"GRADLE_OUT": "> Task :app:testDebugUnitTest NO-SOURCE\n\nBUILD SUCCESSFUL in 1s"})
runs = read_runs(r1i)
chk(rc == 4 and runs and runs[-1].get("exit_reason") == "no_tests_ran",
    "1i. keyed_full Gradle NO-SOURCE -> exit 4 (not stale_skipped)", f"rc={rc} runs={runs}")


# ── 2. Oracle 2: Flaky labeling (same-run flaky_retry + two-run same fp + exclusions + _run_log_fit) ────────
# 2a. Same-run flaky_retry
r2a = make_gradle_repo("flaky_same_run", cmd="sh suite.sh")
put(os.path.join(r2a, "suite.sh"),
    "if [ ! -f .once ]; then touch .once; echo 'AssertionError: flaky once'; exit 1; fi\necho ok; exit 0\n", 0o755)
git(r2a, "add", "suite.sh")
git(r2a, "commit", "-qm", "add suite")
put(os.path.join(r2a, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
rc, out = run_gate(r2a, ["--full", "--no-cache"], {"FLAKY_RETRY": "1"})
runs = read_runs(r2a)
rep = read_report(r2a)
chk(rc == 1 and runs and runs[-1].get("flaky") == ["REG-GRADLE"]
    and "FLAKY" in out and "REG-GRADLE" in out and "FLAKY" in rep and "REG-GRADLE" in rep,
    "2a. same-run flaky_retry -> exit stays 1, runs.jsonl has flaky=['REG-GRADLE'], gate stdout & report name it",
    f"rc={rc} rec={runs[-1] if runs else None}")

# 2b. Two-run same fp: Run 1 FAIL -> Run 2 PASS -> Run 2 runs.jsonl has flaky=['REG-GRADLE'] & report line, exit 0
r2b = make_gradle_repo("flaky_two_run", cmd="sh suite.sh", extra_suites=70)
put(os.path.join(r2b, "suite.sh"),
    "if [ ! -f .passed_before ]; then touch .passed_before; echo 'AssertionError: red once'; exit 1; fi\nexit 0\n", 0o755)
put(os.path.join(r2b, ".gitignore"), ".passed_before\n")
git(r2b, "add", "suite.sh", ".gitignore")
git(r2b, "commit", "-qm", "add suite")
put(os.path.join(r2b, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
rc1, _ = run_gate(r2b, ["--full", "--no-cache"])
rc2, out2 = run_gate(r2b, ["--full", "--no-cache"])
runs = read_runs(r2b)
rep2 = read_report(r2b)
raw_last = open(os.path.join(r2b, ".git/postfix-gate/runs.jsonl"), "rb").read().splitlines()[-1]
chk(rc1 == 1 and rc2 == 0 and len(runs) == 2 and runs[1].get("flaky") == ["REG-GRADLE"]
    and len(raw_last) <= 3000 and "FLAKY" in out2 and "REG-GRADLE" in out2 and "FLAKY" in rep2,
    "2b/2d. two-run same fp (with 71 suites fitting <=3000B) -> exit 0, flaky=['REG-GRADLE'] not cut, reported",
    f"rc1={rc1} rc2={rc2} bytes={len(raw_last)} rec2={runs[1] if len(runs)>1 else None}")

# 2c. Exclusions: infra / env_blocked / killed_from_outside / exit_reason != fail MUST NOT mark flaky
for kind, s_script, rc_extra in [
    ("infra", "if [ ! -f .p ]; then touch .p; echo '> java.io.EOFException'; exit 1; fi\nexit 0\n", {}),
    ("env_blocked", "if [ ! -f .p ]; then touch .p; echo 'SDK location not found'; exit 1; fi\nexit 0\n", {}),
    ("killed_143", "if [ ! -f .p ]; then touch .p; exit 143; fi\nexit 0\n", {}),
]:
    rx = make_gradle_repo("excl_" + kind, cmd="sh suite.sh")
    put(os.path.join(rx, "suite.sh"), s_script, 0o755)
    put(os.path.join(rx, ".gitignore"), ".p\n")
    git(rx, "add", "suite.sh", ".gitignore")
    git(rx, "commit", "-qm", "add suite")
    put(os.path.join(rx, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
    r_a, _ = run_gate(rx, ["--full", "--no-cache"], rc_extra)
    r_b, _ = run_gate(rx, ["--full", "--no-cache"], rc_extra)
    runs = read_runs(rx)
    chk(r_a == 1 and r_b == 0 and len(runs) == 2 and not runs[1].get("flaky"),
        f"2c. exclusion ({kind}) -> Run 2 must NOT mark flaky",
        f"r_a={r_a} r_b={r_b} rec2={runs[1] if len(runs)>1 else None}")

# 2c-bis. exit_reason != fail (e.g., exit 2 / exit 4 synthetic record) must not trigger flaky
r2c = make_gradle_repo("excl_reason", cmd="sh suite.sh")
put(os.path.join(r2c, "suite.sh"), "exit 0\n", 0o755)
git(r2c, "add", "suite.sh")
git(r2c, "commit", "-qm", "add suite")
put(os.path.join(r2c, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
sys.path.insert(0, os.path.join(os.path.dirname(GATE)))
import tree_fp
fp2c = tree_fp.tree_fingerprint(r2c)
os.makedirs(os.path.join(r2c, ".git/postfix-gate"), exist_ok=True)
with open(os.path.join(r2c, ".git/postfix-gate/runs.jsonl"), "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"v": 1, "epoch": int(time.time()) - 5, "project": "excl_reason", "mode": "full",
                         "exit": 1, "verdict": "FAIL", "fp": fp2c, "exit_reason": "project_gone",
                         "suites": [["REG-GRADLE", "FAIL", 0.1]]}) + "\n")
rc, _ = run_gate(r2c, ["--full", "--no-cache"])
runs = read_runs(r2c)
chk(rc == 0 and len(runs) == 2 and not runs[1].get("flaky"),
    "2c-bis. prior exit_reason != fail -> Run 2 must NOT mark flaky",
    f"rc={rc} rec2={runs[1] if len(runs)>1 else None}")


# ── 3. Oracle 3: rerun_skip_miss_reason ─────────────────────────────────────────────────────────────────────
r3 = make_gradle_repo("rerun_miss", cmd="sh suite.sh")
put(os.path.join(r3, "suite.sh"), "exit 0\n", 0o755)
git(r3, "add", "suite.sh")
git(r3, "commit", "-qm", "c0")
c0 = git(r3, "rev-parse", "HEAD")
put(os.path.join(r3, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 2 }\n")
git(r3, "commit", "-qam", "c1")
c1 = git(r3, "rev-parse", "HEAD")
put(os.path.join(r3, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
git(r3, "commit", "-qam", "c2")

# 3a. Run 1 --scoped --diff C1 writes rerun_skip.json
rc, out = run_gate(r3, ["--scoped", "--diff", c1], {"DEVKIT_SUITE_CACHE": "0"})
skip_file = os.path.join(r3, ".git/postfix-gate/rerun_skip.json")
chk(rc == 0 and os.path.isfile(skip_file), "3a. Run 1 --scoped --diff C1 creates rerun_skip.json", f"rc={rc}")

# 3b. Run 2 --scoped --diff C0 (wider base, same dir, same fp) -> rerun_skip_miss_reason == "base"
n_before = len(read_runs(r3))
rc, out = run_gate(r3, ["--scoped", "--diff", c0], {"DEVKIT_SUITE_CACHE": "0"})
runs = read_runs(r3)
chk(rc == 0 and len(runs) == n_before + 1 and runs[-1].get("rerun_skip_miss_reason") == "base"
    and runs[-1].get("reuse_miss_reason") != "base",
    "3b. wider base -> rerun_skip_miss_reason='base', separate from reuse_miss_reason",
    f"rc={rc} rec={runs[-1] if runs else None}")

# 3c. Run 3 with local_sha mismatch
d = json.load(open(skip_file, encoding="utf-8"))
d["local_sha"] = "0" * 40
open(skip_file, "w", encoding="utf-8").write(json.dumps(d) + "\n")
n_before = len(runs)
rc, out = run_gate(r3, ["--scoped", "--diff", c0], {"DEVKIT_SUITE_CACHE": "0"})
runs = read_runs(r3)
chk(rc == 0 and len(runs) == n_before + 1 and runs[-1].get("rerun_skip_miss_reason") == "local_sha",
    "3c. local_sha mismatch -> rerun_skip_miss_reason='local_sha'",
    f"rec={runs[-1] if runs else None}")

# 3d. Run 4 with --force -> rerun_skip_miss_reason == "force"
n_before = len(runs)
rc, out = run_gate(r3, ["--scoped", "--diff", c0, "--force"], {"DEVKIT_SUITE_CACHE": "0"})
runs = read_runs(r3)
chk(rc == 0 and len(runs) == n_before + 1 and runs[-1].get("rerun_skip_miss_reason") == "force",
    "3d. --force -> rerun_skip_miss_reason='force'",
    f"rec={runs[-1] if runs else None}")

# 3e. Run 5 with pool_busy (gate pool slot temporarily held by another process when _gate_pool_has_room runs, then released)
pool_dir = os.path.join(TMP, "pool_busy_slots")
os.makedirs(pool_dir, exist_ok=True)
holder_code = """
import fcntl, os, sys, time
p = os.path.join(sys.argv[1], "gate-1.lock")
fh = open(p, "a")
fcntl.flock(fh, fcntl.LOCK_EX)
time.sleep(2.5)
fh.close()
"""
hp = subprocess.Popen([PY, "-c", holder_code, pool_dir])
time.sleep(0.4)
n_before = len(runs)
rc, out = run_gate(r3, ["--scoped", "--diff", c0], {
    "DEVKIT_SUITE_CACHE": "0",
    "DEVKIT_GATE_SLOTS": "1",
    "SB_HEAVY_SLOT_DIR": pool_dir,
})
hp.wait(timeout=10)
runs = read_runs(r3)
chk(rc == 0 and len(runs) == n_before + 1 and runs[-1].get("rerun_skip_miss_reason") == "pool_busy",
    "3e. pool busy -> rerun_skip_miss_reason='pool_busy'",
    f"rc={rc} len={len(runs)}/{n_before} rec={runs[-1] if runs else None}")

# 3f. Run 6 with unkeyed suite (cache: false)
r3f = make_gradle_repo("rerun_unkeyed", cmd="sh suite.sh")
put(os.path.join(r3f, "suite.sh"), "exit 0\n", 0o755)
put(os.path.join(r3f, "matrix.json"), json.dumps({
    "project": "t",
    "rules": [{"component": "App", "watch_files": ["app/*"],
               "mandatory_regression_tests": [{"id": "REG-U", "name": "u", "command": "sh suite.sh", "cache": False}]}]
}))
git(r3f, "add", "-A")
git(r3f, "commit", "-qm", "init")
put(os.path.join(r3f, "app/src/main/kotlin/pkg/Core.kt"), "package pkg\nclass Core { fun v() = 3 }\n")
rc1, _ = run_gate(r3f, ["--scoped"], {"DEVKIT_SUITE_CACHE": "0"})
rc2, _ = run_gate(r3f, ["--scoped"], {"DEVKIT_SUITE_CACHE": "0"})
runs = read_runs(r3f)
chk(rc1 == 0 and rc2 == 0 and len(runs) == 2 and runs[1].get("rerun_skip_miss_reason") == "unkeyed_suite",
    "3f. unkeyed suite (cache:false) -> rerun_skip_miss_reason='unkeyed_suite'",
    f"rc1={rc1} rc2={rc2} runs={runs}")

print()
if fails:
    print(f"test_gate_no_tests_flaky_rerun_miss: {fails} FAILED")
    sys.exit(1)
print("test_gate_no_tests_flaky_rerun_miss: PASS")
PYEND
