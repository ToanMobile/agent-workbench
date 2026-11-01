#!/usr/bin/env bash
# Kiểm thử hồi quy #780: chặn lỗi SIGPIPE / EPIPE (`printf: write error: Broken pipe`)
# khi dùng pipeline sang `grep -q` dưới `set -... pipefail` trong bộ test của DevKit:
# 1. Thực thi trực tiếp `test_impeccable_skill.sh` với biến môi trường lớn (> 128 KiB > pipe buffer 64 KiB)
#    để kiểm tra nhánh kiểm `ENV_DUMP` (dòng 114–116) không bị gãy pipe.
# 2. Thực thi trực tiếp `test_impeccable_skill.sh` với shim `python3` sinh `PROF_OUT` 6000 dòng (> 80 KiB,
#    `impeccable` đứng đầu) cho các profile UI: bản cũ ĐỎ vì `Broken pipe`, bản mới XANH.
# 3. Đối chứng âm (negative control) cô lập cho nhánh `elif` ở profile `backend`: chỉ riêng `backend` trả
#    `impeccable` + 6000 dòng; bản cũ dính `SIGPIPE` ở `elif` rơi sang `else pass` (thoát 0 giả!),
#    còn bản mới bắt buộc phát hiện và đánh FAIL (`rc != 0`).
# 4. Quét tĩnh toàn bộ `universal-agent-devkit/tests/**/*.sh` bật `pipefail` ở cấp ngoài cùng: không còn
#    pipeline sang `grep -q` / `--quiet` / `--silent` gây chập chờn theo lịch lập lịch CPU.

. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_TEST="$DEVKIT_ROOT/tests/verification/test_impeccable_skill.sh"
REAL_PYTHON3="$(command -v python3)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test_impeccable_pipefail.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILS=0
PASSES=0

pass() {
  echo "  ✔ $1"
  PASSES=$((PASSES + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAILS=$((FAILS + 1))
}

echo "=== Regression #780: pipefail + grep -q SIGPIPE guard ==="

# Chuỗi đệm > 128 KiB vượt xa pipe buffer 64 KiB của macOS/Linux
BIG_ENV_PAD="$("$REAL_PYTHON3" -c 'print("x" * 131072)')"

# ---------------------------------------------------------------------------
# 1. Kiểm tra nhánh ENV_DUMP (dòng 114–116) với biến môi trường > 128 KiB
# ---------------------------------------------------------------------------
ENV_OUT="$(ZZZ_PIPEFAIL_PAD_780="$BIG_ENV_PAD" bash "$TARGET_TEST" 2>&1)"
ENV_RC=$?
if [[ "$ENV_RC" -eq 0 ]] && ! grep -Fq "Broken pipe" <<<"$ENV_OUT"; then
  pass "test_impeccable_skill.sh XANH khi ENV_DUMP vượt 128 KiB dưới pipefail (không bị Broken pipe)"
else
  fail "test_impeccable_skill.sh ĐỎ với ENV_DUMP > 128 KiB (rc=$ENV_RC): $(grep -E 'FAIL:|Broken pipe' <<<"$ENV_OUT" | head -n 3 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. Kiểm tra nhánh PROF_OUT > 80 KiB (6000 dòng, impeccable ở dòng 1) — tái hiện #780
# ---------------------------------------------------------------------------
mkdir -p "$TMP_DIR/bin-pos"
cat >"$TMP_DIR/bin-pos/python3" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == */profile_skills.py ]]; then
  prof="\${2:-}"
  case "\$prof" in
    web|android|ios|automotive|universal|voice-assistant)
      printf 'impeccable\n'
      exec "$REAL_PYTHON3" -c 'import sys; sys.stdout.write("".join(f"skill-pad-{i:04d}\n" for i in range(6000)))'
      ;;
    backend|game)
      exec "$REAL_PYTHON3" -c 'import sys; sys.stdout.write("".join(f"skill-pad-{i:04d}\n" for i in range(6000)))'
      ;;
  esac
fi
exec "$REAL_PYTHON3" "\$@"
EOF
chmod +x "$TMP_DIR/bin-pos/python3"

POS_OUT="$(PATH="$TMP_DIR/bin-pos:$PATH" bash "$TARGET_TEST" 2>&1)"
POS_RC=$?
if [[ "$POS_RC" -eq 0 ]] && ! grep -Fq "Broken pipe" <<<"$POS_OUT"; then
  pass "test_impeccable_skill.sh XANH khi PROF_OUT dài 6000 dòng (> 80 KiB, impeccable ở đầu)"
else
  fail "test_impeccable_skill.sh ĐỎ khi PROF_OUT dài 6000 dòng (rc=$POS_RC): $(grep -E 'FAIL:|Broken pipe' <<<"$POS_OUT" | head -n 3 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 3. Đối chứng âm (negative control): riêng 'backend' trả impeccable + 6000 dòng PHẢI bị bắt lỗi
#    (Bản cũ dính SIGPIPE ở elif nên rơi sang else pass -> thoát 0 giả!)
# ---------------------------------------------------------------------------
mkdir -p "$TMP_DIR/bin-neg"
cat >"$TMP_DIR/bin-neg/python3" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == */profile_skills.py && "\${2:-}" == "backend" ]]; then
  printf 'impeccable\n'
  exec "$REAL_PYTHON3" -c 'import sys; sys.stdout.write("".join(f"skill-pad-{i:04d}\n" for i in range(6000)))'
fi
exec "$REAL_PYTHON3" "\$@"
EOF
chmod +x "$TMP_DIR/bin-neg/python3"

NEG_OUT="$(PATH="$TMP_DIR/bin-neg:$PATH" bash "$TARGET_TEST" 2>&1)"
NEG_RC=$?
if [[ "$NEG_RC" -ne 0 ]] && grep -Fq "KHÔNG ĐƯỢC bao gồm impeccable cho profile 'backend'" <<<"$NEG_OUT"; then
  pass "Đối chứng âm: nhánh elif bắt đúng lỗi khi profile 'backend' trả impeccable + 6000 dòng (không bị SIGPIPE che giấu)"
else
  fail "Đối chứng âm thất bại: SIGPIPE làm nhánh elif rơi sang pass giả khi 'backend' chứa impeccable (rc=$NEG_RC)"
fi

# ---------------------------------------------------------------------------
# 4. Quét tĩnh: không test nào trong universal-agent-devkit/tests/** bật pipefail
#    ở cấp ngoài cùng mà còn dùng pipeline sang grep -q / --quiet / --silent
# ---------------------------------------------------------------------------
cat >"$TMP_DIR/lint_pipefail.py" <<'PY'
import pathlib, re, sys

tests_root = pathlib.Path(sys.argv[1])
pipefail_top = re.compile(r"(?m)^\s*set\b[^\n#]*pipefail")
quoted_str = re.compile(r"'(?:[^']*)'|" + r'"(?:\\.|[^"\\])*"')
bad_pipe = re.compile(
    r"(?<!\|)\|(?!\|)\s*(?:!+\s*)?grep\b[^\n|;]*(?:\s-[A-Za-z]*q[A-Za-z]*\b|\s--quiet\b|\s--silent\b)"
)

offenders = []
for sh in sorted(tests_root.rglob("*.sh")):
    txt = sh.read_text(encoding="utf-8", errors="replace")
    if not pipefail_top.search(txt):
        continue
    top_enabled = False
    depth = 0
    for raw in txt.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if depth == 0 and re.match(r"^set\b[^\n#]*pipefail", s):
            top_enabled = True
            break
        depth += s.count("{") - s.count("}")
    if not top_enabled:
        continue
    for idx, line in enumerate(txt.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        unquoted = quoted_str.sub('""', line)
        unquoted = unquoted.split("#", 1)[0]
        if bad_pipe.search(unquoted):
            offenders.append(f"{sh.relative_to(tests_root.parent)}:{idx}: {line.strip()}")

if offenders:
    print("ERR:" + " | ".join(offenders))
else:
    print("OK")
PY
LINT_OUT="$("$REAL_PYTHON3" "$TMP_DIR/lint_pipefail.py" "$DEVKIT_ROOT/tests")"

if [[ "$LINT_OUT" == "OK" ]]; then
  pass "Quét tĩnh: 0 file test bật pipefail trong universal-agent-devkit/tests/ còn pipeline sang grep quiet"
else
  fail "Quét tĩnh phát hiện mẫu dễ dính SIGPIPE dưới pipefail: ${LINT_OUT#ERR:}"
fi

echo ""
if [[ "$FAILS" -gt 0 ]]; then
  echo "FAILED: $FAILS lỗi ($PASSES kiểm tra đạt)"
  exit 1
fi
echo "ALL $PASSES CHECKS PASSED"
exit 0
