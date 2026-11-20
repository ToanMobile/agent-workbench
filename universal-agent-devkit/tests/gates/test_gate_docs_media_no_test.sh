#!/usr/bin/env bash
# Regression test (#1386) for bin/post-fix-gate.py needs_no_test: deleting four tracked plan/*.jpg screenshots in OfficeReader made the
# merge gate exit 2 ("no regression test matches"), since images/PDF were not documentation. Static media under plan/ or docs/ is read
# by no program; the same files elsewhere (app assets) and html/js/json under docs/ (can run code) still need coverage.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
python3 -I - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
NO_TEST = ["plan/2026-10-10 17.47.22.jpg", "plan/x.JPG", "docs/img/a.png", "docs/a.pdf", "docs/img/b.svg", "plan/c.webp", "docs/d.gif",
           "docs/e.jpeg", "README.md"]
NEEDS = ["assets/a.png", "res/drawable/a.png", "Assets/Textures/a.png", "docs/play/a.html", "docs/a.js", "docs/data.json",
         "src/code.py", "other/plan/x.jpg", "planning/x.jpg"]
bad = 0
for f in NO_TEST:
    ok = m.needs_no_test(f); print(("✔" if ok else "✖") + f" needs no test: {f}"); bad += not ok
for f in NEEDS:
    ok = not m.needs_no_test(f); print(("✔" if ok else "✖") + f" still needs a test: {f}"); bad += not ok
mixed = ["docs/img/a.png", "src/code.py"]
ok = not all(m.needs_no_test(f) for f in mixed); print(("✔" if ok else "✖") + " mixed docs image + code still needs a test"); bad += not ok
print("✅ test_gate_docs_media_no_test: all passed" if not bad else f"❌ test_gate_docs_media_no_test: {bad} failed")
sys.exit(1 if bad else 0)
PY
