#!/usr/bin/env bash
# Kiểm thử hồi quy #780: chặn lỗi SIGPIPE / EPIPE (`printf: write error: Broken pipe`)
# khi dùng pipeline sang `grep` thoát sớm dưới `set -... pipefail` trong bộ test của DevKit:
# 1. Thực thi trực tiếp `test_impeccable_skill.sh` với 2 biến môi trường 80 KB (tổng ~160 KB > pipe buffer
#    64 KiB, mỗi biến < trần `MAX_ARG_STRLEN` 128 KiB của Linux kernel) để kiểm nhánh `ENV_DUMP`.
# 2. Thực thi trực tiếp `test_impeccable_skill.sh` với shim `python3` sinh `PROF_OUT` 6000 dòng (> 80 KiB,
#    `impeccable` đứng đầu) cho các profile UI: bản cũ ĐỎ vì `Broken pipe`, bản mới XANH.
# 3. Đối chứng âm (negative control) cô lập cho nhánh `elif` ở profile `backend`: chỉ riêng `backend` trả
#    `impeccable` + 6000 dòng; bản cũ dính `SIGPIPE` ở `elif` rơi sang `else pass` (thoát 0 giả!),
#    còn bản mới bắt buộc phát hiện và đánh FAIL (`rc != 0`).
# 4. Tự kiểm (self-test) bộ phân tích cú pháp shell rồi quét tĩnh toàn bộ `universal-agent-devkit/tests/**`
#    và `hooks/tests/**` bật `pipefail` ở cấp ngoài cùng: không còn pipeline sang `grep`/`egrep`/`fgrep`
#    thoát sớm (`-q`, `-l`, `-L`, `-m`).

. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_ROOT="${DEVKIT_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TARGET_TEST="$DEVKIT_ROOT/tests/verification/test_impeccable_skill.sh"
REAL_PYTHON3="$(command -v python3 || true)"
if [[ -z "$REAL_PYTHON3" || ! -x "$REAL_PYTHON3" ]]; then
  echo "✖ FAIL: không tìm thấy python3 khả dụng trong PATH" >&2
  exit 1
fi
TEST_BASH="/bin/bash"
[[ -x "$TEST_BASH" ]] || TEST_BASH="$(command -v bash)"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_DIR="$(mktemp -d "${TMP_BASE%/}/test_impeccable_pipefail.XXXXXX")"
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

echo "=== Regression #780: pipefail + grep early-exit SIGPIPE guard ==="

# Mỗi biến đệm 80 KB (< MAX_ARG_STRLEN = 131072 byte/chuỗi env của Linux kernel tránh E2BIG),
# ghép 2 biến tạo ENV_DUMP ~160 KB vượt xa pipe buffer 64 KiB trên cả macOS và Linux.
PAD_80K="$("$REAL_PYTHON3" -c 'print("x" * 80000)')"

# ---------------------------------------------------------------------------
# 1. Kiểm tra nhánh ENV_DUMP (dòng 114–117) với tổng biến môi trường ~160 KB
# ---------------------------------------------------------------------------
ENV_OUT="$(ZZZ_PIPEFAIL_PAD_780_A="$PAD_80K" ZZZ_PIPEFAIL_PAD_780_B="$PAD_80K" "$TEST_BASH" "$TARGET_TEST" 2>&1)"
ENV_RC=$?
if [[ "$ENV_RC" -eq 0 ]] && ! grep -Fq "Broken pipe" <<<"$ENV_OUT"; then
  pass "test_impeccable_skill.sh XANH khi ENV_DUMP ~160 KB dưới pipefail (không bị Broken pipe hay E2BIG)"
else
  ERR_SNIP="$(grep -E -m 3 'FAIL:|Broken pipe|Argument list too long' <<<"$ENV_OUT" || true)"
  fail "test_impeccable_skill.sh ĐỎ với ENV_DUMP ~160 KB (rc=$ENV_RC): ${ERR_SNIP//$'\n'/ }"
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

POS_OUT="$(PATH="$TMP_DIR/bin-pos:$PATH" "$TEST_BASH" "$TARGET_TEST" 2>&1)"
POS_RC=$?
if [[ "$POS_RC" -eq 0 ]] && ! grep -Fq "Broken pipe" <<<"$POS_OUT"; then
  pass "test_impeccable_skill.sh XANH khi PROF_OUT dài 6000 dòng (> 80 KiB, impeccable ở đầu)"
else
  ERR_SNIP="$(grep -E -m 3 'FAIL:|Broken pipe' <<<"$POS_OUT" || true)"
  fail "test_impeccable_skill.sh ĐỎ khi PROF_OUT dài 6000 dòng (rc=$POS_RC): ${ERR_SNIP//$'\n'/ }"
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

NEG_OUT="$(PATH="$TMP_DIR/bin-neg:$PATH" "$TEST_BASH" "$TARGET_TEST" 2>&1)"
NEG_RC=$?
if [[ "$NEG_RC" -ne 0 ]] && grep -Fq "KHÔNG ĐƯỢC bao gồm impeccable cho profile 'backend'" <<<"$NEG_OUT"; then
  pass "Đối chứng âm: nhánh elif bắt đúng lỗi khi profile 'backend' trả impeccable + 6000 dòng (không bị SIGPIPE che giấu)"
else
  fail "Đối chứng âm thất bại: SIGPIPE làm nhánh elif rơi sang pass giả khi 'backend' chứa impeccable (rc=$NEG_RC)"
fi

# ---------------------------------------------------------------------------
# 4. Tự kiểm (self-test) + quét tĩnh toàn bộ universal-agent-devkit/{tests,hooks/tests}/**
# ---------------------------------------------------------------------------
cat >"$TMP_DIR/lint_pipefail.py" <<'PY'
import pathlib, re, sys

heredoc_re = re.compile(r"<<(-?)\s*(?:'([^']*)'|\"([^\"]*)\"|\\?([A-Za-z0-9_.-]+))")
set_pipefail_re = re.compile(
    r"(?:^|[;&|()])\s*set\b[^;#\n|&()]*(?:-[A-Za-z]*o\s+pipefail|--?\s*pipefail)\b"
)
bad_pipe = re.compile(
    r"(?<!\|)\|(?!\|)&?\s*(?:!+\s*)?"
    r"(?:(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S)*\s+|(?:command|env)\s+)*)"
    r"(?:grep|egrep|fgrep)\b[^\n|;&)]*?"
    r"(?:\s-[A-Za-z0-9]*[qlLm][A-Za-z0-9]*\b|\s--(?:quiet|silent|max-count|files-with(?:out)?-match(?:es)?)(?:=|\b))"
)


def sanitize_shell_lines(txt: str):
    """Tách mã thực thi khỏi nội dung chuỗi ('...', $'...', \"...\"), giữ nguyên code trong $(...)/`...` lồng bên trong \"...\",
    bỏ thân heredoc (phân biệt rõ here-string `<<<` với heredoc `<<`), và đánh dấu chính xác dòng có `\\` nối dòng."""
    lines = txt.splitlines()
    out = [""] * len(lines)
    cont_bs = [False] * len(lines)
    # Stack trạng thái: ("code", depth_paren), ("dq", 0), ("sq", 0), ("ansi_sq", 0), ("backtick", 0)
    stack = [["code", 0]]
    active_hds = []

    for i, raw in enumerate(lines):
        if active_hds:
            delim, strip_tabs = active_hds[0]
            chk = raw.lstrip("\t") if strip_tabs else raw
            if chk == delim:
                active_hds.pop(0)
            continue

        buf = []
        pending_hds = []
        j, n = 0, len(raw)
        line_escaped_nl = False

        while j < n:
            mode = stack[-1][0]
            ch = raw[j]

            if mode == "sq":
                if ch == "'":
                    stack.pop()
                    buf.append("'")
                else:
                    buf.append(" ")
                j += 1
                continue

            if mode == "ansi_sq":
                if ch == "\\" and j + 1 < n:
                    buf.append("  ")
                    j += 2
                    continue
                if ch == "'":
                    stack.pop()
                    buf.append("'")
                else:
                    buf.append(" ")
                j += 1
                continue

            if mode == "dq":
                if ch == "\\" and j + 1 == n:
                    line_escaped_nl = True
                    j += 1
                    continue
                if ch == "\\" and j + 1 < n:
                    buf.append("  ")
                    j += 2
                    continue
                if ch == '"':
                    stack.pop()
                    buf.append('"')
                    j += 1
                    continue
                if raw.startswith("$((", j):
                    # Biểu thức số học không chứa pipeline lệnh
                    buf.append("   ")
                    j += 3
                    continue
                if raw.startswith("$(", j):
                    stack.append(["code", 1])
                    buf.append("$(")
                    j += 2
                    continue
                if ch == "`":
                    stack.append(["backtick", 0])
                    buf.append("`")
                    j += 1
                    continue
                buf.append(" ")
                j += 1
                continue

            # mode == "code" hoặc "backtick": mã thực thi thực sự (kể cả bên trong $(...) hoặc `...`)
            if mode == "backtick" and ch == "`":
                stack.pop()
                buf.append("`")
                j += 1
                continue

            if ch == "\\" and j + 1 == n:
                line_escaped_nl = True
                j += 1
                continue
            if ch == "\\" and j + 1 < n:
                buf.append("  ")
                j += 2
                continue
            if raw.startswith("$'", j):
                stack.append(["ansi_sq", 0])
                buf.append("$'")
                j += 2
                continue
            if ch == "'":
                stack.append(["sq", 0])
                buf.append("'")
                j += 1
                continue
            if ch == '"':
                stack.append(["dq", 0])
                buf.append('"')
                j += 1
                continue
            if raw.startswith("$(", j) and not raw.startswith("$((", j):
                stack.append(["code", 1])
                buf.append("$(")
                j += 2
                continue
            if ch == "`":
                stack.append(["backtick", 0])
                buf.append("`")
                j += 1
                continue
            if stack[-1][1] > 0:
                if ch == "(":
                    stack[-1][1] += 1
                elif ch == ")":
                    stack[-1][1] -= 1
                    if stack[-1][1] == 0 and len(stack) > 1:
                        stack.pop()
                        buf.append(")")
                        j += 1
                        continue
            if ch == "#" and (j == 0 or raw[j - 1].isspace() or raw[j - 1] in ";|&()"):
                break
            # Phân biệt rõ here-string `<<<` với heredoc `<<`
            if raw.startswith("<<<", j):
                buf.append("<<<")
                j += 3
                continue
            if ch == "<" and j + 1 < n and raw[j + 1] == "<" and (j == 0 or raw[j - 1] != "<"):
                m = heredoc_re.match(raw, j)
                if m:
                    delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
                    pending_hds.append((delim, m.group(1) == "-"))
                    buf.append(" " * (m.end() - j))
                    j = m.end()
                    continue
            buf.append(ch)
            j += 1

        out[i] = "".join(buf)
        cont_bs[i] = line_escaped_nl
        if pending_hds and not line_escaped_nl:
            active_hds.extend(pending_hds)

    return lines, out, cont_bs, stack, active_hds


def join_continuations(raw_lines, clean_lines, cont_bs):
    """Nối dòng tiếp nối bằng `\\` thật ở cuối dòng hoặc đang treo sau toán tử pipe `|`/`|&` (kể cả qua dòng trống/comment)."""
    joined = []
    acc = ""
    start_ln = 1
    dangling_pipe = False

    for idx, (raw, code, has_bs) in enumerate(zip(raw_lines, clean_lines, cont_bs), 1):
        stripped = code.rstrip()
        if dangling_pipe and not stripped and not has_bs:
            # Dòng trống hoặc chỉ có `# comment` nằm ngay sau `|` -> giữ mạch nối sang dòng lệnh kế tiếp
            continue
        if not acc:
            start_ln = idx
        ends_pipe = (stripped.endswith("|") and not stripped.endswith("||")) or stripped.endswith("|&")
        if has_bs or ends_pipe:
            acc += stripped + " "
            dangling_pipe = ends_pipe and not has_bs
        else:
            acc += code
            joined.append((start_ln, acc, raw_lines[start_ln - 1].strip()))
            acc = ""
            dangling_pipe = False

    if acc:
        joined.append((start_ln, acc, raw_lines[start_ln - 1].strip()))
    return joined


def scan_text(txt: str):
    if "pipefail" not in txt:
        return []
    raw_lines, clean_lines, cont_bs, _, _ = sanitize_shell_lines(txt)
    stmts = join_continuations(raw_lines, clean_lines, cont_bs)
    top_enabled = False
    depth = 0
    for _, code, _ in stmts:
        if depth == 0 and set_pipefail_re.search(code):
            top_enabled = True
            break
        depth += code.count("{") - code.count("}")
    if not top_enabled:
        return []
    hits = []
    for ln_no, code, preview in stmts:
        if bad_pipe.search(code):
            hits.append((ln_no, preview))
    return hits


def run_selftest():
    # 1) Bắt buộc phát hiện lỗi nằm SAU here-string `<<<` (regression P1 vòng 2)
    t_after_herestr = "set -uo pipefail\ngrep -Fqx 'A=1' <<<\"$ENV_DUMP\"\nprintf '%s\\n' \"$X\" | grep -qx 'B=2'\n"
    assert len(scan_text(t_after_herestr)) == 1, f"missed after <<<: {scan_text(t_after_herestr)}"

    # 2) Bắt buộc phát hiện lỗi nằm TRONG `$(...)` bọc ngoặc kép `\"...\"`
    t_in_cmdsub = 'set -euo pipefail\nOUT="$(printf \'%s\\n\' "$BIG" | grep -qx "impeccable")"\n'
    assert len(scan_text(t_in_cmdsub)) == 1, f"missed inside cmdsub: {scan_text(t_in_cmdsub)}"

    # 3) Bắt buộc phát hiện pipeline xuống dòng có `# comment` ở giữa và tham số `${VAR#prefix}`
    t_multiline = "set -uo pipefail\nprintf '%s\\n' ${BIG#prefix} |\n  # comment xen giữa\n  LC_ALL=C grep -m 1 ok\n"
    assert len(scan_text(t_multiline)) == 1, f"missed multiline pipe+comment: {scan_text(t_multiline)}"

    # 4) KHÔNG báo giả khi `grep -q` đọc trực tiếp từ file sau toán tử `&&`
    t_safe_and = 'set -euo pipefail\nprintf "%s\\n" "$X" | grep "ok" && grep -q "needle" some_file.txt\n'
    assert scan_text(t_safe_and) == [], f"false positive across &&: {scan_text(t_safe_and)}"

    # 5) KHÔNG báo giả cho chuỗi nằm trong heredoc `<<'PY'` hoặc chuỗi đơn `'...'`
    t_heredoc = "set -uo pipefail\ncat <<'PY'\nprintf x | grep -q y\nPY\necho 'printf x | grep -q y'\n"
    assert scan_text(t_heredoc) == [], f"false positive in heredoc/sq: {scan_text(t_heredoc)}"


run_selftest()

devkit_root = pathlib.Path(sys.argv[1])
scan_roots = [p for p in (devkit_root / "tests", devkit_root / "hooks" / "tests") if p.is_dir()]
offenders = []
for root in scan_roots:
    for sh in sorted(root.rglob("*.sh")):
        txt = sh.read_text(encoding="utf-8", errors="replace")
        for ln_no, preview in scan_text(txt):
            offenders.append(f"{sh.relative_to(devkit_root)}:{ln_no}: {preview}")

if offenders:
    print("ERR:" + " | ".join(offenders))
else:
    print("OK")
PY
LINT_OUT="$("$REAL_PYTHON3" "$TMP_DIR/lint_pipefail.py" "$DEVKIT_ROOT" 2>&1)"
LINT_RC=$?

if [[ "$LINT_RC" -ne 0 ]]; then
  fail "lint_pipefail.py gặp lỗi thực thi/self-test (rc=$LINT_RC): ${LINT_OUT//$'\n'/ }"
elif [[ "$LINT_OUT" == "OK" ]]; then
  pass "Self-test + quét tĩnh: 0 file test bật pipefail trong universal-agent-devkit/{tests,hooks/tests}/ còn pipe sang grep thoát sớm"
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
