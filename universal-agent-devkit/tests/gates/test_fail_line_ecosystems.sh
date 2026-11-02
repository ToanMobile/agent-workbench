#!/usr/bin/env bash
# Test hồi quy: FAIL_LINE của bin/post-fix-gate.py nhận dòng hỏng của runner ở 5 repo app, không chỉ ✖/FAIL/ERROR.
# Đo 02/11: 12/14 dòng lỗi mẫu trượt (Kotlin `e:`, Gradle `What went wrong`, Unity `error CS…`, pytest `E   …`, jest `●`,
# `npm ERR!`, `FATAL EXCEPTION`, `…Error:`, segfault, `Killed: 9`). Khối '| …' của suite đỏ = fail_lines + 5 dòng cuối, nên với
# Gradle agent chỉ thấy đuôi "BUILD FAILED / Get more help", còn dòng `e:` thật nằm giữa log.
#   a. FAIL_LINE khớp từng dòng hỏng và KHÔNG khớp dòng nhiễu (task graph, download, warning `w:`, BUILD SUCCESSFUL).
#   b. Lượt gate thật trên suite giả kiểu Gradle: fail_lines (--json) và khối '| …' có dòng `e:` của Kotlin.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_DIRS DEVKIT_IMPACTED_SINCE \
  DEVKIT_PER_TEST_CACHE DEVKIT_ALONE_AFTER_FILE DEVKIT_TEST_JOBS FLAKY_RETRY WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # pool slot riêng: không chờ pool gate toàn máy
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# --- a. FAIL_LINE: dòng hỏng / dòng nhiễu ---------------------------------------------------------------------------------
python3 -I - "$GATE" > "$TMP/a.res" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
hit = [
    "e: file:///app/src/main/java/A.kt:12:5 Unresolved reference: foo",              # Kotlin 2
    "e: /app/src/main/java/A.kt: (12, 5): Unresolved reference: foo",                 # Kotlin 1
    "* What went wrong:",                                                              # Gradle
    "Execution failed for task ':app:compileDebugKotlin'.",
    "Assets/Scripts/Player.cs(12,5): error CS0103: The name 'x' does not exist",      # Unity / C#
    "src/Main.java:12: error: cannot find symbol",                                     # javac / clang / swiftc
    "E       assert 1 == 2",                                                           # pytest
    "  ● Cart › adds item",                                                            # jest
    "npm ERR! code ELIFECYCLE",
    "npm error code ELIFECYCLE",                                                       # npm ≥ 10
    "FATAL EXCEPTION: main",                                                           # Android logcat
    "java.lang.OutOfMemoryError: Java heap space",
    "ValueError: invalid literal for int()",
    "Segmentation fault: 11",
    "Killed: 9",
]
miss = [
    "> Task :app:compileDebugKotlin",
    "w: file:///app/src/main/java/A.kt:3:1 'onBackPressed(): Unit' is deprecated",
    "Download https://repo.maven.apache.org/maven2/com/google/errorprone/error_prone_annotations/2.3.4/x.jar",
    "BUILD SUCCESSFUL in 3s",
    "Deprecated Gradle features were used in this build, making it incompatible with Gradle 9.0.",
    "  ✔ maps a TypeError to a retry",
    "e2e: starting emulator",
    "Starting a Gradle Daemon (subsequent builds will be faster)",
]
bad = [l for l in hit if not mod.FAIL_LINE.search(l)] + ["(nhiễu) " + l for l in miss if mod.FAIL_LINE.search(l)]
for l in bad:
    print("BAD", l)
print("a_ok" if not bad else "a_bad %d" % len(bad))
PY
if grep -qx a_ok "$TMP/a.res"; then ok "a FAIL_LINE khớp 15 dòng hỏng của Gradle/Kotlin/Unity/javac/pytest/jest/npm/Android/signal, bỏ 8 dòng nhiễu"
else fail "a: $(grep -E '^(BAD|a_bad|Traceback|[A-Za-z]*Error)' "$TMP/a.res" | head -20 | tr '\n' ';')"; fi

# --- b. lượt gate thật: suite giả kiểu Gradle ------------------------------------------------------------------------------
ORIGIN="$TMP/b/origin.git"; REPO="$TMP/b/repo"; mkdir -p "$TMP/b"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-APP-GRADLE-01","name":"Gradle giả: lỗi biên dịch Kotlin","command":"bash gradle.sh"}]}]}
JSON
  # như ./gradlew test in khi Kotlin không biên dịch được: dòng e: ở giữa, đuôi là lời khuyên chung của Gradle
  { echo 'echo "> Task :app:preBuild UP-TO-DATE"'; echo 'echo "> Task :app:compileDebugKotlin"'
    echo 'echo "w: file:///r/app/src/main/java/A.kt:3:1 x is deprecated"'
    echo 'echo "e: file:///r/app/src/main/java/A.kt:12:5 Unresolved reference: fooBar"'
    echo 'echo "> Task :app:compileDebugKotlin FAILED"'; echo 'echo ""'
    echo 'echo "FAILURE: Build failed with an exception."'; echo 'echo "* What went wrong:"'
    echo 'echo "Execution failed for task :app:compileDebugKotlin."'; echo 'echo "* Try:"'
    echo 'echo "> Run with --stacktrace option to get the stack trace."'; echo 'echo "> Run with --info or --debug option to get more log output."'
    echo 'echo "> Run with --scan to get full insights."'; echo 'echo "> Get more help at https://help.gradle.org."'
    echo 'echo "BUILD FAILED in 4s"'; echo 'exit 1'; } > gradle.sh
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
CLAUDE_PROJECT_DIR="$REPO" FLAKY_RETRY=0 python3 "$GATE" --no-checklist --run-tests --tree HEAD --no-cache --json > "$TMP/b.out" 2>&1
python3 -I - "$TMP/b.out" > "$TMP/b.res" 2>&1 <<'PY'
import json, re, sys
plain = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1], encoding="utf-8", errors="replace").read())
data = {}
for line in reversed(plain.splitlines()):
    if line.strip().startswith("{"):
        try:
            data = json.loads(line)
            break
        except ValueError:
            pass
tests = [t for t in data.get("regression_tests") or [] if t.get("id") == "REG-APP-GRADLE-01"]
fl = (tests[0].get("fail_lines") or []) if tests else []
block = [l.strip() for l in plain.splitlines() if l.strip().startswith("| ")]
E = "e: file:///r/app/src/main/java/A.kt:12:5 Unresolved reference: fooBar"
print("status", tests[0].get("status") if tests else None)
print("b1" if E in fl else "b1_no", json.dumps(fl, ensure_ascii=False)[:600])
print("b2" if ("| " + E) in block else "b2_no", json.dumps(block, ensure_ascii=False)[:600])
print("b3" if not any(l.startswith("w: ") for l in fl) else "b3_no")
PY
res() { grep -q "^$1\b" "$TMP/b.res" && ! grep -q "^$1_no" "$TMP/b.res"; }
info() { cut -c1-700 "$TMP/b.res" | tr '\n' ' '; [ -s "$TMP/b.res" ] || tail -n 5 "$TMP/b.out"; }
grep -q "^status FAIL" "$TMP/b.res" && ok "b0 suite Gradle giả đỏ (FAIL)" || fail "b0: $(info)"
res b1 && ok "b1 fail_lines có dòng e: của Kotlin" || fail "b1: $(info)"
res b2 && ok "b2 khối '| …' in dòng e: của Kotlin" || fail "b2: $(info)"
res b3 && ok "b3 warning w: không vào fail_lines" || fail "b3: $(info)"

[ "$FAILS" -eq 0 ] && { echo "test_fail_line_ecosystems: PASS"; exit 0; }
echo "test_fail_line_ecosystems: FAIL ($FAILS)"
exit 1
