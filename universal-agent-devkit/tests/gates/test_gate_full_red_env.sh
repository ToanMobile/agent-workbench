#!/usr/bin/env bash
# Test hồi quy (#700): gate-full không chia đôi khi MỌI suite đỏ đều nhóm b (thời gian thực / môi trường) — chạy lại ở các commit cũ
# cũng đỏ y như vậy nên chia đôi chỉ tốn hàng giờ máy rồi đổ oan cho commit cũ nhất; lượt 13:04 30/10 phải SIGTERM tay để dừng.
#   1. 3 suite đỏ đều có dấu hiệu nhóm b (watchdog hook, killed after …s (deadline), nhãn "timing": true trong ma trận) ⇒ không chạy lại
#      lệnh nào, history result red-env (exit 3), có thẻ, không ghi last_full_green_sha;
#   2. 1 suite đỏ thật + 1 nhóm b ⇒ vẫn chia đôi như cũ (result red, exit 1);
#   3. DEVKIT_GATE_FULL_BISECT=0 ⇒ không chia đôi cả khi suite đỏ thật, vẫn có thẻ; =1 ⇒ ép chia đôi cả khi mọi suite là nhóm b;
#   4. dấu hiệu nằm trong dòng ĐẠT (✔/ok … killed after …) của một khối hỏng không tính: suite vẫn là đỏ thật;
#   5. chạy lại ở đỉnh xanh (khác lần đầu) ⇒ red-env;
#   6. suite chạy run_impacted.sh: xét từng khối LÁ (`✖ tests/…` và các ca ✖ lồng trong nó) — một ca đỏ thật, kể cả nằm cùng file với
#      ca có dấu hiệu, ⇒ chia đôi; mọi ca có dấu hiệu ⇒ red-env; đuôi output cắt dở không dính vào khối cuối của fail_lines; chữ
#      TIMEOUT trong chi tiết không phải dấu hiệu;
#   7. agent-kit test THẬT của lượt (kit giả, không DEVKIT_GATE_FULL_CMD) đỏ chỉ vì hook contract ENV-BLOCKED (dạng sau #714: dòng
#      ENV-BLOCKED + tổng kết "ENV-BLOCKED: hook watchdog fired under load, no verdict"; lượt 00:00 30/10 chia đôi 5 giờ 27 phút) ⇒
#      red-env, agent-kit test chỉ chạy một lần; thêm một ca lệch thật (✗) ⇒ chia đôi như cũ;
#   8. suite đỏ không có lệnh chạy lại (ma trận thiếu command) ⇒ vẫn red, exit 1 (không thành red-env vì "chạy lại xanh" rỗng);
#   9. fail_lines (8 dòng đầu khớp FAIL) + đuôi 2000 ký tự chỉ thấy ca watchdog, ca đỏ thật nằm giữa log: phân loại đọc toàn văn log bằng
#      chứng của suite (t["log"] trong scratch) ⇒ red, chia đôi.
# Gate giả qua DEVKIT_GATE_FULL_CMD, mỗi lần chạy lại một lệnh đỏ ghi một dòng vào $FAKE_RERUNS (rỗng = không chạy lại, không chia đôi).
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-red-env.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# repo giả: 4 commit first-parent (đủ để chia đôi có việc làm); kit có tests/a.sh, tests/b.sh cho ca run_impacted.sh, và
# bin/post-fix-gate.py (xanh) + bin/agent-kit giả cho ca 7 (không install.sh: gate_full.py vào thẳng bước gate + agent-kit test)
g init -q --bare "$T/origin.git"
g init -q "$T/seed"
mkdir -p "$T/seed/universal-agent-devkit/tests" "$T/seed/universal-agent-devkit/bin"
for n in a b; do
  printf '#!/bin/sh\necho %s >>"$FAKE_RERUNS"\nexit 1\n' "$n" >"$T/seed/universal-agent-devkit/tests/$n.sh"
done
printf '%s\n' 'import json' 'print(json.dumps({"verdict": "PASS", "exit_code": 0, "accepted": True, "regression_tests": []}))' \
  >"$T/seed/universal-agent-devkit/bin/post-fix-gate.py"
cat >"$T/seed/universal-agent-devkit/bin/agent-kit" <<'SH'
#!/usr/bin/env bash
# agent-kit test giả: hook contract (tests/lib/case_runner.sh sau #714) có 2 ca watchdog dưới tải ⇒ ENV-BLOCKED, tổng kết hc_summary;
# FAKE_KIT_MODE=real thêm một ca lệch thật ⇒ nhánh FAIL của hc_summary (không có dòng tổng kết ENV-BLOCKED)
echo kit >>"$FAKE_RERUNS"
echo "  ok   a Read matching no glob exits 0                exit=0"
echo "  ENV-BLOCKED  solo: push HEAD:main from main allowed     load 31.20 > hold 24, CPU hook 12 ms"
echo "  ENV-BLOCKED  hw-gate[0]: rm -rf build                   load 31.20 > hold 24, CPU hook 9 ms"
echo "─────────────────────────────────────────────"
if [ "${FAKE_KIT_MODE:-}" = real ]; then
  echo "contract points: 689 ok, 1 deviating, 2 env-blocked"
  echo
  echo "  ✗ no-session key (a / a / a)"
  echo
  echo "A deviation means the hook and its documented contract disagree."
else
  echo "contract points: 690 ok, 2 env-blocked (no verdict)"
  echo "ENV-BLOCKED: hook watchdog fired under load, no verdict"
fi
exit 1
SH
chmod +x "$T/seed/universal-agent-devkit/bin/agent-kit"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
for i in 1 2 3; do printf '%s\n' "$i" >"$T/seed/f$i.txt"; g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "c$i"; done
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main:main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
HIST="$COMMON/postfix-gate/nightly/history.jsonl"

# gate giả: in JSON một dòng như post-fix-gate --json; lệnh của suite đỏ ghi một dòng vào $FAKE_RERUNS khi bị chạy lại
cat >"$T/fakegate.py" <<'PY'
import json, os, shlex, sys
rr = shlex.quote(os.environ["FAKE_RERUNS"])
mode = os.environ["FAKE_MODE"]
WD = ("      output: BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn để an toàn. "
      "Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file.")


def red(sid, fail_lines=(), tail="", code=1):
    return {"id": sid, "status": "FAIL", "command": "echo %s >>%s; exit %d" % (sid, rr, code),
            "fail_lines": list(fail_lines), "output_tail": tail}


# fail_lines như lượt 13:04 30/10: dòng FAIL trần của danh sách chạy + dòng ✗ trùng không kèm chi tiết; chi tiết nằm ở đuôi output
wd = red("REG-B-WD-01", fail_lines=["  FAIL plain push allowed by design                   want=0 got=2", "  ✗ plain push allowed by design"],
         tail="contract points: 691 ok, 1 deviating\n\n  ✗ plain push allowed by design\n      hook=block-dangerous-git.sh want exit=0, got=2\n" + WD)
kill = red("REG-B-KILL-01", fail_lines=["✖ tests/slow.sh", "    killed after 1800s (deadline)"])
timing = red("REG-B-TIMING-01", fail_lines=["✖ PM bi SIGTERM trong luc cho init (9762ms)", "  AssertionError: agy gia phai da duoc spawn"])
real = red("REG-REAL-01", fail_lines=["✖ đếm sai: want 2, got 3"])
passname = red("REG-PASSNAME-01", tail="✖ ca X\n    ✔ con killed after 5s (deadline) ⇒ chưa kết luận\n    ok   killed after 5s (deadline) là nhóm b\n    ✅ cháu killed after 5s (deadline)\n"
                                         "    đếm sai: want 1, got 2\nkilled after 5s (deadline) — dòng ở cột 0 sau khối, không thuộc khối")
flaky = red("REG-FLAKY-01", fail_lines=["✖ đếm sai: want 1, got 2"], code=0)
ALL = "bash universal-agent-devkit/tests/run_impacted.sh --all"
kit_mixed = {"id": "REG-ALL-01", "status": "FAIL", "command": ALL, "fail_lines": [],
             "output_tail": "✔ tests/c.sh\n✖ tests/a.sh\n    ✖ ca A — rc=2\n" + WD + "\n✖ tests/b.sh\n    ✖ ca B: want 0, got 1\nfailures: 2"}
kit_allb = {"id": "REG-ALL-01", "status": "FAIL", "command": ALL, "fail_lines": [],
            "output_tail": "✖ tests/a.sh\n    ✖ ca A — rc=2\n" + WD + "\n✖ tests/b.sh\n    ✖ ca B\n      killed after 900s (deadline)\nfailures: 2"}
# cùng một file: ca A dính watchdog, ca B đỏ thật (kèm chữ TIMEOUT của một gate lồng, không phải dấu hiệu)
nested = {"id": "REG-ALL-01", "status": "FAIL", "command": ALL, "fail_lines": [],
          "output_tail": "✖ tests/a.sh\n    ✖ ca A — rc=2\n" + WD + "\n    ✖ ca B: want 0, got 1\n      REG-X TIMEOUT 2s\nfailures: 2"}
# output_tail = out[-2000:] mở đầu bằng mẩu cắt dở của a.sh: không được dính vào khối cuối (b.sh) của fail_lines
cut = {"id": "REG-ALL-01", "status": "FAIL", "command": ALL,
       "fail_lines": ["✖ tests/a.sh", "    ✖ ca A: killed after 900s (deadline)", "✖ tests/b.sh", "    ✖ ca B: want 0, got 1"],
       "output_tail": "      killed after 900s (deadline)\n✖ tests/a.sh\n    ✖ ca A: killed after 900s (deadline)\n✖ tests/b.sh\n"
                      "    ✖ ca B: want 0, got 1\nfailures: 2"}
nocmd = {"id": "REG-NOCMD-01", "status": "FAIL", "command": "", "fail_lines": ["✖ đếm sai: want 1, got 2"], "output_tail": ""}
# post-fix-gate ghi toàn văn output vào .agents/evidence/<id>/<giờ>.log (đường dẫn tương đối scratch, cwd của gate giả = scratch)
hidden = red("REG-HIDDEN-01", fail_lines=["✔ ca %d: FAIL-safe vẫn đạt" % i for i in range(8)],
             tail="contract points: 690 ok, 1 deviating\n\n  ✗ plain push allowed by design\n" + WD)
if mode == "hidden":
    hidden["log"] = ".agents/evidence/REG-HIDDEN-01/20261031-000000.log"
    os.makedirs(os.path.dirname(hidden["log"]), exist_ok=True)
    with open(hidden["log"], "w", encoding="utf-8") as f:
        f.write("# test: REG-HIDDEN-01\n# status: FAIL\n\n" + "\n".join(hidden["fail_lines"]) + "\n✖ ca thật: want 1, got 2\n"
                + "\n".join("  ok   ca đệm %d" % i for i in range(200)) + "\n" + hidden["output_tail"] + "\n")
suites = {"allb": [wd, kill, timing], "mixed": [real, wd], "real": [real], "passname": [passname], "flaky": [flaky],
          "kitmixed": [kit_mixed], "kitallb": [kit_allb], "nested": [nested], "cut": [cut], "nocmd": [nocmd], "hidden": [hidden]}[mode]
print(json.dumps({"verdict": "FAIL", "exit_code": 1, "accepted": False, "matrix_path": os.environ["FAKE_MATRIX"],
                  "regression_tests": suites}, ensure_ascii=False))
sys.exit(1)
PY
cat >"$T/matrix.json" <<'JSON'
{"project": "t", "rules": [{"component": "pm", "watch_files": ["**"], "mandatory_regression_tests": [
  {"id": "REG-B-TIMING-01", "name": "pm", "command": "true", "timing": true},
  {"id": "REG-REAL-01", "name": "real", "command": "true"}]}]}
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
unset DEVKIT_GATE_FULL_BISECT

# run_gf <mode> [-u VAR] [VAR=giá trị…]: một lượt gate_full.py; in exit code. Xoá dấu vết lượt trước (reruns, thẻ).
run_gf() {
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
no_scratch() {
  ! ls -d "$COMMON"/postfix-gate/gate-full-scratch-* >/dev/null 2>&1 && [ ! -e "$COMMON/postfix-gate/gate-full.lock" ]
}

# --- 1. mọi suite đỏ đều nhóm b ⇒ red-env, không chia đôi -------------------------------------------------------------------
rc=$(run_gf allb)
chk "1a. 3 suite nhóm b: không chạy lại lệnh đỏ nào (không chia đôi)" '[ "$(reruns)" = 0 ]' "reruns=$(reruns) $(tail -5 "$T/out.allb")"
chk "1b. history result red-env, đủ 3 suite trong red và group_b" \
  'hist "row[\"result\"] == \"red-env\" and len(row[\"red\"]) == 3 and sorted(row.get(\"group_b\") or []) == sorted(row[\"red\"]) and row[\"suspect\"] == \"\""' \
  "$(tail -1 "$HIST" 2>/dev/null)"
chk "1c. exit 3 (chưa quy được lỗi cho commit nào), không ghi last_full_green_sha" \
  '[ "$rc" = 3 ] && [ ! -e "$COMMON/postfix-gate/last_full_green_sha" ]' "rc=$rc"
chk "1d. vẫn có thẻ, risk không phải High main đỏ, summary ghi nhóm b" \
  'grep -q "P1 gate-full đêm" "$T/card.args" 2>/dev/null && ! grep -q "High" "$T/card.args" && grep -q "nhóm b" "$T/logs/summary-latest.md"' \
  "$(tr '\n' ' ' <"$T/card.args" 2>/dev/null) | $(tr '\n' ' ' <"$T/logs/summary-latest.md" 2>/dev/null)"
chk "1e. scratch gỡ, khoá nhả" 'no_scratch'

# --- 2. 1 đỏ thật + 1 nhóm b ⇒ chia đôi như cũ ------------------------------------------------------------------------------
rc=$(run_gf mixed)
chk "2a. đỏ thật + nhóm b: vẫn chạy lại / chia đôi" '[ "$(reruns)" -gt 1 ] && grep -q "chia đôi" "$T/out.mixed"' "reruns=$(reruns) $(tail -5 "$T/out.mixed")"
chk "2b. result red, exit 1, thẻ risk High" 'hist "row[\"result\"] == \"red\"" && [ "$rc" = 1 ] && grep -q "High" "$T/card.args"' "rc=$rc"

# --- 3. DEVKIT_GATE_FULL_BISECT ---------------------------------------------------------------------------------------------
rc=$(run_gf real DEVKIT_GATE_FULL_BISECT=0)
chk "3a. BISECT=0 + suite đỏ thật: không chạy lại, result red, exit 1, vẫn có thẻ" \
  '[ "$(reruns)" = 0 ] && hist "row[\"result\"] == \"red\"" && [ "$rc" = 1 ] && grep -q "P1 gate-full đêm" "$T/card.args"' \
  "rc=$rc reruns=$(reruns) $(tail -3 "$T/out.real")"
chk "3b. BISECT=0: summary ghi lý do không chia đôi" 'grep -q "DEVKIT_GATE_FULL_BISECT=0" "$T/logs/summary-latest.md"'
rc=$(run_gf mixed DEVKIT_GATE_FULL_BISECT=0)
chk "3c. BISECT=0 + đỏ thật lẫn nhóm b: không chạy lại" '[ "$(reruns)" = 0 ] && [ "$rc" = 1 ]' "rc=$rc reruns=$(reruns)"
rc=$(run_gf allb DEVKIT_GATE_FULL_BISECT=1)
chk "3d. BISECT=1 ép chia đôi cả khi mọi suite là nhóm b; result vẫn red-env" \
  '[ "$(reruns)" -gt 1 ] && grep -q "chia đôi" "$T/out.allb" && hist "row[\"result\"] == \"red-env\""' "rc=$rc reruns=$(reruns)"
rc=$(run_gf real DEVKIT_GATE_FULL_BISECT=yes)
chk "3e. BISECT giá trị lạ ⇒ auto (đỏ thật vẫn chia đôi), có ghi chú" \
  '[ "$(reruns)" -gt 1 ] && grep -q "DEVKIT_GATE_FULL_BISECT=yes" "$T/logs/summary-latest.md"' "rc=$rc reruns=$(reruns)"

# --- 4. dấu hiệu trong dòng ĐẠT không tính ------------------------------------------------------------------------------------
rc=$(run_gf passname)
chk "4. dòng đạt (✔/ok … killed after) trong khối hỏng và dòng cột 0 sau khối không tính: suite vẫn đỏ thật, chia đôi, result red" \
  '[ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")"' "rc=$rc reruns=$(reruns)"

# --- 5. chạy lại ở đỉnh xanh ⇒ red-env ------------------------------------------------------------------------------------------
rc=$(run_gf flaky)
chk "5. đỉnh chạy lại xanh (khác lần đầu): một lần chạy lại, result red-env, exit 3" \
  '[ "$(reruns)" = 1 ] && hist "row[\"result\"] == \"red-env\" and row.get(\"group_b\") == [\"REG-FLAKY-01\"]" && [ "$rc" = 3 ]' \
  "rc=$rc reruns=$(reruns) $(tail -1 "$HIST" 2>/dev/null)"

# --- 6. run_impacted.sh: từng đoạn ✖ tests/… ----------------------------------------------------------------------------------
rc=$(run_gf kitmixed)
chk "6a. run_impacted: tests/a.sh nhóm b + tests/b.sh đỏ thật ⇒ chia đôi, result red" \
  '[ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red\""' "rc=$rc reruns=$(reruns) $(tail -3 "$T/out.kitmixed")"
rc=$(run_gf kitallb)
chk "6b. run_impacted: mọi bài đỏ có dấu hiệu nhóm b ⇒ không chạy lại, result red-env" \
  '[ "$(reruns)" = 0 ] && hist "row[\"result\"] == \"red-env\"" && [ "$rc" = 3 ]' "rc=$rc reruns=$(reruns) $(tail -3 "$T/out.kitallb")"

rc=$(run_gf nested)
chk "6c. cùng một file: ca watchdog + ca đỏ thật (chi tiết có chữ TIMEOUT) ⇒ chia đôi, result red" \
  '[ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")" && [ "$rc" = 1 ]' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"
rc=$(run_gf cut)
chk "6d. đuôi output cắt dở không dính vào khối cuối của fail_lines ⇒ b.sh vẫn đỏ thật, result red" \
  '[ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")" && [ "$rc" = 1 ]' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"

# --- 7. agent-kit test thật của lượt (không DEVKIT_GATE_FULL_CMD) -----------------------------------------------------------------
rc=$(run_gf kit -u DEVKIT_GATE_FULL_CMD)
chk "7a. agent-kit test đỏ chỉ vì hook contract ENV-BLOCKED (dạng sau #714): chạy một lần, không chia đôi, result red-env, exit 3" \
  '[ "$(reruns)" = 1 ] && hist "row[\"result\"] == \"red-env\" and row[\"red\"] == [\"agent-kit test\"] and row.get(\"group_b\") == [\"agent-kit test\"]" && [ "$rc" = 3 ]' \
  "rc=$rc reruns=$(reruns) $(tail -4 "$T/out.kit")"
rc=$(run_gf kit -u DEVKIT_GATE_FULL_CMD FAKE_KIT_MODE=real)
chk "7b. thêm một ca lệch thật (✗, không dòng tổng kết ENV-BLOCKED): chạy lại + chia đôi, result red, exit 1" \
  '[ "$(reruns)" -gt 2 ] && grep -q "chia đôi" "$T/out.kit" && hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")" && [ "$rc" = 1 ]' \
  "rc=$rc reruns=$(reruns) $(tail -4 "$T/out.kit")"
chk "7c. không lượt nào ghi last_full_green_sha; scratch gỡ, khoá nhả" \
  '[ ! -e "$COMMON/postfix-gate/last_full_green_sha" ] && no_scratch'

# --- 8. suite đỏ không có lệnh chạy lại ------------------------------------------------------------------------------------------
rc=$(run_gf nocmd)
chk "8. suite đỏ không có command: không coi 'chạy lại xanh' rỗng là nhóm b ⇒ result red, exit 1, thẻ High" \
  'hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")" && [ "$rc" = 1 ] && grep -q "High" "$T/card.args"' \
  "rc=$rc $(tail -1 "$HIST")"

# --- 9. ca đỏ thật chỉ có trong toàn văn log -------------------------------------------------------------------------------------
rc=$(run_gf hidden)
chk "9. fail_lines + đuôi chỉ thấy watchdog, toàn văn log có ca đỏ thật ⇒ result red, chia đôi, exit 1" \
  '[ "$(reruns)" -gt 1 ] && hist "row[\"result\"] == \"red\" and not row.get(\"group_b\")" && [ "$rc" = 1 ]' "rc=$rc reruns=$(reruns) $(tail -1 "$HIST")"

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_full_red_env: PASS"; exit 0; fi
echo "test_gate_full_red_env: $fails FAIL"; exit 1
