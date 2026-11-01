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
# 4. Quét tĩnh toàn bộ `universal-agent-devkit/tests/**/*.sh` và `hooks/tests/**/*.sh` bật `pipefail`
#    ở cấp ngoài cùng: không còn pipeline sang `grep`/`egrep`/`fgrep` thoát sớm (`-q`, `-l`, `-L`, `-m`).

. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_ROOT="${DEVKIT_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TARGET_TEST="$DEVKIT_ROOT/tests/verification/test_impeccable_skill.sh"
REAL_PYTHON3="$(command -v python3)"
TEST_BASH="/bin/bash"
[[ -x "$TEST_BASH" ]] || TEST_BASH="$(command -v bash)"
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
# 4. Quét tĩnh: không test nào trong universal-agent-devkit/{tests,hooks/tests}/**
#    bật pipefail ở cấp ngoài cùng mà còn dùng pipeline sang grep thoát sớm (-q/-l/-L/-m)
# ---------------------------------------------------------------------------
cat >"$TMP_DIR/lint_pipefail.py" <<'PY'
import pathlib, re, sys

devkit_root = pathlib.Path(sys.argv[1])
scan_roots = [p for p in (devkit_root / "tests", devkit_root / "hooks" / "tests") if p.is_dir()]

heredoc_re = re.compile(r"<<(-?)\s*(?:'([^']+)'|\"([^\"]+)\"|\\?([A-Za-z_][A-Za-z0-9_]*))")
set_pipefail_re = re.compile(
    r"(?:^|[;&|()])\s*set\b[^;#\n|&()]*(?:-[A-Za-z]*o\s+pipefail|--?\s*pipefail)\b"
)
bad_pipe = re.compile(
    r"(?<!\|)\|(?!\|)\s*(?:!+\s*)?"
    r"(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+|(?:command|env)\s+)*)"
    r"(?:grep|egrep|fgrep)\b[^\n|;]*"
    r"(?:\s-[A-Za-z0-9]*[qlLm][A-Za-z0-9]*\b|\s--(?:quiet|silent|max-count|files-with(?:out)?-match(?:es)?)(?:=|\b))"
)


def sanitize_shell_lines(txt: str):
    """Khử nội dung chuỗi đơn/kép (kể cả nhiều dòng), heredoc và comment đúng luật shell (`#` sau khoảng trắng/phân tách)."""
    lines = txt.splitlines()
    out = [""] * len(lines)
    sq = dq = False
    heredoc_end = None
    heredoc_strip_tabs = False
    i = 0
    while i < len(lines):
        raw = lines[i]
        if heredoc_end is not None:
            chk = raw.lstrip("\t") if heredoc_strip_tabs else raw
            if chk == heredoc_end:
                heredoc_end = None
            i += 1
            continue
        buf = []
        j, n = 0, len(raw)
        pending_hd = None
        while j < n:
            ch = raw[j]
            if sq:
                if ch == "'":
                    sq = False
                    buf.append("'")
                else:
                    buf.append(" ")
                j += 1
                continue
            if dq:
                if ch == "\\" and j + 1 < n:
                    buf.append("  ")
                    j += 2
                    continue
                if ch == '"':
                    dq = False
                    buf.append('"')
                else:
                    buf.append(" ")
                j += 1
                continue
            if ch == "\\" and j + 1 < n:
                buf.append(raw[j : j + 2])
                j += 2
                continue
            if ch == "'":
                sq = True
                buf.append("'")
                j += 1
                continue
            if ch == '"':
                dq = True
                buf.append('"')
                j += 1
                continue
            if ch == "#" and (j == 0 or raw[j - 1].isspace() or raw[j - 1] in ";|&()"):
                break
            if ch == "<" and j + 1 < n and raw[j + 1] == "<" and (j + 2 >= n or raw[j + 2] != "<"):
                m = heredoc_re.match(raw, j)
                if m:
                    pending_hd = (m.group(2) or m.group(3) or m.group(4), m.group(1) == "-")
                    buf.append(" " * (m.end() - j))
                    j = m.end()
                    continue
            buf.append(ch)
            j += 1
        out[i] = "".join(buf)
        if pending_hd and not sq and not dq:
            heredoc_end, heredoc_strip_tabs = pending_hd
        i += 1
    return lines, out


def join_continuations(raw_lines, clean_lines):
    """Nối các dòng tiếp nối bằng `\\` cuối dòng hoặc kết thúc bằng toán tử pipe `|`."""
    joined = []
    acc = ""
    start_ln = 1
    for idx, (raw, code) in enumerate(zip(raw_lines, clean_lines), 1):
        if not acc:
            start_ln = idx
        stripped = code.rstrip()
        cont_bs = stripped.endswith("\\") and not stripped.endswith("\\\\")
        cont_pipe = stripped.endswith("|") and not stripped.endswith("||")
        piece = stripped[:-1] if cont_bs else code
        if cont_bs or cont_pipe:
            acc += piece + " "
        else:
            acc += piece
            joined.append((start_ln, acc, raw_lines[start_ln - 1].strip()))
            acc = ""
    if acc:
        joined.append((start_ln, acc, raw_lines[start_ln - 1].strip()))
    return joined


offenders = []
for root in scan_roots:
    for sh in sorted(root.rglob("*.sh")):
        txt = sh.read_text(encoding="utf-8", errors="replace")
        if "pipefail" not in txt:
            continue
        raw_lines, clean_lines = sanitize_shell_lines(txt)
        stmts = join_continuations(raw_lines, clean_lines)
        top_enabled = False
        depth = 0
        for _, code, _ in stmts:
            if depth == 0 and set_pipefail_re.search(code):
                top_enabled = True
                break
            depth += code.count("{") - code.count("}")
        if not top_enabled:
            continue
        for ln_no, code, preview in stmts:
            if bad_pipe.search(code):
                offenders.append(f"{sh.relative_to(devkit_root)}:{ln_no}: {preview}")

if offenders:
    print("ERR:" + " | ".join(offenders))
else:
    print("OK")
PY
LINT_OUT="$("$REAL_PYTHON3" "$TMP_DIR/lint_pipefail.py" "$DEVKIT_ROOT")"

if [[ "$LINT_OUT" == "OK" ]]; then
  pass "Quét tĩnh: 0 file test bật pipefail trong universal-agent-devkit/{tests,hooks/tests}/ còn pipe sang grep thoát sớm (-q/-l/-L/-m)"
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
