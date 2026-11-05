#!/usr/bin/env bash
# Test hồi quy #906: nhánh `…Error:` của FAIL_LINE (bin/post-fix-gate.py) xét từ đầu tên gói, không từ tên lớp.
#   a. Dòng INFO có tên lớp đầy đủ sau một từ thường (`retry after java.net.SocketTimeoutError:`) không khớp: trước đó lookbehind chỉ
#      thấy `t.` trước tên lớp nên dòng này lọt vào 8 dòng đầu của fail_lines.
#   b. Dòng lỗi thật vẫn khớp: đầu dòng, Gradle `   > `, logcat tag, `stack=`, `| `, `[x] `, `Caused by: `, lớp lồng `$`.
#   c. Không ReDoS: dòng 1 MB (gồm `Ab` lặp, thứ làm nhánh bậc hai khi bỏ phần neo đầu tên) xong dưới 1 s CPU (CPU tiến trình
#      con qua tests/lib/cpu_probe.py, không đo đồng hồ tường: #1010).
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
miss = ["2026-11-02 12:00:01 INFO retry after java.net.SocketTimeoutError: read timed out",
        "D/OkHttp: retry after okhttp3.internal.http2.StreamResetError: x",
        "  ✔ rejects with TypeError: bad input"]
hit = ["java.lang.OutOfMemoryError: Java heap space",
       "   > java.lang.OutOfMemoryError: Java heap space",
       "W/System.err: java.lang.UnsatisfiedLinkError: dlopen failed",
       "INSTRUMENTATION_STATUS: stack=java.lang.NoSuchMethodError: y",
       "    | ValueError: boom",
       "[stderr] ModuleNotFoundError: No module named 'x'",
       "Caused by: com.x.Outer$InnerError: m",
       "\tandroidx.test.espresso.base.DefaultFailureHandler$AssertionFailedWithCauseError: 'is displayed' doesn't match",
       "E AndroidRuntime: java.lang.OutOfMemoryError: Failed to allocate"]
bad = {"a": [l for l in miss if F.search(l)], "b": [l for l in hit if not F.search(l)]}
sys.path.insert(0, sys.argv[2]); import cpu_probe   # tests/lib
worst, why = cpu_probe.worst_cpu(F.search, ("Ab" * 500000, "a.b$" * 250000, "x " * 250000 + "Ab" * 250000, "java." * 200000 + "x"), 1.0)
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
check a "dòng INFO có tên lớp đầy đủ sau một từ thường không khớp"
check b "dòng lỗi thật (đầu dòng, Gradle >, logcat, stack=, |, [x], Caused by, lớp lồng \$) vẫn khớp"
check c "không ReDoS: dòng 1 MB (gồm Ab lặp) xong dưới 1 s CPU"
[ "$FAILS" -eq 0 ] && { echo "test_fail_line_qualified: PASS"; exit 0; }
echo "test_fail_line_qualified: FAIL ($FAILS)"
exit 1
