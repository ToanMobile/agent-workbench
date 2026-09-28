#!/usr/bin/env bash
# Regression test: bin/regression_checklist.py reads a test runner only as a command, never as a
# word inside a quoted argument. GeelyEx2 2026-09-28: `python3 -c "import pytest; import cv2" &&
# pytest tests/qc/a.py` split on the `;` inside the quotes, so `python3 -c "import pytest` counted
# as a pytest run of every .py test and hid every new orphan .py test.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tests/qc"; : > "$TMP/tests/qc/a.py"
FAILS=0
scope() { python3 - "$DEVKIT_DIR/bin" "$TMP" "$1" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path
import regression_checklist as rc
runs = [r for c, seg in rc._segments(sys.argv[3]) for r in [rc._runner(Path(sys.argv[2]), c, seg)] if r]
print(sorted(r[1] or ["<every test>"] for r in runs))
PY
}
check() { # name command expected
  local got; got="$(scope "$2")"
  [ "$got" = "$3" ] && echo "✔ $1" || { echo "✖ $1: got $got, expected $3"; FAILS=$((FAILS + 1)); }
}
check "pytest inside python -c \"…; …\" is not a run" 'python3 -c "import pytest; import cv2" 2>/dev/null && pytest tests/qc/a.py || exit 2' "[['tests/qc/a.py']]"
check "pytest inside python -c '…' is not a run" "python3 -c 'import pytest' && pytest tests/qc/a.py" "[['tests/qc/a.py']]"
check "a real pytest run keeps its scope" "pytest tests/qc/a.py" "[['tests/qc/a.py']]"
check "a bare pytest still means every test" "cd tests && pytest" "[['<every test>']]"
[ "$FAILS" -eq 0 ] && echo "runner quoted: all checks passed" || { echo "runner quoted: $FAILS FAILED"; exit 1; }
