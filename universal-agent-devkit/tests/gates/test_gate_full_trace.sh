#!/usr/bin/env bash
# Test hồi quy (#759): lượt gate-full đỏ tự truy vết so với ref xanh gần nhất (last_full_green_sha) và ghi vào summary-latest.md +
# trace-latest.json — trước đây routine đêm của Agent-Factory phải tự dò PR / thẻ gây đỏ.
# Repo giả: base (= last_full_green_sha) → c1 chore → c2 "(#12)" Refs #5 làm tests/test_t.sh đỏ → c3 "(#13)" Closes #6 sửa bin/helper.py (test_t.sh
# nhắc tên nó: nguồn liên quan theo đồ thị của scoped_gate.py) → c4 "(#14)" chỉ sửa README.md (watch_files của REG-W-01).
#   t0. đỏ thật: chia đôi THẬT ra c2 (c1 chạy lại xanh — lệnh của REG-W-01 / REG-U-01 chạy lại xanh, chỉ test_t.sh quyết định);
#   t1. summary có mục truy vết, khoảng base..c4, đủ 3 PR kèm thẻ;
#   t2. trace-latest.json: REG-T-01 — c2 "chắc" (commit nghi vấn của chia đôi + đụng file test) đứng đầu, c3 "nghi" (đụng helper.py), không
#       có c4; REG-W-01 — c4 "nghi" qua watch_files cụ thể (luật "**" / "universal-agent-devkit/**" không tính);
#   t3. red-env (không chia đôi): suite không commit nào đụng tới ⇒ "không rõ";
#   t4. scoped_gate.py hỏng (import lỗi) ⇒ lượt vẫn đỏ, exit 1, vẫn có thẻ, ghi chú "truy vết lỗi";
#   t5. lượt xanh: trace-latest.json result green, tests rỗng; summary không có mục truy vết.
# Gate giả qua DEVKIT_GATE_FULL_CMD, thẻ giả qua DEVKIT_GATE_FULL_CARD_CMD, gh giả. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-trace.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

g init -q --bare "$T/origin.git"
g init -q "$T/seed"
K="$T/seed/universal-agent-devkit"
mkdir -p "$K/tests" "$K/bin"
printf '#!/bin/sh\n# chạy bin/helper.py\necho t >>"$FAKE_RERUNS"\nexit 0\n' >"$K/tests/test_t.sh"
printf 'print("v1")\n' >"$K/bin/helper.py"
printf 'v0\n' >"$T/seed/README.md"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
C0="$(g -C "$T/seed" rev-parse HEAD)"
printf '1\n' >"$T/seed/f1.txt"; g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "🔧 [chore] c1"
C1="$(g -C "$T/seed" rev-parse HEAD)"
sed 's/^exit 0$/exit 1/' "$K/tests/test_t.sh" >"$T/t.sh" && cat "$T/t.sh" >"$K/tests/test_t.sh"
g -C "$T/seed" commit -qam "✨ [feat] test_t đổi hành vi (#12)" -m "Refs #5"
C2="$(g -C "$T/seed" rev-parse HEAD)"
printf 'print("v2")\n' >"$K/bin/helper.py"
g -C "$T/seed" commit -qam "🐛 [fix] helper (#13)" -m "Closes #6"
C3="$(g -C "$T/seed" rev-parse HEAD)"
printf 'v1\n' >"$T/seed/README.md"
g -C "$T/seed" commit -qam "📝 [docs] readme (#14)"
C4="$(g -C "$T/seed" rev-parse HEAD)"
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main:main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
mkdir -p "$COMMON/postfix-gate"
printf '%s\n' "$C0" >"$COMMON/postfix-gate/last_full_green_sha"

cat >"$T/fakegate.py" <<'PY'
import json, os, shlex, sys
rr = shlex.quote(os.environ["FAKE_RERUNS"])
mode = os.environ["FAKE_MODE"]
WD = "      output: BLOCKED: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s)"


def red(sid, cmd=None, fail_lines=("✖ đếm sai: want 0, got 1",), tail=""):
    return {"id": sid, "status": "FAIL", "command": cmd or "echo %s >>%s; exit 1" % (sid, rr), "fail_lines": list(fail_lines),
            "output_tail": tail}


if mode == "green":
    print(json.dumps({"verdict": "PASS", "exit_code": 0, "accepted": True, "regression_tests": []}))
    sys.exit(0)
# REG-W-01 / REG-U-01: đỏ trong gate, chạy lại xanh — chia đôi chỉ theo test_t.sh (đỏ từ c2) nên phải thấy c1 xanh mới ra c2
ok_cmd = "echo %s >>" + rr + "; exit 0"
suites = {"red": [red("REG-T-01", cmd="bash universal-agent-devkit/tests/test_t.sh"), red("REG-W-01", cmd=ok_cmd % "REG-W-01"),
                  red("REG-U-01", cmd=ok_cmd % "REG-U-01")],
          "allb": [red("REG-U-01", fail_lines=["✖ ca W"], tail="✖ ca W\n" + WD)]}[mode]
print(json.dumps({"verdict": "FAIL", "exit_code": 1, "accepted": False, "matrix_path": os.environ["FAKE_MATRIX"],
                  "regression_tests": suites}, ensure_ascii=False))
sys.exit(1)
PY
cat >"$T/matrix.json" <<'JSON'
{"project": "t", "rules": [
  {"component": "all", "watch_files": ["**", "universal-agent-devkit/**"], "mandatory_regression_tests": [{"id": "REG-T-01", "command": "true"}]},
  {"component": "readme", "watch_files": ["README.md"], "mandatory_regression_tests": [{"id": "REG-W-01", "command": "true"}]}]}
JSON
cat >"$T/fakecard.sh" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"$FAKE_CARD_ARGS"
echo "Created https://github.com/fake/repo/issues/99"
SH
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "[]"\n' >"$T/bin/gh"
chmod +x "$T/fakecard.sh" "$T/bin/gh"

export PATH="$T/bin:$PATH" FAKE_RERUNS="$T/reruns" FAKE_CARD_ARGS="$T/card.args" FAKE_MATRIX="$T/matrix.json"
export DEVKIT_GATE_FULL_CMD="python3 $T/fakegate.py" DEVKIT_GATE_FULL_CARD_CMD="sh $T/fakecard.sh"
export DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0
export DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock"   # khoá toàn máy trong thư mục tạm: không chờ / chặn lượt đêm thật
unset DEVKIT_GATE_FULL_BISECT
SUM="$T/logs/summary-latest.md"
TJ="$T/logs/trace-latest.json"

run_gf() {   # run_gf <mode> [gate_full.py]: một lượt, in exit code
  rm -f "$T/reruns" "$T/card.args" "$TJ"
  FAKE_MODE="$1" python3 "${2:-$GF}" run --repo "$T/repo" --timeout 30 >"$T/out.$1" 2>&1
  echo $?
}
tj() {   # tj '<biểu thức python trên d (trace-latest.json), by (id → suite)>'
  python3 - "$TJ" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError) as exc:
    print("trace-latest.json:", exc); sys.exit(1)
by = {t["id"]: t for t in d.get("tests") or []}
ok = bool(eval(sys.argv[2], {"d": d, "by": by}))
if not ok:
    print(json.dumps(d, ensure_ascii=False)[:1500])
sys.exit(0 if ok else 1)
PY
}

# --- t1/t2: đỏ thật, chia đôi ra c2 -------------------------------------------------------------------------------------------
rc=$(run_gf red)
chk "t0. lượt đỏ thật: exit 1, chia đôi thấy c1 xanh rồi ra c2" \
  '[ "$rc" = 1 ] && grep -q "${C1:0:12} xanh" "$T/out.red" && grep -q "Commit nghi vấn: $C2" "$SUM"' "rc=$rc $(tail -6 "$T/out.red")"
chk "t1. summary-latest.md có mục truy vết: khoảng base..c4, PR #12 (thẻ #5), PR #13 (thẻ #6), PR #14" \
  'grep -q "Truy vết" "$SUM" && grep -q "${C0:0:12}\.\.${C4:0:12}" "$SUM" && grep -q "PR #12 (thẻ #5)" "$SUM" && grep -q "PR #13 (thẻ #6)" "$SUM" && grep -q "PR #14" "$SUM"' \
  "$(cat "$SUM" 2>/dev/null)"
chk "t2a. JSON: REG-T-01 đứng đầu là c2 'chắc' (PR 12, thẻ [5])" \
  'tj "by[\"REG-T-01\"][\"candidates\"][0] == dict(by[\"REG-T-01\"][\"candidates\"][0], sha=\"$C2\", pr=12, issues=[5], confidence=\"chắc\")"'
chk "t2b. JSON: REG-T-01 có c3 'nghi' vì đụng bin/helper.py (nguồn test nhắc tên), không có c4 (luật ** không tính)" \
  'tj "any(c[\"sha\"] == \"$C3\" and c[\"confidence\"] == \"nghi\" and \"helper.py\" in c[\"why\"] for c in by[\"REG-T-01\"][\"candidates\"]) and \"$C4\" not in [c.get(\"sha\") for c in by[\"REG-T-01\"][\"candidates\"]]"'
chk "t2c. JSON: REG-W-01 có c4 'nghi' qua watch_files README.md; khoảng có đủ 4 commit, last_green = base" \
  'tj "any(c[\"sha\"] == \"$C4\" and c[\"confidence\"] == \"nghi\" for c in by[\"REG-W-01\"][\"candidates\"]) and [c[\"pr\"] for c in d[\"commits\"]] == [14, 13, 12, None] and d[\"last_green\"] == \"$C0\" and d[\"result\"] == \"red\""'

# --- t3: red-env, không chia đôi ----------------------------------------------------------------------------------------------
rc=$(run_gf allb)
chk "t3. red-env: suite không commit nào đụng tới ⇒ 'không rõ' (JSON + summary)" \
  '[ "$rc" = 3 ] && tj "d[\"result\"] == \"red-env\" and by[\"REG-U-01\"][\"candidates\"][0][\"confidence\"] == \"không rõ\"" && grep -q "REG-U-01: không rõ" "$SUM"' \
  "rc=$rc $(tail -3 "$T/out.allb")"

# --- t4: truy vết hỏng không đổi kết luận ---------------------------------------------------------------------------------------
mkdir -p "$T/bk/bin"
cp "$GF" "$DEVKIT_DIR/bin/capacity.py" "$T/bk/bin/"
printf 'raise RuntimeError("scoped_gate hỏng")\n' >"$T/bk/bin/scoped_gate.py"
rc=$(run_gf red "$T/bk/bin/gate_full.py")
chk "t4. scoped_gate.py hỏng: lượt vẫn đỏ, exit 1, có thẻ, ghi chú truy vết lỗi" \
  '[ "$rc" = 1 ] && grep -q "P1 gate-full đêm" "$T/card.args" && grep -q "truy vết lỗi" "$SUM"' "rc=$rc $(tail -3 "$T/out.red")"

# --- t5: lượt xanh ------------------------------------------------------------------------------------------------------------
rc=$(run_gf green)
chk "t5. lượt xanh: trace-latest.json result green, tests rỗng; summary không có mục truy vết" \
  '[ "$rc" = 0 ] && tj "d[\"result\"] == \"green\" and d[\"tests\"] == [] and d[\"sha\"] == \"$C4\"" && ! grep -q "Truy vết" "$SUM"' "rc=$rc"
chk "z. scratch gỡ, khoá nhả" \
  '! ls -d "$COMMON"/postfix-gate/gate-full-scratch-* >/dev/null 2>&1 && [ ! -e "$COMMON/postfix-gate/gate-full.lock" ]'

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_full_trace: PASS"; exit 0; fi
echo "test_gate_full_trace: $fails FAIL"; exit 1
