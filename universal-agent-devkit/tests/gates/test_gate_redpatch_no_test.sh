#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, Goods) for bin/post-fix-gate.py needs_no_test: untracking two red-proof patches under
# .agents/local/red-patches/ made the gate exit 2 ("no regression test matches the change"), because only documentation, agent state files
# and .agents/local/memory/ counted as "nothing a regression test could catch". A bug-back patch is data of the RED-proof tool that a
# regression test never runs: adding, changing or removing one needs no test. Project hooks / scripts under .agents/local/ still do.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
python3 -I - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
NO_TEST = [".agents/local/red-patches/BUG-P1-10.patch", ".agents/local/red-patches/BUG-20261010-x.patch",
           ".agents/local/memory/claude-auto/note.md", "README.md"]                               # the last two: unchanged behaviour
NEEDS = [".agents/local/hooks/project_hook.sh", ".agents/local/red-patches-evil/x.py", "src/main.kt", "Assets/Scripts/A.cs",
         ".agents/local/rules-helper.py"]
bad = 0
for f in NO_TEST:
    ok = m.needs_no_test(f)
    print(("✔" if ok else "✖") + f" needs no test: {f}"); bad += not ok
for f in NEEDS:
    ok = not m.needs_no_test(f)
    print(("✔" if ok else "✖") + f" still needs a test: {f}"); bad += not ok
print("✅ test_gate_redpatch_no_test: all passed" if not bad else f"❌ test_gate_redpatch_no_test: {bad} failed")
sys.exit(1 if bad else 0)
PY
