#!/usr/bin/env bash
# Test hồi quy #909 (review #908): nhánh `…Error:` của FAIL_LINE (bin/post-fix-gate.py) còn trượt ba dòng lỗi thật và một test neo có thể treo.
#   a. JVM thật in `Terminating due to java.lang.OutOfMemoryError: Java heap space` (ExitOnOutOfMemoryError) / `Aborting due to …` (Crash…):
#      tên lớp đứng sau từ thường nên nhánh `…Error:` bỏ qua; Python in `test_x.<locals>.CustomError: boom`, `...LinkageError:`, `Foo$$InnerError:`.
#   b. `retry after java.net.SocketTimeoutError: read timed out` vẫn không khớp (nhánh mới không nới lỏng #906).
#   c. `Ab` * 20000 (40 KB) xong dưới 1 s CPU; bản bỏ neo `(?<![\w.$])` làm search bậc hai và vượt ngưỡng (kiểm ngay trong test: oracle phân biệt).
# CPU của tiến trình con qua tests/lib/cpu_probe.py, không đo đồng hồ tường (#1010). Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
OUT="$(python3 -I - "$GATE" "$DEVKIT_DIR/tests/lib" 2>&1 <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
F = mod.FAIL_LINE
hit = ["Terminating due to java.lang.OutOfMemoryError: Java heap space",
       "Aborting due to java.lang.OutOfMemoryError: Java heap space",
       "   > Terminating due to java.lang.OutOfMemoryError: Java heap space",
       "test_x.<locals>.CustomError: boom",
       "E   test_x.<locals>.CustomError: boom",
       "Caused by: ...java.lang.LinkageError: bad",
       "Foo$$InnerError: x"]
miss = ["2026-11-02 12:00:01 INFO retry after java.net.SocketTimeoutError: read timed out",
        "D/OkHttp: retry after okhttp3.internal.http2.StreamResetError: x",
        "INFO retry after Terminating due to java.lang.OutOfMemoryError: x"]
bad = {"a": [l for l in hit if not F.search(l)], "b": [l for l in miss if F.search(l)]}
sys.path.insert(0, sys.argv[2]); import cpu_probe   # tests/lib
big = "Ab" * 20000
worst, why = cpu_probe.worst_cpu(F.search, (big, "Ab" * 500000), 1.0)
bad["c"] = [] if worst < 1.0 else ["40 KB tốn %.2f s CPU (%s)" % (worst, why)]
# d. oracle phân biệt: bỏ neo `(?<![\w.$])` ⇒ input 40 KB phải vượt 1 s CPU (bị RLIMIT_CPU giết trong ~2 s, không treo)
src = F.pattern
assert src.count(r"(?<![\w.$])") == 1, "neo không còn đúng một lần: cập nhật test"
mutant = re.compile(src.replace(r"(?<![\w.$])", ""))
mw, mwhy = cpu_probe.worst_cpu(mutant.search, (big,), 1.0)
bad["d"] = [] if mw >= 1.0 else ["bản bỏ neo vẫn nhanh (%.2f s): input 40 KB không bắt được hồi quy" % mw]
for k in sorted(bad):
    print(("%s_ok" % k) if not bad[k] else ("%s_bad %s" % (k, " | ".join(bad[k]))))
PY
)"
FAILS=0
check() {   # <key> <mô tả>
  if printf '%s\n' "$OUT" | grep -qx "$1_ok"; then echo "✔ $1 $2"
  else echo "✖ $1 $2: $(printf '%s\n' "$OUT" | grep -E "^($1_bad|Traceback|[A-Za-z]*Error)" | head -5 | tr '\n' ';')"; FAILS=$((FAILS + 1)); fi
}
check a "OOM của JVM, lớp <locals>, ...X, \$\$ khớp"
check b "dòng INFO 'retry after java.net.…Error:' vẫn không khớp"
check c "40 KB 'Ab' xong dưới 1 s CPU"
check d "bỏ neo (?<![\\w.\$]) thì 40 KB vượt 1 s CPU (oracle phân biệt)"
[ "$FAILS" -eq 0 ] && { echo "test_fail_line_oom_locals: PASS"; exit 0; }
echo "test_fail_line_oom_locals: FAIL ($FAILS)"
exit 1
