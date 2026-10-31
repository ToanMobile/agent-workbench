#!/usr/bin/env bash
# Test hồi quy (#741, anh Đạt 31/10): gate PR / merge gate / `post-fix-gate.py --scoped` KHÔNG BAO GIỜ tự leo --full; cả bộ suite chỉ
# chạy ở gate-full đêm 00:00 (bin/gate_full.py gọi `--tree HEAD`).
#   u1. sửa file [core] có test chạm tới ⇒ decide vẫn PHÂN LOẠI full, no_full ra scoped: test của file đó + smoke, core_touched, would_full;
#   u2. file [core] không test nào chạm ⇒ thêm [core-smoke]; u3. unmapped ⇒ [core-smoke]; u4. code bị xoá không test nào nhắc ⇒ [core-smoke];
#   u4b. code bị xoá mà test còn nhắc tên (gọi tên cũ) ⇒ chọn đúng test đó (đồ thị của cây hiện tại không còn nút của file bị xoá);
#   u4c. .py bị xoá mà test import theo stem (`from lib import gone3`) ⇒ chọn test đó; u4d. dòng tests/impact_map.txt khớp file bị xoá ⇒ chọn;
#   u7. `gen --write-core` (write_core_auto) giữ nguyên mục [core-smoke];
#   u5. base sai (đồ thị lỗi) ⇒ scoped, smoke + [core-smoke]; u6. file thường có test ⇒ không thêm [core-smoke];
#   r.  [core-smoke] của repo có trần: mọi mục là file thật, có trong tests/lib/test_durations.txt, tổng ≤ 120 s;
#   e1. `--run-tests --scoped --brief --json` sửa file lõi: chạy test của nó, runs.jsonl mode scoped + core_touched, dòng "core-touched" sau
#       KẾT LUẬN (còn trong --brief), khoá core_touched trong --json;
#   e2. file lõi không test: [core-smoke] chạy, biên nhận scoped ghi core_smoke;
#   e3. POSTFIX_GATE_FULL=1 / POSTFIX_GATE_FORCE_FULL=1 / CI=true không đè --scoped;
#   e4. đối chứng: `--scoped --full` / `--scoped --force-full` tường minh vẫn full; e5. `--tree HEAD` (đường của gate-full đêm) vẫn full;
#   e6. gate_full.py vẫn gọi gate với `--tree HEAD`;
#   e7. test .py chạm diff mà không luật ma trận nào chạy đúng môi trường: không chạy ở PR, [core-smoke] bù, nêu trong tóm tắt --brief;
#   e8. git mv file code sang tài liệu: luật ma trận theo dõi đường dẫn CŨ vẫn chạy (không "chỉ tài liệu", không 0 test).
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY POSTFIX_GATE_FULL \
      POSTFIX_GATE_FORCE_FULL
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── u. no_full trên sandbox (hàm thuần của bin/scoped_gate.py)
SB="$TMP/u"
mkdir -p "$SB/lib" "$SB/tests/x" "$SB/tests/s" "$SB/.agents" && cd "$SB" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
printf '[core]\nlib/core_t.py\nlib/core_u.py\n\n[smoke]\ntests/s/test_smoke.sh\n\n[core-smoke]\ntests/s/test_cs.sh\n' > .agents/gate-core.txt
printf 'T = 1\n' > lib/core_t.py
printf 'U = 1\n' > lib/core_u.py
printf 'P = 1\n' > lib/plain.py
printf 'O = 1\n' > lib/orphan.py
printf 'G = 1\n' > lib/gone.py
printf 'H = 1\n' > lib/gone2.py
printf '#!/usr/bin/env bash\npython3 lib/gone.py\n' > tests/x/test_gone.sh
printf 'G3 = 1\n' > lib/gone3.py
printf 'from lib import gone3\n\ndef test_g3():\n    assert gone3.G3\n' > tests/x/test_g3.py
printf 'G4 = 1\n' > lib/gone4.py
printf '#!/usr/bin/env bash\ntrue\n' > tests/x/test_im.sh
printf 'lib/gone4.py tests/x/test_im.sh\n' > tests/impact_map.txt
printf '#!/usr/bin/env bash\npython3 lib/core_t.py\n' > tests/x/test_core_t.sh
printf '#!/usr/bin/env bash\npython3 lib/plain.py\n' > tests/x/test_plain.sh
printf '#!/usr/bin/env bash\ntrue\n' > tests/s/test_smoke.sh
printf '#!/usr/bin/env bash\ntrue\n' > tests/s/test_cs.sh
git add -A && git commit -qm base || exit 2

UOUT="$(python3 -I - "$SG" "$SB" <<'PY' 2>&1
import os, subprocess, sys
SG, SB = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.dirname(SG))
import scoped_gate as sg  # noqa: E402
if not hasattr(sg, "no_full"):
    print("u0|no-no_full"); sys.exit(0)


def edit(path, text):
    with open(os.path.join(SB, path), "w") as f:
        f.write(text)


def reset():
    subprocess.run(["git", "-C", SB, "checkout", "-q", "-f", "HEAD"], capture_output=True)
    subprocess.run(["git", "-C", SB, "clean", "-fdq"], capture_output=True)


def show(tag, base="HEAD"):
    d = sg.decide(SB, base)
    n = sg.no_full(d, SB)
    print("%s|cls=%s|mode=%s|tests=%s|smoke=%s|cs=%s|core=%s|wf=%d|reasons=%d" % (
        tag, d["mode"], n["mode"], ",".join(n["tests"]), ",".join(n["smoke"]), ",".join(n["core_smoke"]),
        ",".join(n["core_touched"]), len(n["would_full"]), len(n["reasons"])))


reset(); edit("lib/core_t.py", "T = 2\n"); show("u1")
reset(); edit("lib/core_u.py", "U = 2\n"); show("u2")
reset(); edit("lib/orphan.py", "O = 2\n"); show("u3")
reset(); os.remove(os.path.join(SB, "lib/gone2.py")); show("u4")
reset(); os.remove(os.path.join(SB, "lib/gone.py")); show("u4b")
reset(); os.remove(os.path.join(SB, "lib/gone3.py")); show("u4c")
reset(); os.remove(os.path.join(SB, "lib/gone4.py")); show("u4d")
reset(); show("u5", base="no-such-ref")
reset(); edit("lib/plain.py", "P = 2\n"); show("u6")
reset(); sg.write_core_auto(SB, [("lib/plain.py", "fan-in 9")]); print("u7|" + ",".join(sg.load_core(SB)["core_smoke"]))
PY
)"
u() { printf '%s\n' "$UOUT" | grep "^$1|"; }
case "$UOUT" in *"u0|no-no_full"*) fail "u. bin/scoped_gate.py chưa có no_full(): gate PR còn leo full" ;; esac
case "$(u u1)" in "u1|cls=full|mode=scoped|tests=tests/x/test_core_t.sh|smoke=tests/s/test_smoke.sh|cs=|core=lib/core_t.py|wf=1|reasons=0")
  ok "u1. file [core] có test: phân loại full, no_full ra scoped = test của nó + smoke, core_touched, would_full" ;;
  *) fail "u1. file [core] có test: $(u u1)" ;; esac
case "$(u u2)" in "u2|cls=full|mode=scoped|tests=|smoke=tests/s/test_smoke.sh,tests/s/test_cs.sh|cs=tests/s/test_cs.sh|core=lib/core_u.py|"*)
  ok "u2. file [core] không test chạm: thêm [core-smoke]" ;; *) fail "u2. file [core] không test: $(u u2)" ;; esac
case "$(u u3)" in "u3|cls=full|mode=scoped|tests=|smoke=tests/s/test_smoke.sh,tests/s/test_cs.sh|cs=tests/s/test_cs.sh|core=|"*)
  ok "u3. unmapped: scoped + [core-smoke], không full" ;; *) fail "u3. unmapped: $(u u3)" ;; esac
case "$(u u4)" in "u4|cls=full|mode=scoped|tests=|"*"|cs=tests/s/test_cs.sh|"*) ok "u4. code bị xoá không test nào nhắc: scoped + [core-smoke]" ;;
  *) fail "u4. code bị xoá: $(u u4)" ;; esac
case "$(u u4b)" in "u4b|cls=full|mode=scoped|tests=tests/x/test_gone.sh|smoke=tests/s/test_smoke.sh|cs=|"*)
  ok "u4b. code bị xoá mà test còn gọi tên cũ: chọn đúng test đó" ;; *) fail "u4b. code bị xoá, test còn gọi tên cũ không được chọn: $(u u4b)" ;; esac
case "$(u u4c)" in "u4c|cls=full|mode=scoped|tests=tests/x/test_g3.py|"*"|cs=|"*) ok "u4c. .py bị xoá, test import theo stem: chọn test đó" ;;
  *) fail "u4c. .py bị xoá, test import theo stem không được chọn: $(u u4c)" ;; esac
case "$(u u4d)" in "u4d|cls=full|mode=scoped|tests=tests/x/test_im.sh|"*"|cs=|"*) ok "u4d. impact_map.txt khớp file bị xoá: chọn test đó" ;;
  *) fail "u4d. impact_map.txt khớp file bị xoá không được chọn: $(u u4d)" ;; esac
[ "$(u u7)" = "u7|tests/s/test_cs.sh" ] && ok "u7. write_core_auto giữ [core-smoke]" || fail "u7. write_core_auto làm mất [core-smoke]: $(u u7)"
case "$(u u5)" in "u5|cls=full|mode=scoped|tests=|smoke=tests/s/test_smoke.sh,tests/s/test_cs.sh|cs=tests/s/test_cs.sh|core=|wf=1|reasons=0")
  ok "u5. base sai: scoped = smoke + [core-smoke], lý do giữ ở would_full" ;; *) fail "u5. base sai: $(u u5)" ;; esac
case "$(u u6)" in "u6|cls=scoped|mode=scoped|tests=tests/x/test_plain.sh|smoke=tests/s/test_smoke.sh|cs=|core=|wf=0|reasons=0")
  ok "u6. file thường có test: như cũ, không [core-smoke]" ;; *) fail "u6. file thường: $(u u6)" ;; esac
[ -n "$(u u1)" ] || printf '%s\n' "$UOUT" | tail -8

# ── r. [core-smoke] của repo chứa kit (agent-workbench): có trần thời gian. Kit tách riêng (không có gate-core.txt ở trên) thì bỏ qua.
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
if [ -f "$ROOT/.agents/gate-core.txt" ]; then
  ROUT="$(python3 -I - "$SG" "$ROOT" "$DEVKIT_DIR/tests/lib/test_durations.txt" <<'PY' 2>&1
import os, sys
SG, ROOT, DUR = sys.argv[1:4]
sys.path.insert(0, os.path.dirname(SG))
import scoped_gate as sg  # noqa: E402
cs = sg.load_core(ROOT).get("core_smoke") or []
kit = os.path.relpath(os.path.dirname(os.path.dirname(SG)), ROOT) + "/"
dur = {}
for line in open(DUR, encoding="utf-8"):
    p = line.split()
    if len(p) == 2 and not line.startswith("#"):
        dur[kit + p[1]] = float(p[0])
missing = [p for p in cs if not os.path.isfile(os.path.join(ROOT, p))]
untimed = [p for p in cs if p not in dur]
print("n=%d|missing=%s|untimed=%s|sum=%d" % (len(cs), ",".join(missing), ",".join(untimed), sum(dur.get(p, 0) for p in cs)))
PY
)"
  case "$ROUT" in "n=0|"*) fail "r. repo không có mục [core-smoke] trong .agents/gate-core.txt: $ROUT" ;;
    *"|missing=|untimed=|sum="*)
      s="${ROUT##*sum=}"
      [ "$s" -le 120 ] 2>/dev/null && ok "r. [core-smoke] của repo: mọi mục là file thật, có thời lượng, tổng $s s ≤ 120 s" \
        || fail "r. [core-smoke] tổng $s s > 120 s: $ROUT" ;;
    *) fail "r. [core-smoke] có mục không phải file thật / không có trong test_durations.txt: $ROUT" ;; esac
else
  ok "r. bỏ qua: kit không nằm trong repo có .agents/gate-core.txt"
fi

# ── e. post-fix-gate.py thật trên sandbox
R="$TMP/e"
mkdir -p "$R/src" "$R/tests" "$R/.agents" "$R/templates" && cd "$R" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
printf '[core]\nsrc/core.py\nsrc/lonely.py\n\n[smoke]\ntests/test_smoke.sh\n\n[core-smoke]\ntests/test_cs.sh\n' > .agents/gate-core.txt
printf 'C = 1\n' > src/core.py
printf 'L = 1\n' > src/lonely.py
printf 'Y = 1\n' > src/pyonly.py
printf 'M = 1\n' > src/mv.py
mkdir -p docs
printf 'import subprocess\n\ndef test_pyonly():\n    assert subprocess.call(["python3", "src/pyonly.py"]) == 0\n' > tests/test_pyonly.py
printf '#!/usr/bin/env bash\necho core >> "%s/ran"\npython3 src/core.py\n' "$TMP" > tests/test_core.sh
printf '#!/usr/bin/env bash\necho cs >> "%s/ran"\n' "$TMP" > tests/test_cs.sh
printf '#!/usr/bin/env bash\necho smoke >> "%s/ran"\n' "$TMP" > tests/test_smoke.sh
printf '.claude/\n' > .gitignore
echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh; ma trận mặc định (--tree chỉ tin ma trận đã commit)
cat > templates/regression_matrix.json <<JSON
{"project": "t", "rules": [{"component": "C", "watch_files": ["src/core.py", "src/lonely.py", "src/pyonly.py", "src/m[v].py"],
  "mandatory_regression_tests": [{"id": "REG-C", "name": "c", "command": "echo REG-C >> '$TMP/ran'"}]}]}
JSON
git add -A && git commit -qm init || exit 2
git init -q --bare -b main "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin main 2>/dev/null || exit 2   # --tree: HEAD phải có trên origin
RL="$(git rev-parse --absolute-git-dir)/postfix-gate/runs.jsonl"
SP="$(git rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
gate() { : > "$TMP/ran"; GOUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --no-cache "$@" 2>&1)"; RC=$?; }
last() { tail -1 "$RL" 2>/dev/null | python3 -c 'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print("mode=%s|core=%s|reason=%s" % (r.get("mode"), ",".join(r.get("core_touched") or []), r.get("force_reason") or ""))' 2>/dev/null; }
ran() { grep -qx "$1" "$TMP/ran" 2>/dev/null; }

# e1. sửa file lõi có test (--brief --json: chỉ còn tóm tắt sau KẾT LUẬN + dòng JSON cuối)
echo 'C = 2' > src/core.py
gate --scoped --brief --json
L1="$(last)"
J1="$(printf '%s\n' "$GOUT" | tail -1 | python3 -c 'import json,sys; print(",".join(json.loads(sys.stdin.read()).get("core_touched", ["NO-KEY"])))' 2>/dev/null)"
if [ "$RC" = 0 ] && [ "$L1" = "mode=scoped|core=src/core.py|reason=" ] && ran core && ran smoke && printf '%s\n' "$GOUT" | grep -q "core-touched.*src/core.py" \
   && [ "$J1" = src/core.py ]; then
  ok "e1. --scoped sửa file lõi: chạy test của nó + smoke, runs.jsonl mode scoped + core_touched, core-touched trong --brief và --json"
else fail "e1. --scoped sửa file lõi: exit $RC, runs.jsonl {$L1}, --json core_touched '$J1', ran: $(tr '\n' ' ' < "$TMP/ran" 2>/dev/null)"
  printf '%s\n' "$GOUT" | grep -E "scoped|full|core" | tail -5; fi
git checkout -q -- src/core.py 2>/dev/null || git -C "$R" restore -q src/core.py

# e2. file lõi không test nào chạm: [core-smoke] chạy, biên nhận ghi core_smoke
echo 'L = 2' > src/lonely.py
rm -f "$SP"; gate --scoped
CS="$(python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1])).get("core_smoke") or []))' "$SP" 2>/dev/null || echo NO-RECEIPT)"
if [ "$RC" = 0 ] && [ "$(last)" = "mode=scoped|core=src/lonely.py|reason=" ] && ran cs && [ "$CS" = tests/test_cs.sh ]; then
  ok "e2. file lõi không test: [core-smoke] chạy, biên nhận scoped ghi core_smoke"
else fail "e2. file lõi không test: exit $RC, runs.jsonl {$(last)}, core_smoke trong biên nhận: $CS, ran: $(tr '\n' ' ' < "$TMP/ran" 2>/dev/null)"; fi

# e3. biến môi trường ép full không đè --scoped tường minh
for kv in POSTFIX_GATE_FULL=1 POSTFIX_GATE_FORCE_FULL=1 CI=true; do
  export "$kv"; gate --scoped; unset "${kv%%=*}"
  case "$(last)" in "mode=scoped|"*) ok "e3. $kv + --scoped ⇒ vẫn scoped" ;; *) fail "e3. $kv + --scoped ⇒ {$(last)} (mong mode=scoped)" ;; esac
done
git checkout -q -- src/lonely.py 2>/dev/null || git -C "$R" restore -q src/lonely.py

# e4. đối chứng: --full tường minh vẫn full
echo 'C = 3' > src/core.py
gate --scoped --full
case "$(last)" in "mode=full|"*"reason=--full") ok "e4. --scoped --full tường minh ⇒ full" ;; *) fail "e4. --scoped --full ⇒ {$(last)} (mong mode=full, reason --full)" ;; esac
gate --scoped --force-full
case "$(last)" in "mode=full|"*"reason=--force-full") ok "e4. --scoped --force-full tường minh ⇒ full" ;; *) fail "e4. --scoped --force-full ⇒ {$(last)} (mong mode=full)" ;; esac
git checkout -q -- src/core.py 2>/dev/null || git -C "$R" restore -q src/core.py

# e5. --tree HEAD (đường gate-full đêm) trên cây sạch vẫn full
gate --tree HEAD
case "$(last)" in "mode=full|"*"reason=--tree") ok "e5. --tree HEAD (gate-full đêm) ⇒ full" ;;
  *) fail "e5. --tree HEAD ⇒ exit $RC {$(last)} (mong mode=full, reason --tree)"; printf '%s\n' "$GOUT" | tail -4 ;; esac

# e6. gate-full đêm gọi gate bằng --tree HEAD
grep -q '"--run-tests", "--tree", "HEAD"' "$DEVKIT_DIR/bin/gate_full.py" && ok "e6. gate_full.py gọi post-fix-gate --run-tests --tree HEAD (full)" \
  || fail "e6. gate_full.py không còn gọi --run-tests --tree HEAD"

# e7. test .py chạm diff, không luật ma trận cụ thể nào chạy nó đúng môi trường: không chạy ở PR, [core-smoke] bù, tóm tắt --brief nêu tên
echo 'Y = 2' > src/pyonly.py
gate --scoped --brief
if [ "$RC" = 0 ] && [ "$(last)" = "mode=scoped|core=|reason=" ] && ran cs && printf '%s\n' "$GOUT" | grep -q "tests/test_pyonly.py"; then
  ok "e7. test .py không suite nào chạy: [core-smoke] bù, tóm tắt --brief nêu tests/test_pyonly.py"
else fail "e7. test .py không suite nào chạy: exit $RC, runs.jsonl {$(last)}, ran: $(tr '\n' ' ' < "$TMP/ran" 2>/dev/null)"; printf '%s\n' "$GOUT" | tail -6; fi
git checkout -q -- src/pyonly.py 2>/dev/null || git -C "$R" restore -q src/pyonly.py

# e8. git mv file code sang tài liệu: luật theo dõi đường dẫn cũ (REG-C: glob src/m[v].py — ma trận không nêu đúng tên file nên vẫn tin
#     được) vẫn chạy, không xanh 0 test
git mv src/mv.py docs/mv.md
gate --scoped
if [ "$RC" = 0 ] && [ "$(last)" = "mode=scoped|core=|reason=" ] && ran REG-C; then ok "e8. git mv code → tài liệu: luật theo dõi đường dẫn cũ vẫn chạy"
else fail "e8. git mv code → tài liệu: exit $RC, runs.jsonl {$(last)}, ran: $(tr '\n' ' ' < "$TMP/ran" 2>/dev/null) (mong REG-C)"; printf '%s\n' "$GOUT" | grep -E "KẾT LUẬN|CHƯA|✖|⚠|orphan|mồ côi|không phủ|coverage" | head -8; fi
git mv docs/mv.md src/mv.py

[ "$FAILS" -eq 0 ] && { echo "PASS test_scoped_gate_nofull"; exit 0; }
echo "FAIL test_scoped_gate_nofull ($FAILS)"; exit 1
