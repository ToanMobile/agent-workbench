#!/usr/bin/env bash
# Test hồi quy (review #899): FAIL_LINE của bin/post-fix-gate.py bắt đúng định dạng thật và không lấy dòng xanh/INFO.
#   a. Định dạng job-report của bash (`x.sh: line N: PID Killed: 9 cmd`) khớp; trước đó nhánh Killed neo đầu dòng nên trượt.
#   b. `…Error:` giữa dòng INFO hoặc dòng ✔ không khớp: chúng chiếm chỗ trong 8 dòng đầu của fail_lines, đẩy dòng lỗi thật ra.
#   c. Mỗi nhánh mới của #899 có một mẫu: MSBuild, clang/swiftc `file:N:N: error`, `fatal error`, Bus error, Abort trap.
# Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
OUT="$(python3 -I - "$GATE" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
hit = {
    "a": ["tests/a.sh: line 40: 1234 Killed: 9   sleep 100"],
    "c": ["App/App.csproj : error MSB3027: Could not copy \"obj/App.dll\"",
          "src/a.c:3:5: error: use of undeclared identifier 'x'",
          "Sources/App/View.swift:12:9: error: cannot find 'foo' in scope",
          "src/a.c:1:10: fatal error: 'missing.h' file not found",
          "Bus error: 10",
          "Abort trap: 6",
          "Caused by: java.lang.NoClassDefFoundError: com/x/Y"],
}
miss = {
    "b": ["2026-11-02 12:00:01 INFO retry after SocketTimeoutError: read timed out",
          "  ✔ rejects with TypeError: bad input"],
}
bad = {}
for k, lines in hit.items():
    bad.setdefault(k, []).extend(l for l in lines if not mod.FAIL_LINE.search(l))
for k, lines in miss.items():
    bad.setdefault(k, []).extend("(nhiễu) " + l for l in lines if mod.FAIL_LINE.search(l))
for k in sorted(bad):
    print(("%s_ok" % k) if not bad[k] else ("%s_bad %s" % (k, " | ".join(bad[k]))))
PY
)"
FAILS=0
check() {   # <key> <mô tả>
  if printf '%s\n' "$OUT" | grep -qx "$1_ok"; then echo "✔ $1 $2"
  else echo "✖ $1 $2: $(printf '%s\n' "$OUT" | grep -E "^($1_bad|Traceback|[A-Za-z]*Error)" | head -5 | tr '\n' ';')"; FAILS=$((FAILS + 1)); fi
}
check a "job-report của bash 'line N: PID Killed: 9' khớp"
check b "'…Error:' giữa dòng INFO / dòng ✔ không khớp"
check c "MSBuild, clang/swiftc file:N:N: error, fatal error, Bus error, Abort trap, Caused by …Error: khớp"
[ "$FAILS" -eq 0 ] && { echo "test_fail_line_precision: PASS"; exit 0; }
echo "test_fail_line_precision: FAIL ($FAILS)"
exit 1
