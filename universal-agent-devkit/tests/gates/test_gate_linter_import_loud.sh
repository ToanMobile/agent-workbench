#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, Goods) for bin/post-fix-gate.py run_performance_audit: both AST linters (Compose stability,
# Unity Zero-GC) were imported inside ONE `try … except Exception: pass`. A broken or missing linter module switched the lint off with no
# word — the gate went green on code it never linted — and one failing import also took the other linter down. Now each import is its own
# try and a failure is printed (log_err, not blocking): which linter, why, and that its lint is OFF for the run. Only the audit runs here.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

cat > "$TMP/driver.py" <<'PY'
import contextlib, importlib.util, io, pathlib, sys
gate, kit = sys.argv[1:3]
spec = importlib.util.spec_from_file_location("pfg_under_test", gate)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod.get_devkit_dir = lambda: pathlib.Path(kit)
# the gate puts its own kit's script dirs on sys.path while it loads: drop them, or a "missing" linter still imports from the real kit
real = str(pathlib.Path(gate).resolve().parent.parent / "scripts")
sys.path[:] = [p for p in sys.path if not p.startswith(real)]
for m in ("lint_compose_stability", "lint_unity_gc"):
    sys.modules.pop(m, None)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ok, findings = mod.run_performance_audit(sys.argv[3].split(",") if len(sys.argv) > 3 and sys.argv[3] else [])
print(buf.getvalue())
PY

# run <kit> [changed files, comma separated]; one process per case: no import cache shared between kits
run() { python3 -I "$TMP/driver.py" "$GATE" "$1" "${2:-Foo.kt,Bar.cs}" 2>&1; }

# kit with neither linter, with only the Compose linter, and the real one
mkdir -p "$TMP/none/scripts/linters" "$TMP/nounity/scripts/linters"
cp "$DEVKIT_DIR/scripts/linters/lint_compose_stability.py" "$TMP/nounity/scripts/linters/"

out="$(run "$TMP/none")"
echo "$out" | grep -q 'lint_compose_stability' && ok "missing Compose linter is reported" || fail "missing Compose linter was swallowed: $out"
echo "$out" | grep -q 'lint_unity_gc'          && ok "missing Unity linter is reported"   || fail "missing Unity linter was swallowed: $out"
echo "$out" | grep -q 'OFF'                     && ok "the report says the lint is OFF"     || fail "no 'OFF' in the report: $out"

out="$(run "$TMP/nounity")"
echo "$out" | grep -q 'lint_unity_gc'          && ok "only the Unity linter missing: it is reported" || fail "Unity import failure swallowed (Compose present): $out"
echo "$out" | grep -q 'lint_compose_stability' && fail "a working Compose linter was reported as failed: $out" || ok "a working Compose linter is not reported"

out="$(run "$DEVKIT_DIR")"
echo "$out" | grep -qE 'lint_unity_gc|lint_compose_stability|OFF' && fail "complete kit reported a linter problem: $out" || ok "complete kit: silent, as before"

# a linter nobody needs is neither loaded nor reported: no .kt / .cs in the change, or only the other language
out="$(run "$TMP/none" "README.md,app.py")"
[ -z "$(echo "$out" | tr -d '[:space:]')" ] && ok "no .kt/.cs changed: silent although both linters are missing" || fail "noise for a change without .kt/.cs: $out"
out="$(run "$TMP/none" "Foo.kt")"
echo "$out" | grep -q 'lint_unity_gc' && fail "Unity linter reported for a Kotlin-only change: $out" || ok "Kotlin-only change: the Unity linter is not asked for"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_linter_import_loud: all passed" || { echo "❌ test_gate_linter_import_loud: $FAILS failed"; exit 1; }
