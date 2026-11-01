#!/usr/bin/env bash
# Test hồi quy (#749, #748): ca biên của bộ phân loại nhóm b (red-env) trong bin/gate_full.py, sau #700.
# #749 — mỗi ca dưới đây trước sửa bị tính nhóm b (bỏ chia đôi một lỗi thật); ca đối chứng "…ok" vẫn phải là nhóm b:
#   e1. run_impacted: một file có '✖ ca A' + watchdog và dòng '    FAIL ca B: want 0 got 1' trần cùng thụt lề (thành chi tiết của
#       khối cha, khối cha có con nên bị loại khỏi lá) ⇒ red, chia đôi; e1ok: dòng FAIL trần mang dấu hiệu ⇒ vẫn red-env;
#   e2. log = lần đầu '✖ ca A' đỏ thật + mốc chạy lại của post-fix-gate + lần lại '✖ ca A' dính watchdog (khoá khối trùng, gộp OR)
#       ⇒ red; e2ok: cả hai lần đều dính watchdog ⇒ red-env;
#   e3. log bằng chứng > 1 MB bị cắt đầu ('… (đầu log bị cắt, giữ 1 MB cuối)'), phần còn chỉ có ca watchdog ⇒ red; e3ok: cùng log
#       không bị cắt ⇒ red-env;
#   e4. không khối nào, dòng tổng kết ENV-BLOCKED + Traceback ⇒ red;
#   e5. khối LÁ (file không in ca ✖ con): dòng 'Killed: 9' của helper bị giết + dòng 'FAIL ca B: want 0 got 1' trần ⇒ red (review r20).
# #748 — DEVKIT_GATE_FULL_BISECT=1 (ép chia đôi) khi mọi suite là nhóm b:
#   b1. chia đôi ra commit nghi vấn (đỉnh đỏ, commit cũ xanh: tái hiện được) ⇒ result red, exit 1, thẻ High;
#   b2. chia đôi không ra commit ⇒ result red-env, thẻ không ghi "không chia đôi" (đã chia đôi);
#   b3. đối chứng: auto + mọi suite nhóm b ⇒ không chia đôi, thẻ vẫn ghi lý do "không chia đôi";
#   b4. có last_full_green_sha, mọi commit chạy lại đều đỏ (môi trường): chia đôi trả commit đầu sau mốc xanh mà không thấy commit nào
#       xanh ở lượt này ⇒ vẫn red-env, exit 3, thẻ không High (review r20: không đổ oan như #700).
# Gate giả qua DEVKIT_GATE_FULL_CMD; mỗi lần chạy lại một lệnh đỏ ghi một dòng vào $FAKE_RERUNS. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-red-env-edges.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# repo giả: base + c1..c3 (f1..f3.txt) trên first-parent; kit có tests/a.sh cho ca run_impacted.sh
g init -q --bare "$T/origin.git"
g init -q "$T/seed"
mkdir -p "$T/seed/universal-agent-devkit/tests"
printf '#!/bin/sh\necho a >>"$FAKE_RERUNS"\nexit 1\n' >"$T/seed/universal-agent-devkit/tests/a.sh"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
for i in 1 2 3; do printf '%s\n' "$i" >"$T/seed/f$i.txt"; g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "c$i"; done
C2="$(g -C "$T/seed" rev-parse HEAD~1)"
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main:main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
HIST="$COMMON/postfix-gate/nightly/history.jsonl"

cat >"$T/fakegate.py" <<'PY'
import json, os, shlex, sys
rr = shlex.quote(os.environ["FAKE_RERUNS"])
mode = os.environ["FAKE_MODE"]
WD = ("      output: BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn để an toàn. "
      "Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file.")
MARK = "\n# --- chạy lại 1 lần (FLAKY_RETRY) — exit 1 ---\n"
ALL = "bash universal-agent-devkit/tests/run_impacted.sh --all"


def red(sid, fail_lines=(), tail="", cmd=None, log=None):
    t = {"id": sid, "status": "FAIL", "command": cmd or "echo %s >>%s; exit 1" % (sid, rr),
         "fail_lines": list(fail_lines), "output_tail": tail}
    if log is not None:   # như post-fix-gate: toàn văn output ở .agents/evidence/<id>/<giờ>.log (tương đối scratch = cwd)
        t["log"] = ".agents/evidence/%s/20261101-000000.log" % sid
        os.makedirs(os.path.dirname(t["log"]), exist_ok=True)
        with open(t["log"], "w", encoding="utf-8") as f:
            f.write("# test: %s\n# status: FAIL\n\n%s\n" % (sid, log))
    return t


def kit(tail):
    return {"id": "REG-ALL-01", "status": "FAIL", "command": ALL, "fail_lines": [], "output_tail": tail}


first_real = "✖ ca A\n    đếm sai: want 0, got 1"
first_wd = "✖ ca A\n" + WD
only_wd = "✖ ca A\n" + WD + "\nfailures: 1"
# lambda: red(..., log=…) ghi file log khi dựng — chỉ dựng mode được chọn (e2/e2ok, e3/e3ok cùng đường dẫn log)
suites = {
    "e1": lambda: [kit("✖ tests/a.sh\n    ✖ ca A — rc=2\n" + WD + "\n    FAIL ca B: want 0 got 1\nfailures: 2")],
    "e1ok": lambda: [kit("✖ tests/a.sh\n    ✖ ca A — rc=2\n" + WD + "\n    FAIL ca B: killed after 900s (deadline)\nfailures: 2")],
    "e2": lambda: [red("REG-RETRY-01", tail=first_wd, log=first_real + MARK + first_wd)],
    "e2ok": lambda: [red("REG-RETRY-01", tail=first_wd, log=first_wd + MARK + first_wd)],
    "e3": lambda: [red("REG-TRUNC-01", tail=only_wd, log="… (đầu log bị cắt, giữ 1 MB cuối)\n" + only_wd)],
    "e3ok": lambda: [red("REG-TRUNC-01", tail=only_wd, log=only_wd)],
    "e4": lambda: [red("REG-TB-01", tail='Traceback (most recent call last):\n  File "x.py", line 3, in <module>\nValueError: hỏng\n'
               "contract points: 690 ok, 2 env-blocked (no verdict)\nENV-BLOCKED: hook watchdog fired under load, no verdict")],
    "e5": lambda: [kit("✖ tests/a.sh\n    tests/a.sh: line 40: 1234 Killed: 9   sleep 100\n    FAIL ca B: want 0 got 1\nfailures: 1")],
    # b1: lệnh chỉ đỏ từ c2 (có f2.txt) — đỉnh đỏ, base/c1 xanh ⇒ chia đôi ra c2
    "b1": lambda: [red("REG-B-SUS-01", fail_lines=["✖ ca W"], tail="✖ ca W\n" + WD, cmd="echo REG-B-SUS-01 >>%s; test ! -f f2.txt" % rr)],
    "b2": lambda: [red("REG-B-ALL-01", fail_lines=["✖ ca W"], tail="✖ ca W\n" + WD)],
}[mode]()
print(json.dumps({"verdict": "FAIL", "exit_code": 1, "accepted": False, "regression_tests": suites}, ensure_ascii=False))
sys.exit(1)
PY
cat >"$T/fakecard.sh" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"$FAKE_CARD_ARGS"
echo "Created https://github.com/fake/repo/issues/99"
SH
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "[]"\n' >"$T/bin/gh"
chmod +x "$T/fakecard.sh" "$T/bin/gh"

export PATH="$T/bin:$PATH" FAKE_RERUNS="$T/reruns" FAKE_CARD_ARGS="$T/card.args"
export DEVKIT_GATE_FULL_CMD="python3 $T/fakegate.py" DEVKIT_GATE_FULL_CARD_CMD="sh $T/fakecard.sh"
export DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0
export DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock"   # khoá toàn máy trong thư mục tạm: không chờ / chặn lượt đêm thật
unset DEVKIT_GATE_FULL_BISECT

run_gf() {   # run_gf <mode> [VAR=giá trị…]: một lượt gate_full.py, in exit code; xoá dấu vết lượt trước (reruns, thẻ)
  local mode="$1"; shift
  rm -f "$T/reruns" "$T/card.args"
  env "$@" FAKE_MODE="$mode" python3 "$GF" run --repo "$T/repo" --timeout 30 >"$T/out.$mode" 2>&1
  echo $?
}
reruns() { if [ -f "$T/reruns" ]; then wc -l <"$T/reruns" | tr -d ' '; else echo 0; fi; }
hist() {   # hist '<biểu thức python trên row>': kiểm dòng cuối của history.jsonl
  python3 - "$HIST" "$1" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
row = rows[-1] if rows else {}
ok = bool(rows) and bool(eval(sys.argv[2], {"row": row}))
if not ok:
    print("row=", row)
sys.exit(0 if ok else 1)
PY
}
red_bisect() {   # red_bisect <mode> <rc>: result red, exit 1, có chạy lại để chia đôi
  [ "$2" = 1 ] && [ "$(reruns)" -gt 1 ] && hist "row['result'] == 'red'"
}
red_env() {      # red_env <rc>: result red-env, exit 3, không chạy lại lệnh đỏ nào
  [ "$1" = 3 ] && [ "$(reruns)" = 0 ] && hist "row['result'] == 'red-env'"
}

# --- #749 -----------------------------------------------------------------------------------------------------------------
rc=$(run_gf e1)
chk "e1. run_impacted: '✖ ca A' + watchdog và 'FAIL ca B: want 0 got 1' trần trong cùng file ⇒ red, chia đôi" \
  'red_bisect e1 "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e1ok)
chk "e1ok. dòng FAIL trần mang dấu hiệu nhóm b ⇒ vẫn red-env" 'red_env "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e2)
chk "e2. lần đầu '✖ ca A' đỏ thật + lần chạy lại '✖ ca A' dính watchdog ⇒ red, chia đôi" \
  'red_bisect e2 "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e2ok)
chk "e2ok. cả lần đầu lẫn lần chạy lại đều dính watchdog ⇒ red-env" 'red_env "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e3)
chk "e3. log bằng chứng bị cắt đầu, phần còn chỉ có ca watchdog ⇒ red, chia đôi" \
  'red_bisect e3 "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e3ok)
chk "e3ok. cùng log không bị cắt ⇒ red-env" 'red_env "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e4)
chk "e4. không khối, dòng tổng kết ENV-BLOCKED + Traceback ⇒ red, chia đôi" \
  'red_bisect e4 "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf e5)
chk "e5. khối lá: 'Killed: 9' của helper + 'FAIL ca B: want 0 got 1' trần ⇒ red, chia đôi" \
  'red_bisect e5 "$rc"' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"

# --- #748 -----------------------------------------------------------------------------------------------------------------
rc=$(run_gf b1 DEVKIT_GATE_FULL_BISECT=1)
chk "b1. BISECT=1, mọi suite nhóm b, chia đôi ra commit nghi vấn c2 ⇒ result red, exit 1, thẻ High" \
  '[ "$rc" = 1 ] && hist "row[\"result\"] == \"red\" and row[\"suspect\"] == \"$C2\"" && grep -q "High" "$T/card.args"' \
  "rc=$rc $(tail -1 "$HIST") | $(grep -i risk -A1 "$T/card.args" 2>/dev/null | tr '\n' ' ')"
rc=$(run_gf b2 DEVKIT_GATE_FULL_BISECT=1)
chk "b2. BISECT=1, mọi suite nhóm b, chia đôi không ra commit ⇒ red-env, thẻ không ghi 'không chia đôi'" \
  '[ "$rc" = 3 ] && [ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red-env\" and row[\"suspect\"] == \"\"" && ! grep -q "không chia đôi" "$T/card.args"' \
  "rc=$rc reruns=$(reruns) $(grep -o '[^.]*không chia đôi[^.]*' "$T/card.args" 2>/dev/null | head -2 | tr '\n' ' ')"
rc=$(run_gf b2)
chk "b3. auto, mọi suite nhóm b ⇒ không chia đôi, red-env, thẻ vẫn ghi lý do 'không chia đôi'" \
  'red_env "$rc" && grep -q "không chia đôi" "$T/card.args"' "rc=$rc reruns=$(reruns)"
C1="$(g -C "$T/seed" rev-parse HEAD~2)"
LG="$COMMON/postfix-gate/last_full_green_sha"
printf '%s\n' "$C1" >"$LG"
rc=$(run_gf b2 DEVKIT_GATE_FULL_BISECT=1)
mv "$LG" "$T/last_green.b4"   # các ca khác chạy không có mốc xanh
chk "b4. BISECT=1 + last_green, mọi commit chạy lại đều đỏ ⇒ vẫn red-env, exit 3, thẻ không High" \
  '[ "$rc" = 3 ] && [ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red-env\"" && ! grep -q "High" "$T/card.args"' \
  "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
chk "z. scratch gỡ, khoá nhả" \
  '! ls -d "$COMMON"/postfix-gate/gate-full-scratch-* >/dev/null 2>&1 && [ ! -e "$COMMON/postfix-gate/gate-full.lock" ]'

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_full_red_env_edges: PASS"; exit 0; fi
echo "test_gate_full_red_env_edges: $fails FAIL"; exit 1
