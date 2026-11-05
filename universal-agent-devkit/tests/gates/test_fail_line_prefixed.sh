#!/usr/bin/env bash
# Test hồi quy (review #901): FAIL_LINE nhận `…Error:` có tiền tố thật của runner, không chỉ ở đầu dòng.
# #901 neo `…Error:` vào đầu dòng (hoặc sau AndroidRuntime:) để bỏ dòng INFO/✔; neo đó làm mất dòng nguyên nhân Gradle
# `   > java.lang.OutOfMemoryError:`, logcat tag khác, instrumentation `stack=`, ExceptionGroup `| ValueError:`, tiền tố container/runner.
#   a. Các dòng đó khớp.
#   b. Dòng INFO/✔ nhắc `…Error:` sau một từ thường vẫn không khớp (giữ mục b của test_fail_line_precision.sh).
#   c. Không ReDoS: dòng 1 MB xong dưới 1 s CPU (CPU tiến trình con qua tests/lib/cpu_probe.py, không đo đồng hồ tường:
#      #1010: merge gate #1007 đỏ oan vì ca này đo 5,03 s tường ở load 70; CPU thật 0,09–0,12 s, đo 05/11 ở load 23–57;
#      regex bậc hai/mũ vẫn bị RLIMIT_CPU giết ⇒ đỏ).
# Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
OUT="$(python3 -I - "$GATE" "$DEVKIT_DIR/tests/lib" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
F = mod.FAIL_LINE
hit = ["   > java.lang.OutOfMemoryError: Java heap space",
       "W/System.err: java.lang.UnsatisfiedLinkError: dlopen failed",
       "E/TestRunner: java.lang.NoSuchMethodError: No virtual method x",
       "INSTRUMENTATION_STATUS: stack=java.lang.NoSuchMethodError: y",
       "    | ValueError: boom",
       "app-1  | TypeError: x",
       "[stderr] ModuleNotFoundError: No module named 'x'",
       "12:00:00 [main] java.lang.OutOfMemoryError: Metaspace"]
miss = ["2026-11-02 12:00:01 INFO retry after SocketTimeoutError: read timed out",
        "  ✔ rejects with TypeError: bad input",
        "  ✔ maps a TypeError: to retry"]
bad = {"a": [l for l in hit if not F.search(l)], "b": [l for l in miss if F.search(l)]}
sys.path.insert(0, sys.argv[2]); import cpu_probe   # tests/lib
worst, why = cpu_probe.worst_cpu(F.search, ("a.b$" * 250000, "A$" * 500000, "a " * 500000 + "TypeError", "|" * 1000000), 1.0)
bad["c"] = [] if worst < 1.0 else ["dòng 1 MB tốn %.2f s CPU (%s)" % (worst, why)]
for k in sorted(bad):
    print(("%s_ok" % k) if not bad[k] else ("%s_bad %s" % (k, " | ".join(bad[k]))))
PY
)"
FAILS=0
check() {   # <key> <mô tả>
  if printf '%s\n' "$OUT" | grep -qx "$1_ok"; then echo "✔ $1 $2"
  else echo "✖ $1 $2: $(printf '%s\n' "$OUT" | grep -E "^($1_bad|Traceback|[A-Za-z]*Error)" | head -5 | tr '\n' ';')"; FAILS=$((FAILS + 1)); fi
}
check a "…Error: sau tiền tố Gradle '>', logcat tag, stack=, '|', '[x]' khớp"
check b "dòng INFO/✔ nhắc …Error: sau một từ thường không khớp"
check c "không ReDoS: dòng 1 MB xong dưới 1 s CPU"
[ "$FAILS" -eq 0 ] && { echo "test_fail_line_prefixed: PASS"; exit 0; }
echo "test_fail_line_prefixed: FAIL ($FAILS)"
exit 1
