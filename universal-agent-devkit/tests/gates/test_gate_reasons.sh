#!/usr/bin/env bash
# Regression test (audit of 3 real repos, 2026-09-27): a Stop block must say WHY.
#  1. post-fix-gate's proof-folder check did not _record() its findings, so the JSON summary had
#     none and regression_gate blocked with "REJECT" and no reason (GeelyEx2: 10 blocks).
#  2. A suite failed for vacuity (production diff reverted, test still green) was shown as a bare
#     "FAIL" whose command exits 0 (OfficeReader: 5 blocks, ~25 min).
#  3. A crashed gate (Python traceback, exit 1, no JSON) read as REJECT with no reason.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. proof findings reach the JSON summary ───────────────────────────────────
R="$TMP/repo"; mkdir -p "$R/src" "$R/reports" "$R/.agents" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"true"}]}]}\n' \
  > .agents/regression_matrix.active.json
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + b"x" * 9000)' reports/proof-a.png
cp reports/proof-a.png reports/proof-b.png
CLAUDE_PROJECT_DIR="$R" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json > "$TMP/gate.out" 2>&1
python3 - "$TMP/gate.out" <<'PY' && ok "a duplicated proof image is a finding in the JSON summary (category proof)" || fail "proof finding missing from the summary"
import json, sys
last = [l for l in open(sys.argv[1], encoding="utf-8") if l.startswith("{")][-1]
d = json.loads(last)
sys.exit(0 if any(f.get("category") == "proof" and "proof-" in (f.get("file") or "") for f in d.get("findings", [])) else 1)
PY

# A retake of the same success screen (≥98% similar, not byte-identical) warns, never blocks:
# blocking made agents delete older proofs to pass (OfficeReader 2026-09-26: 8 times).
rm -f reports/proof-*.png
python3 - reports <<'PY'
import struct, sys, zlib
def png(rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw, 0)) + ch(b"IEND", b"")
rows = [[(x * 7 + y * 3) % 256 for x in range(120)] for y in range(90)]
open(sys.argv[1] + "/proof-c.png", "wb").write(png(rows))
rows[45][60] = (rows[45][60] + 1) % 256
open(sys.argv[1] + "/proof-d.png", "wb").write(png(rows))
PY
CLAUDE_PROJECT_DIR="$R" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json > "$TMP/gate2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "98%" "$TMP/gate2.out" && ok "a ≥98% similar retake warns (named) and does not block" \
  || fail "similar retake: rc=$rc $(grep -E '98%|KẾT LUẬN|VERDICT' "$TMP/gate2.out" | head -3)"
cmp -s reports/proof-c.png reports/proof-d.png && fail "test setup: images identical" || true

# ── 2 + 3. the hook prints the reason (fake kit whose gate returns a canned result) ──
FK="$TMP/fakekit"; mkdir -p "$FK/hooks" "$FK/bin"
cp "$DEVKIT_DIR/hooks/regression_gate.sh" "$FK/hooks/"
for f in "$DEVKIT_DIR"/hooks/*.py; do ln -s "$f" "$FK/hooks/"; done
H="$TMP/h"; mkdir -p "$H/src" "$H/.agents" && cd "$H" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-V","name":"c","command":"true"}]}]}\n' \
  > .agents/regression_matrix.active.json
git add -A && git commit -qm init
stop() { printf '{"session_id":"%s","hook_event_name":"Stop"}' "$1" \
  | CLAUDE_PROJECT_DIR="$H" bash "$FK/hooks/regression_gate.sh" >"$TMP/out" 2>"$TMP/err"; }

cat > "$FK/bin/post-fix-gate.py" <<'PY'
import json, sys
print(json.dumps({"verdict": "REJECT", "exit_code": 1, "files": ["src/Core.kt"], "regression_tests": [
    {"id": "REG-V", "name": "c", "status": "FAIL", "label": "VACUOUS", "exit_code": 0, "command": "true",
     "output_tail": "Test rỗng: revert mã nguồn sản xuất mà test vẫn XANH — không có năng lực phát hiện lỗi"}],
    "findings": [], "report": "r.md"}))
sys.exit(1)
PY
echo "fun ok() = 2" > src/Core.kt
stop s-v; rc=$?
[ "$rc" = 2 ] && grep -q "VACUOUS" "$TMP/err" && grep -q "revert" "$TMP/err" \
  && ok "a vacuous suite is named VACUOUS with the reason, not a bare FAIL" || fail "vacuity reason missing (rc=$rc): $(cat "$TMP/err")"

# BUSY suites (another run holds the lock; the gate writes status UNTESTED, label BUSY) are not failures: nothing to fix, run again later
# (2026-09-27: 6 BUSY suites listed as failing, with "fix code/test").
cat > "$FK/bin/post-fix-gate.py" <<'PY'
import json, sys
print(json.dumps({"verdict": "UNVERIFIED", "exit_code": 2, "files": ["src/Core.kt"], "tests_touched": ["tests/t.sh"],
    "regression_tests": [{"id": "REG-B", "name": "c", "status": "UNTESTED", "label": "BUSY", "command": "true",
                          "output_tail": "Một lượt chạy test khác giữ khoá dự án"}], "findings": [], "report": "r.md"}))
sys.exit(2)
PY
echo "fun ok() = 4" > src/Core.kt
stop s-b; rc=$?
grep -q "REG-B" "$TMP/err" && grep -q "chạy lại" "$TMP/err" && ! grep -q "Sửa code/test" "$TMP/err" \
  && ok "BUSY suites are named as not run yet, never as failures to fix" || fail "BUSY shown as failure (rc=$rc): $(cat "$TMP/err")"

cat > "$FK/bin/post-fix-gate.py" <<'PY'
raise ValueError("boom in the gate")
PY
echo "fun ok() = 3" > src/Core.kt
stop s-c; rc=$?
[ "$rc" = 0 ] && grep -q "boom in the gate" "$TMP/out" \
  && ok "a crashed gate (no JSON) is reported as a crash with its error, not a reasonless block" \
  || fail "crash handled wrong (rc=$rc): out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
cd "$TMP" || exit 1

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_reasons: all passed" || { echo "❌ test_gate_reasons: $FAILS failed"; exit 1; }
