#!/usr/bin/env bash
# Test hồi quy (#785, Epic #790 — Mục 1): bin/post-fix-gate.py dùng lại biên nhận scoped
# (<git common dir>/postfix-gate/scoped_receipts/<fp>.json) cho lượt `--run-tests --scoped`
# trong một git dir CHƯA từng chạy gate (scratch của merge gate, integrate, worktree QA/review mới):
#   1. Worktree A chạy --scoped PASS (gồm cả suite KEYED qua SuiteCache và runner run_impacted.sh chạy thật) rồi bị gỡ;
#      scratch B mới chạy đúng trình tự .merge-scratch (worktree add --detach -> git merge origin/main -> install.sh --no-githooks
#      -> git checkout -q -- . -> copy_ignored của super-board-scratch-config.sh -> .merge-evidence/ -> --scoped): _ever_gated(B)==False,
#      fp và local_sha giữ nguyên, 0 suite chạy lại, exit 0, tested_at giữ nguyên, push_gate nhận, runs.jsonl ghi mode="scoped",
#      verdict="REUSED", reused_full_pass=true, reused_scoped=<fp>; mục store không bị lượt mượn ghi đè (V4-4) và mang full_command (V4-1).
#   1b. Chạy lại --scoped ngay trên cùng worktree (own_receipt) vẫn chạy REG-K + REG-N; ở scratch mới, suite khai "cache": false
#       vẫn chạy thật mỗi lượt kể cả khi các suite khác dùng lại biên nhận scoped.
#   2. Không dùng lại (chạy lại suite + ghi reuse_miss_reason vào runs.jsonl) khi: (a) đổi matrix_sha,
#      (b) đổi gate_sha (bản sao post-fix-gate.py đặt ngoài cây repo), (c) thêm file chưa track (đổi fp -> not_found),
#      (d) biên nhận exit != 0, (e) cùng cây nhưng base khác làm phát sinh test ngoài biên nhận (superset),
#      (f) mục KEYED mất hiệu lực trong SuiteCache, (g) quá hạn DEVKIT_GATE_CACHE_MAX_S (ttl),
#      (h) có dòng --full đỏ trên cùng fp (full_red), (i) worktree đã từng chạy gate (ever_gated) hoặc mục store là symlink (not_found),
#      (j) SCOPED-EXTRA cùng id nhưng khác lệnh (base khác đổi suite ma trận đã chọn) ⇒ chạy thật (V4-1).
#   3. Một lượt FAIL sau đó trên cùng cây xoá mục scoped_receipts/<fp>.json; worktree mới phải chạy lại suite và lượt dùng lại cũ
#      không bao giờ hồi sinh mục đã xoá (lượt mượn không ghi mục store: write_store=False, V4-4).
#   4. Race khoá (stale_reused): biên nhận scoped nguồn bị xoá trước kết luận (mô phỏng lượt song song vừa FAIL) ⇒ kết luận
#      lật thành UNTESTED (STALE, exit 4), không bao giờ trả exit 0 dựa trên biên nhận đã huỷ.
#   4b. Lượt --scoped PASS bình thường khi store rỗng (không reuse) vẫn ghi scoped_pass.json + mục store, không UnboundLocalError (OCR4-1).
#   5. Cổng vào chụp trước test_run.lock (AG2-P1, OCR2-H2): (a) mục store bị ghi lại hợp lệ lúc đang giữ khoá ⇒ stale_reused kiểm lại
#      bằng cached_scoped_pass, exit 0 (không STALE oan); (b) mục store xuất hiện lúc scratch đang giữ test_run.lock chờ gate slot ⇒
#      kiểm lại sau khoá/slot vẫn dùng lại (0 suite chạy, verdict=REUSED); (c) mục store bị lượt PASS khác ghi lại với suite đã mượn
#      thành UNTESTED/KEYED ⇒ tra khoá nội dung của suite đó, còn trúng thì giữ, exit 0 (V4-3).
#   6. Runner run_impacted.sh không có KEYS ở lượt --scoped: FAIL đã ghi trên cùng khoá chặn mượn PASS từ store còn nguyên (AG5-P1b).
#   7. Lượt --scoped chép PASS từ full_pass.json riêng là lượt mượn: không ghi lại mục store mà một FAIL đã xoá (AG5-P1a).
# Tương thích bash 3.2, chỉ dùng Python stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE CI \
      DEVKIT_SLOT_PRIORITY DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_PER_TEST_CACHE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export DEVKIT_SENTINEL_MAX_S=999999999

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cnt()  { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
snap() { echo "$(cnt A) $(cnt K) $(cnt N) $(cnt X)"; }
dlt()  { python3 -c 'import sys; a, b = sys.argv[1].split(), sys.argv[2].split(); print(" ".join(str(int(y) - int(x)) for x, y in zip(a, b)))' "$1" "$2"; }

ORIGIN="$TMP/origin.git"
R="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$R" 2>/dev/null || exit 1
(
  cd "$R" || exit 1
  git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src tests kit/tests/g .agents
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/\n.hong\n' > .gitignore
  bash "$DEVKIT_DIR/bin/install.sh" -t "$R" -a claude -y --no-githooks >/dev/null 2>&1 || true
  echo '{"profile":"backend"}' > .agents/active-profile.json
  echo 'a = 1' > src/a.py
  echo 'k = 1' > src/k.py
  echo 'n = 1' > src/n.py
  echo 'x = 1' > src/x.py
  printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_a.sh
  printf '#!/usr/bin/env bash\ngrep -q = src/x.py\n' > tests/test_x.sh
  printf '#!/usr/bin/env bash\ngrep -q = src/k.py\n' > kit/tests/g/test_k.sh
  cat > kit/tests/run_impacted.sh <<SH
#!/usr/bin/env bash
# devkit-selection-list: --list in danh sách test chọn, không chạy gì
if [ "\${1-}" = --list ]; then echo tests/g/test_k.sh; exit 0; fi
echo run >> '$TMP/count.K'
test ! -f .hong
SH
  chmod +x tests/test_a.sh tests/test_x.sh kit/tests/g/test_k.sh kit/tests/run_impacted.sh
  python3 - "$R/.agents/regression_matrix.active.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"],
     "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": f"echo run >> '{tmp}/count.A'; bash tests/test_a.sh"}]},
    {"component": "K", "watch_files": ["src/k.py", "kit/*"],
     "mandatory_regression_tests": [{"id": "REG-K", "name": "kit", "command": "bash kit/tests/run_impacted.sh"}]},
    {"component": "N", "watch_files": ["src/n.py"],
     "mandatory_regression_tests": [{"id": "REG-N", "name": "nocache", "command": f"echo run >> '{tmp}/count.N'", "cache": False}]},
    {"component": "X", "watch_files": ["src/x.py"],
     "mandatory_regression_tests": [{"id": "REG-X", "name": "extra", "command": f"echo run >> '{tmp}/count.X'; bash tests/test_x.sh"}]},
]}, open(path, "w"))
PY
  git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
) || exit 1

COMMON="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"
SSTORE="$COMMON/postfix-gate/scoped_receipts"
RUNLOG="$COMMON/postfix-gate/runs.jsonl"

run_scoped() {
  local wt="$1"; shift
  local g="${GATE_BIN:-$GATE}"
  OUT="$(cd "$wt" && CLAUDE_PROJECT_DIR="$wt" python3 "$g" --diff "${DIFF_REF:-origin/main}" --run-tests --scoped --no-checklist "$@" 2>&1)"
  RC=$?
}
add_wt() { git -C "$R" worktree add -q --detach "$TMP/$1" "${2:-feat}" || { echo "✖ setup worktree $1"; exit 1; }; }
rm_wt()  { git -C "$R" worktree remove --force "$TMP/$1" 2>/dev/null || rm -rf "$TMP/$1"; }
store_file() { ls "$SSTORE"/*.json 2>/dev/null | head -1; }
last_miss_reason() { tail -1 "$RUNLOG" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("reuse_miss_reason",""))'; }
wipe_scoped() {
  rm -f "$COMMON/postfix-gate/scoped_pass.json" "$COMMON"/worktrees/*/postfix-gate/scoped_pass.json
  rm -rf "$SSTORE"
}

# ── 1. Chuẩn bị nhánh feat: lượt 1 ở wt-a nạp REG-A vào SuiteCache, lượt 2 ở wt-a tạo biên nhận scoped có cả KEYED (REG-A) + PASS thật (REG-K)
git -C "$R" checkout -q -b feat
echo 'a = 2' > "$R/src/a.py"
echo 'k = 2' > "$R/src/k.py"
git -C "$R" commit -qam "edit a and k"
git -C "$R" checkout -q main

git -C "$R" worktree add -q "$TMP/wt-a" feat
bash "$DEVKIT_DIR/bin/install.sh" -t "$TMP/wt-a" -a claude -y --no-githooks >/dev/null 2>&1 || true
git -C "$TMP/wt-a" checkout -q -- .
run_scoped "$TMP/wt-a"
[ "$RC" = 0 ] || { fail "1. tiền đề lượt 1 ở wt-a thất bại ($RC): $OUT"; exit 1; }
# Lùi last_pass_at của SuiteCache về 5h trước (18000 s < 6h DEVKIT_GATE_CACHE_MAX_S):
# lượt 2 của wt-a vẫn phải ghi tested_at mới (cách hiện tại < 120 s, không bị kéo lùi 5h theo SuiteCache)
python3 - "$COMMON/postfix-gate/suite_cache" <<'PY'
import glob, json, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "*.json")):
    try:
        d = json.load(open(p))
        if isinstance(d, dict) and "last_pass_at" in d:
            d["last_pass_at"] = float(d["last_pass_at"]) - 18000
            json.dump(d, open(p, "w"))
    except Exception:
        pass
PY
b0="$(snap)"
run_scoped "$TMP/wt-a"
d0="$(dlt "$b0" "$(snap)")"
if [ "$RC" = 0 ] && [ "$d0" = "0 1 0 0" ]; then
  ok "1. tiền đề: PR gate ở wt-a chạy REG-K (1 lần) và dùng khoá cho REG-A (KEYED trong biên nhận)"
else
  fail "1. tiền đề wt-a: rc=$RC delta=$d0 (mong rc=0, 0 1 0 0)"; printf '%s\n' "$OUT" | tail -15; exit 1
fi
SF="$(store_file)"
[ -n "$SF" ] || { fail "1. tiền đề: thiếu file trong scoped_receipts/"; exit 1; }
KEYED_ST="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next(("%s/%s" % (x.get("status"), x.get("label")) for x in d["tests"] if x["id"]=="REG-A"), "?"))' "$SF")"
[ "$KEYED_ST" = "UNTESTED/KEYED" ] && ok "1. tiền đề: biên nhận scoped ghi REG-A là UNTESTED/KEYED" \
  || fail "1. tiền đề: trạng thái REG-A trong biên nhận = $KEYED_ST (mong UNTESTED/KEYED)"
TESTED0="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tested_at"])' "$SF")"
FRESH_OK="$(python3 -c 'import sys,time; print("yes" if time.time() - float(sys.argv[1]) < 120 else "no")' "$TESTED0")"
[ "$FRESH_OK" = "yes" ] && ok "1. tiền đề: tested_at của biên nhận mới không bị SuiteCache 5h trước kéo lùi" \
  || fail "1. tiền đề: tested_at bị kéo lùi ($TESTED0)"
FP0="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fingerprint"])' "$SF")"
# Gỡ hẳn wt-a để chắc chắn chỉ còn scoped_receipts/<fp>.json trong common dir (như sau Builder bước 9 / merge scratch)
rm_wt wt-a

# Scratch B mới mô phỏng ĐÚNG đường .merge-scratch của super-board-merge-gate.sh:
# worktree add --detach -> git merge origin/main --no-edit -> install.sh -a claude -y --no-githooks -> git checkout -q -- .
add_wt wt-b feat
git -C "$TMP/wt-b" merge origin/main --no-edit -q
bash "$DEVKIT_DIR/bin/install.sh" -t "$TMP/wt-b" -a claude -y --no-githooks >/dev/null 2>&1 || true
git -C "$TMP/wt-b" checkout -q -- .
# V4-6: hai bước thật còn lại của merge gate trước verify — super-board-scratch-config.sh (worktree.py copy_ignored từ main checkout)
# và prepare_scratch_evidence (.merge-evidence/ + dòng exclude trong git dir của scratch)
if ! python3 - "$DEVKIT_DIR/scripts/git/worktree.py" "$R" "$TMP/wt-b" >/dev/null 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.copy_ignored(sys.argv[2], sys.argv[3])
PY
then fail "1. copy_ignored (super-board-scratch-config.sh) vào wt-b lỗi"; fi
GD_B="$(git -C "$TMP/wt-b" rev-parse --absolute-git-dir)"
mkdir -p "$GD_B/info" "$TMP/wt-b/.merge-evidence/tests"
grep -qxF '.merge-evidence/' "$GD_B/info/exclude" 2>/dev/null || printf '%s\n' '.merge-evidence/' >> "$GD_B/info/exclude"
PRE_B="$(python3 - "$GATE" "$DEVKIT_DIR/bin" "$TMP/wt-b" "$SF" <<'PY'
import importlib.util, json, sys
gate_path, bin_dir, wt, store = sys.argv[1:]
sys.path.insert(0, bin_dir)
import tree_fp
spec = importlib.util.spec_from_file_location("pfg_pre_b", gate_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("%s|%s|%s" % (m._ever_gated(wt), tree_fp.tree_fingerprint(wt), m.local_state_sha(wt) == json.load(open(store)).get("local_sha")))
PY
)"
[ "$PRE_B" = "False|$FP0|True" ] && ok "1. sau install.sh + checkout -- . + copy_ignored + .merge-evidence/: _ever_gated(wt-b)=False, fp giữ nguyên ($FP0), local_sha khớp" \
  || fail "1. trạng thái wt-b trước gate lệch: $PRE_B (mong False|$FP0|True)"
STORE_SHA0="$(shasum -a 256 "$SF" | cut -d' ' -f1)"
b1="$(snap)"
run_scoped "$TMP/wt-b" --brief
d1="$(dlt "$b1" "$(snap)")"
if [ "$RC" = 0 ] && [ "$d1" = "0 0 0 0" ]; then
  ok "1. scratch B mới (sau merge + install.sh --no-githooks + checkout -- .): dùng lại biên nhận scoped, 0 suite chạy lại"
else
  fail "1. scratch B mới: rc=$RC delta=$d1 (mong rc=0, 0 0 0 0)"; printf '%s\n' "$OUT" | tail -20
fi
SP_B="$(git -C "$TMP/wt-b" rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
TESTED_B="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tested_at"])' "$SP_B" 2>/dev/null || echo NONE)"
[ "$TESTED_B" = "$TESTED0" ] && ok "1. tested_at giữ nguyên mốc gốc (không kéo dài hạn 6h)" \
  || fail "1. tested_at bị đổi: $TESTED0 -> $TESTED_B"
LOG_CHECK="$(tail -1 "$RUNLOG" | python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print("%s|%s|%s|%s|%s" % (r.get("mode"), r.get("verdict"), r.get("exit_reason"), r.get("reused_full_pass"), r.get("reused_scoped","")))')"
[ "$LOG_CHECK" = "scoped|REUSED|reused|True|$FP0" ] && ok "1. runs.jsonl ghi mode=scoped, verdict=REUSED, reused_full_pass=True, reused_scoped=$FP0" \
  || fail "1. runs.jsonl sai: $LOG_CHECK (mong scoped|REUSED|reused|True|$FP0)"
# V4-4: lượt mượn KHÔNG ghi lại mục store (refresh_only vẫn ghi đè mục đang có); V4-1: mục store mang full_command của từng suite
[ "$(shasum -a 256 "$SF" 2>/dev/null | cut -d' ' -f1)" = "$STORE_SHA0" ] && ok "1. lượt mượn không ghi đè mục scoped_receipts/<fp>.json (V4-4)" \
  || fail "1. lượt mượn đã ghi đè mục store (V4-4)"
FC_OK="$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["tests"]; print(bool(t) and all(isinstance(x.get("full_command"), str) and x["full_command"] for x in t))' "$SF")"
[ "$FC_OK" = "True" ] && ok "1. mục store ghi full_command cho mọi suite (V4-1)" || fail "1. mục store thiếu full_command (V4-1)"
PUSH_OUT="$(python3 "$PG" "$TMP/wt-b" 2>&1)"; PUSH_RC=$?
[ "$PUSH_RC" = 0 ] && ok "1. push_gate nhận scoped_pass.json của worktree dùng lại" \
  || fail "1. push_gate từ chối worktree dùng lại ($PUSH_RC: $PUSH_OUT)"
rm_wt wt-b

# ── 1b. Chạy lại --scoped trên cùng worktree (own_receipt) vẫn chạy REG-K + REG-N; scratch mới vẫn chạy suite "cache": false
git -C "$R" worktree add -q "$TMP/wt-n1" feat
echo 'n = 2' > "$TMP/wt-n1/src/n.py"
git -C "$TMP/wt-n1" commit -qam "edit n"
run_scoped "$TMP/wt-n1"
[ "$RC" = 0 ] || fail "1b. tiền đề wt-n1 rc=$RC"
bsame="$(snap)"
run_scoped "$TMP/wt-n1"
dsame="$(dlt "$bsame" "$(snap)")"
if [ "$RC" = 0 ] && [ "$dsame" = "0 1 1 0" ] && [ "$(last_miss_reason)" = "own_receipt" ]; then
  ok "1b-same. chạy lại --scoped ngay trong cùng worktree ⇒ runner REG-K và suite cache:false REG-N vẫn chạy thật (own_receipt)"
else
  fail "1b-same. cùng worktree: rc=$RC delta=$dsame miss=$(last_miss_reason) (mong 0 1 1 0, own_receipt)"
fi
rm_wt wt-n1
add_wt wt-n2 feat
bn="$(snap)"
run_scoped "$TMP/wt-n2"
dn="$(dlt "$bn" "$(snap)")"
if [ "$RC" = 0 ] && [ "$dn" = "0 0 1 0" ]; then
  ok "1b. suite cache:false vẫn chạy thật (1 lần), trong khi REG-A và REG-K dùng lại (0 lần)"
else
  fail "1b. cache:false: rc=$RC delta=$dn (mong 0 0 1 0)"
fi
rm_wt wt-n2
# Đưa feat lùi lại commit trước edit n để các ca sau chỉ có REG-A + REG-K
git -C "$R" update-ref refs/heads/feat "$(git -C "$R" rev-parse feat~1)"

# ── 2a. Đổi 1 byte matrix (matrix_sha khác) ⇒ không dùng lại + ghi reuse_miss_reason=matrix_sha
cp "$R/.agents/regression_matrix.active.json" "$TMP/m_alt.json"
printf '\n' >> "$TMP/m_alt.json"
add_wt wt-2a feat
b="$(snap)"; run_scoped "$TMP/wt-2a" --matrix "$TMP/m_alt.json"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$d" = "0 1 0 0" ] && [ "$(last_miss_reason)" = "matrix_sha" ] \
  && ok "2a. đổi 1 byte matrix (matrix_sha lệch) ⇒ chạy lại REG-K, reuse_miss_reason=matrix_sha" \
  || fail "2a. matrix_sha lệch: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2a

# ── 2b. Đổi 1 byte bản sao post-fix-gate.py đặt NGOÀI cây repo ($TMP/fake_devkit/bin) ⇒ không dùng lại + reuse_miss_reason=gate_sha
mkdir -p "$TMP/fake_devkit/bin"
for item in "$DEVKIT_DIR"/*; do
  [ "$(basename "$item")" = "bin" ] && continue
  ln -s "$item" "$TMP/fake_devkit/$(basename "$item")"
done
for pyf in "$DEVKIT_DIR"/bin/*; do
  [ "$(basename "$pyf")" = "post-fix-gate.py" ] && continue
  ln -s "$pyf" "$TMP/fake_devkit/bin/$(basename "$pyf")"
done
GATE_COPY="$TMP/fake_devkit/bin/post-fix-gate.py"
cp "$GATE" "$GATE_COPY" && printf '\n# gate_sha_probe\n' >> "$GATE_COPY"
add_wt wt-2b feat
b="$(snap)"; GATE_BIN="$GATE_COPY" run_scoped "$TMP/wt-2b"; d="$(dlt "$b" "$(snap)")"
rm -rf "$TMP/fake_devkit"
[ "$RC" = 0 ] && [ "$d" = "0 1 0 0" ] && [ "$(last_miss_reason)" = "gate_sha" ] \
  && ok "2b. đổi 1 byte post-fix-gate.py ngoài cây (gate_sha lệch) ⇒ chạy lại REG-K, reuse_miss_reason=gate_sha" \
  || { fail "2b. gate_sha lệch: rc=$RC delta=$d miss=$(last_miss_reason)"; printf '%s\n' "$OUT" | tail -15; }
rm_wt wt-2b

# ── 2c. Thêm file chưa track làm đổi fp ⇒ không dùng lại + reuse_miss_reason=not_found
add_wt wt-2c feat
echo 'u = 1' > "$TMP/wt-2c/src/untracked.py"
b="$(snap)"; run_scoped "$TMP/wt-2c" --allow-no-tests; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$d" = "0 1 0 0" ] && [ "$(last_miss_reason)" = "not_found" ] \
  && ok "2c. thêm file chưa track (đổi fp) ⇒ chạy lại REG-K, reuse_miss_reason=not_found" \
  || fail "2c. file chưa track: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2c

# ── 2d. Biên nhận scoped có exit != 0 ⇒ không dùng lại
SF="$SSTORE/$FP0.json"
python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["exit"]=2; json.dump(r,open(p,"w"))' "$SF"
add_wt wt-2d feat
b="$(snap)"; run_scoped "$TMP/wt-2d"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$d" = "0 1 0 0" ] && [ "$(last_miss_reason)" = "exit_or_carried" ] \
  && ok "2d. biên nhận exit != 0 ⇒ không dùng lại, chạy lại REG-K, reuse_miss_reason=exit_or_carried" \
  || fail "2d. biên nhận exit != 0: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2d

# Khôi phục biên nhận sạch cho FP0 trước ca 2e..2i
add_wt wt-restore feat
wipe_scoped
run_scoped "$TMP/wt-restore" >/dev/null
rm_wt wt-restore

# ── 2e. Cùng cây nhưng base khác làm phát sinh thêm rule/test ngoài biên nhận ⇒ không bỏ sót test mới (superset)
git -C "$R" branch -q feat-base feat
git -C "$R" worktree add -q "$TMP/wt-eb" feat-base
echo 'x = 2' > "$TMP/wt-eb/src/x.py"
git -C "$TMP/wt-eb" commit -qam "edit x"
echo 'k = 3' > "$TMP/wt-eb/src/k.py"
git -C "$TMP/wt-eb" commit -qam "edit k3"
# Chạy scoped chỉ so với HEAD~1 (chỉ thấy k.py đổi, biên nhận KHÔNG có REG-X / test_x.sh)
DIFF_REF="HEAD~1" run_scoped "$TMP/wt-eb"
[ "$RC" = 0 ] || fail "2e. tiền đề HEAD~1 rc=$RC"
rm_wt wt-eb
# Worktree mới cùng cây feat-base nhưng so với origin/main (thấy cả x.py, a.py, k.py): bắt buộc chạy REG-X và ghi reuse_miss_reason=superset
add_wt wt-eb2 feat-base
b="$(snap)"; DIFF_REF="origin/main" run_scoped "$TMP/wt-eb2"; d="$(dlt "$b" "$(snap)")"
if [ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $4}')" = "1" ] && [ "$(last_miss_reason)" = "superset" ]; then
  ok "2e. cùng cây nhưng base rộng hơn (thêm src/x.py) ⇒ REG-X chạy thật ($d), reuse_miss_reason=superset"
else
  fail "2e. base rộng hơn bị bỏ sót REG-X: rc=$RC delta=$d miss=$(last_miss_reason)"
fi
rm_wt wt-eb2
git -C "$R" branch -q -D feat-base

# ── 2f. Mục KEYED trong biên nhận bị hỏng/xoá khỏi SuiteCache ⇒ chạy lại đúng suite đó
rm -rf "$COMMON/postfix-gate/suite_cache"
add_wt wt-2f feat
b="$(snap)"; run_scoped "$TMP/wt-2f"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $1}')" = "1" ] \
  && ok "2f. mục KEYED mất trong SuiteCache ⇒ REG-A chạy lại thật ($d)" \
  || fail "2f. mục KEYED mất mà REG-A không chạy lại: rc=$RC delta=$d"
rm_wt wt-2f

# ── 2g. Biên nhận quá hạn DEVKIT_GATE_CACHE_MAX_S=0 ⇒ không dùng lại + reuse_miss_reason=ttl
add_wt wt-2g feat
b="$(snap)"; DEVKIT_GATE_CACHE_MAX_S=0 run_scoped "$TMP/wt-2g"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ] && [ "$(last_miss_reason)" = "ttl" ] \
  && ok "2g. biên nhận quá hạn DEVKIT_GATE_CACHE_MAX_S=0 ⇒ chạy lại REG-K, reuse_miss_reason=ttl" \
  || fail "2g. biên nhận quá hạn vẫn dùng lại: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2g

# ── 2h. Có dòng --full đỏ (exit 1) trên cùng fp trong runs.jsonl ⇒ từ chối dùng lại biên nhận scoped + reuse_miss_reason=full_red
printf '{"v": 1, "epoch": %s, "mode": "full", "exit": 1, "verdict": "FAIL", "fp": "%s"}\n' "$(date +%s)" "$FP0" >> "$RUNLOG"
add_wt wt-2h feat
b="$(snap)"; run_scoped "$TMP/wt-2h"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ] && [ "$(last_miss_reason)" = "full_red" ] \
  && ok "2h. có dòng --full đỏ cùng fp ⇒ không dùng lại biên nhận scoped, chạy lại REG-K, reuse_miss_reason=full_red" \
  || fail "2h. có dòng --full đỏ mà vẫn dùng lại: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2h
# Đóng lại dấu full đỏ bằng dòng full xanh và làm mới biên nhận sạch cho ca 2i, 3, 4
printf '{"v": 1, "epoch": %s, "mode": "full", "exit": 0, "verdict": "PASS", "fp": "%s"}\n' "$(date +%s)" "$FP0" >> "$RUNLOG"
wipe_scoped
add_wt wt-clean feat; run_scoped "$TMP/wt-clean" --no-cache >/dev/null; rm_wt wt-clean

# ── 2i. Worktree đã từng chạy gate (_ever_gated) hoặc mục store là symlink ⇒ không mượn
add_wt wt-2i feat
run_scoped "$TMP/wt-2i" >/dev/null   # lượt 1: mượn hợp lệ, ghi dòng run-log cho wt-2i
rm -f "$(git -C "$TMP/wt-2i" rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
b="$(snap)"; run_scoped "$TMP/wt-2i"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ] && [ "$(last_miss_reason)" = "ever_gated" ] \
  && ok "2i. worktree đã từng chạy gate (_ever_gated) ⇒ không mượn lại store, chạy REG-K (reuse_miss_reason=ever_gated)" \
  || fail "2i. worktree đã từng chạy vẫn mượn store: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-2i

SF="$SSTORE/$FP0.json"
mv "$SF" "$TMP/real_scoped.json" && ln -s "$TMP/real_scoped.json" "$SF"
add_wt wt-sym feat
b="$(snap)"; run_scoped "$TMP/wt-sym"; d="$(dlt "$b" "$(snap)")"
rm -f "$SF" && mv "$TMP/real_scoped.json" "$SF"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ] && [ "$(last_miss_reason)" = "not_found" ] \
  && ok "2i-symlink. mục scoped_receipts là symlink ⇒ bỏ qua, chạy REG-K (reuse_miss_reason=not_found)" \
  || fail "2i-symlink. nhận nhầm symlink: rc=$RC delta=$d miss=$(last_miss_reason)"
rm_wt wt-sym

# ── 2j. V4-1 (AG4-P0): SCOPED-EXTRA giữ id cố định nhưng lệnh đổi theo quyết định. A (so origin/main) chọn REG-A nên tests/test_a.sh chạy
#    trong REG-A, SCOPED-EXTRA của A chỉ có tests/test_z.sh; B cùng cây nhưng so HEAD~1 (a.py không đổi) không chọn REG-A nên
#    tests/test_a.sh rơi vào SCOPED-EXTRA của B ⇒ B KHÔNG được mượn PASS của SCOPED-EXTRA khác lệnh, phải chạy thật
git -C "$R" branch -q feat-v41 main
git -C "$R" worktree add -q "$TMP/wt-v41a" feat-v41
echo 'a = 41' > "$TMP/wt-v41a/src/a.py"
git -C "$TMP/wt-v41a" commit -qam "v41 a"
printf '\n# v41\n' >> "$TMP/wt-v41a/tests/test_a.sh"
printf '#!/usr/bin/env bash\necho run >> %s\n' "'$TMP/count.Z'" > "$TMP/wt-v41a/tests/test_z.sh"
chmod +x "$TMP/wt-v41a/tests/test_z.sh"
git -C "$TMP/wt-v41a" add -A && git -C "$TMP/wt-v41a" commit -qm "v41 tests"
zb="$(cnt Z)"; ab="$(cnt A)"
DIFF_REF="origin/main" run_scoped "$TMP/wt-v41a" --allow-orphan-tests   # test_z.sh cố ý không thuộc suite ma trận nào
FP41="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.tree_fingerprint(sys.argv[2]))' "$DEVKIT_DIR/bin" "$TMP/wt-v41a")"
EXTRA_A="$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["tests"]; print(next((x.get("full_command") or "" for x in t if x["id"]=="SCOPED-EXTRA"), ""))' "$SSTORE/$FP41.json" 2>/dev/null)"
if [ "$RC" = 0 ] && [ "$(cnt A)" -gt "$ab" ] && [ "$(cnt Z)" -gt "$zb" ] && printf '%s' "$EXTRA_A" | grep -q 'test_z.sh' \
   && ! printf '%s' "$EXTRA_A" | grep -q 'test_a.sh'; then
  ok "2j. tiền đề: A chạy REG-A + SCOPED-EXTRA chỉ có test_z.sh, mục store ghi lệnh đó"
else
  fail "2j. tiền đề A: rc=$RC extra='$EXTRA_A'"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-v41a
add_wt wt-v41b feat-v41
zb="$(cnt Z)"
DIFF_REF="HEAD~1" run_scoped "$TMP/wt-v41b" --allow-orphan-tests
if [ "$RC" = 0 ] && [ "$(( $(cnt Z) - zb ))" = 1 ]; then
  ok "2j. B cùng cây, SCOPED-EXTRA khác lệnh (thêm test_a.sh) ⇒ chạy thật, không mượn PASS của lệnh khác (V4-1)"
else
  fail "2j. B mượn PASS của SCOPED-EXTRA khác lệnh: rc=$RC Z+=$(( $(cnt Z) - zb )) (mong 1)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-v41b
git -C "$R" branch -q -D feat-v41

# ── 3. Lượt FAIL trên cùng cây xoá scoped_receipts/<fp>.json; lượt dùng lại không hồi sinh mục đã xoá
add_wt wt-fail feat
touch "$TMP/wt-fail/.hong"
FLAKY_RETRY=0 run_scoped "$TMP/wt-fail" --no-cache
[ "$RC" = 1 ] && [ ! -e "$SSTORE/$FP0.json" ] \
  && ok "3. lượt FAIL trên cùng cây xoá mục scoped_receipts/<fp>.json" \
  && rm -f "$TMP/wt-fail/.hong" \
  || fail "3. sau FAIL: rc=$RC, file store còn=$([ -e "$SSTORE/$FP0.json" ] && echo yes || echo no)"
rm_wt wt-fail
add_wt wt-after-fail feat
b="$(snap)"; run_scoped "$TMP/wt-after-fail"; d="$(dlt "$b" "$(snap)")"
[ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ] \
  && ok "3. worktree mới sau FAIL: không còn biên nhận để mượn, chạy thật REG-K" \
  || fail "3. worktree mới sau FAIL không chạy REG-K: rc=$RC delta=$d"
rm_wt wt-after-fail

# ── 4. Race khoá (stale_reused): biên nhận scoped nguồn bị xoá sau khi đọc nhưng trước kết luận ⇒ exit 4 (STALE), không exit 0
git -C "$R" branch -q feat-race feat
git -C "$R" worktree add -q "$TMP/wt-r1" feat-race
echo 'n = 9' > "$TMP/wt-r1/src/n.py"
git -C "$TMP/wt-r1" commit -qam "race setup"
cat > "$TMP/m_race.json" <<JSON
{"project":"t","rules":[
  {"component":"A","watch_files":["src/a.py"],
   "mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"echo run >> '$TMP/count.A'; bash tests/test_a.sh"}]},
  {"component":"K","watch_files":["src/k.py","kit/*"],
   "mandatory_regression_tests":[{"id":"REG-K","name":"kit","command":"bash kit/tests/run_impacted.sh"}]},
  {"component":"N","watch_files":["src/n.py"],
   "mandatory_regression_tests":[{"id":"REG-RACE","name":"race","cache":false,
    "command":"if [ -f '$TMP/drop_now' ]; then rm -rf '$SSTORE'; elif [ -f '$TMP/rewrite_now' ]; then python3 -c 'import glob,json,os,sys,time\nfor p in glob.glob(sys.argv[1]+\"/*.json\"):\n d=json.load(open(p)); d[\"time\"]=time.time()\n open(p+\".tmp\",\"w\").write(json.dumps(d)); os.replace(p+\".tmp\",p)' '$SSTORE'; fi"}]}
]}
JSON
run_scoped "$TMP/wt-r1" --matrix "$TMP/m_race.json"
[ "$RC" = 0 ] && [ -n "$(store_file)" ] || fail "4. tiền đề tạo biên nhận race thất bại ($RC)"
rm_wt wt-r1

# ── 5a. Mục store bị ghi lại hợp lệ (stamp/inode đổi) trong lúc B đang giữ test_run.lock ⇒ kiểm lại thành công, KHÔNG exit 4 oan (AG2-P1, OCR2-H2)
touch "$TMP/rewrite_now"
add_wt wt-r5a feat-race
b="$(snap)"; run_scoped "$TMP/wt-r5a" --matrix "$TMP/m_race.json"; d="$(dlt "$b" "$(snap)")"
rm -f "$TMP/rewrite_now"
if [ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "0" ]; then
  ok "5a. mục store bị ghi lại hợp lệ khi đang giữ test_run.lock ⇒ stale_reused xác thực lại, exit 0 (không STALE oan)"
else
  fail "5a. ghi lại store hợp lệ bị STALE oan: rc=$RC delta=$d"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-r5a

touch "$TMP/drop_now"
add_wt wt-r2 feat-race
run_scoped "$TMP/wt-r2" --matrix "$TMP/m_race.json"
rm -f "$TMP/drop_now"
REPORT_R2="$(git -C "$TMP/wt-r2" rev-parse --absolute-git-dir)/postfix-gate/last_report.md"
if [ "$RC" = 4 ] && grep -q "STALE" "$REPORT_R2" 2>/dev/null; then
  ok "4. race khoá: biên nhận scoped bị xoá trước kết luận ⇒ trả exit 4 (STALE), không exit 0 giả"
else
  fail "4. race khoá: rc=$RC (mong 4 STALE)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-r2
git -C "$R" branch -q -D feat-race

# ── 4b. Lượt --scoped PASS bình thường khi store rỗng (OCR4-1): không UnboundLocalError, ghi đủ scoped_pass.json + mục store
wipe_scoped
rm -rf "$COMMON/postfix-gate/suite_cache"
add_wt wt-4b feat
run_scoped "$TMP/wt-4b"
SP_4B="$(git -C "$TMP/wt-4b" rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
if [ "$RC" = 0 ] && [ -f "$SP_4B" ] && [ -f "$SSTORE/$FP0.json" ] && ! printf '%s\n' "$OUT" | grep -q "UnboundLocalError"; then
  ok "4b. lượt --scoped PASS bình thường khi store rỗng: ghi đủ scoped_pass.json + mục store, không UnboundLocalError (OCR4-1)"
else
  fail "4b. store rỗng: rc=$RC sp=$([ -f "$SP_4B" ] && echo yes || echo no) store=$([ -f "$SSTORE/$FP0.json" ] && echo yes || echo no)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-4b

# ── 5b. Mục store xuất hiện lúc scratch đang giữ test_run.lock chờ gate slot ⇒ kiểm lại sau chờ slot vẫn mượn được (AG2-P1, OCR2-H2)
mv "$SSTORE/$FP0.json" "$TMP/saved_fp0.json"
rm -f "$TMP/slot_ready" "$TMP/release_slot"
env -u SB_HEAVY_SLOT_HELD -u DEVKIT_GATE_SLOT_HELD SB_HEAVY_SLOT_POLL_S=0.05 \
  python3 - "$DEVKIT_DIR/bin" "$TMP/slot_ready" "$TMP/release_slot" <<'PY' &
import os, sys, time
bin_dir, ready_f, rel_f = sys.argv[1:]
sys.path.insert(0, bin_dir)
import heavy_slot
h = heavy_slot.acquire_pool("gate", heavy_slot.pool_paths("gate", 1), wait_s=10.0, label="hold-5b")
open(ready_f, "w").write("1")
t0 = time.monotonic()
while not os.path.exists(rel_f) and time.monotonic() - t0 < 15.0:
    time.sleep(0.05)
heavy_slot.release_pool(h)
PY
HOLD_PID=$!
for _ in $(seq 1 100); do [ -f "$TMP/slot_ready" ] && break; sleep 0.05; done
add_wt wt-5b feat
b5b="$(snap)"
(
  cd "$TMP/wt-5b" && env -u SB_HEAVY_SLOT_HELD -u DEVKIT_GATE_SLOT_HELD \
    CLAUDE_PROJECT_DIR="$TMP/wt-5b" DEVKIT_GATE_SLOTS=1 SB_HEAVY_SLOT_POLL_S=0.05 \
    python3 "$GATE" --diff origin/main --run-tests --scoped --no-checklist --brief > "$TMP/wt5b.out" 2>&1
  echo $? > "$TMP/wt5b.rc"
) &
WT5B_PID=$!
for _ in $(seq 1 200); do [ -n "$(ls "$SB_HEAVY_SLOT_DIR/queue/gate" 2>/dev/null)" ] && break; sleep 0.05; done
mv "$TMP/saved_fp0.json" "$SSTORE/$FP0.json"
touch "$TMP/release_slot"
wait "$WT5B_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
d5b="$(dlt "$b5b" "$(snap)")"
RC5B="$(cat "$TMP/wt5b.rc" 2>/dev/null || echo 99)"
LOG5B="$(tail -1 "$RUNLOG" | python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print("%s|%s|%s" % (r.get("mode"), r.get("verdict"), r.get("reused_scoped","")))')"
if [ "$RC5B" = 0 ] && [ "$d5b" = "0 0 0 0" ] && [ "$LOG5B" = "scoped|REUSED|$FP0" ]; then
  ok "5b. mục store xuất hiện lúc B đang giữ test_run.lock chờ slot ⇒ kiểm lại sau slot vẫn dùng lại, 0 suite chạy ($LOG5B)"
else
  fail "5b. sau chờ slot không dùng lại được: rc=$RC5B delta=$d5b log=$LOG5B"; tail -20 "$TMP/wt5b.out" 2>/dev/null
fi
rm_wt wt-5b

# ── 5c. V4-3 (AG4-P1, AG3-P1-1): lượt PASS khác (A2) ghi lại mục store, suite B vừa mượn PASS (REG-A) giờ là UNTESTED/KEYED (A2 trúng
#    SuiteCache) ⇒ stale_reused tra khoá nội dung của REG-A; khoá còn trúng ⇒ giữ, exit 0 (không STALE oan), REG-A không chạy lại
cat > "$TMP/relabel.py" <<'PY'
import glob, json, os, sys, time
for p in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(p))
    for x in d.get("tests") or []:
        if x.get("id") == "REG-A":
            x.update(status="UNTESTED", label="KEYED")
    d["time"] = time.time()
    open(p + ".tmp", "w").write(json.dumps(d))
    os.replace(p + ".tmp", p)
PY
cat > "$TMP/m_rl.json" <<JSON
{"project":"t","rules":[
  {"component":"A","watch_files":["src/a.py"],
   "mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"echo run >> '$TMP/count.A'; bash tests/test_a.sh"}]},
  {"component":"K","watch_files":["src/k.py","kit/*"],
   "mandatory_regression_tests":[{"id":"REG-K","name":"kit","command":"bash kit/tests/run_impacted.sh"}]},
  {"component":"N","watch_files":["src/n.py"],
   "mandatory_regression_tests":[{"id":"REG-RL","name":"relabel","cache":false,
    "command":"if [ -f '$TMP/relabel_now' ]; then python3 '$TMP/relabel.py' '$SSTORE'; fi"}]}
]}
JSON
git -C "$R" branch -q feat-rl feat
git -C "$R" worktree add -q "$TMP/wt-rl1" feat-rl
echo 'n = 5' > "$TMP/wt-rl1/src/n.py"
git -C "$TMP/wt-rl1" commit -qam "relabel setup"
wipe_scoped
rm -rf "$COMMON/postfix-gate/suite_cache"
ab="$(cnt A)"
run_scoped "$TMP/wt-rl1" --matrix "$TMP/m_rl.json"
RL_A="$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["tests"]; print(next((x.get("status") for x in t if x["id"]=="REG-A"), "?"))' "$(store_file)" 2>/dev/null)"
if [ "$RC" = 0 ] && [ "$(cnt A)" -gt "$ab" ] && [ "$RL_A" = "PASS" ]; then
  ok "5c. tiền đề: A chạy thật REG-A (PASS trong mục store, khoá nội dung đã ghi vào SuiteCache)"
else
  fail "5c. tiền đề A: rc=$RC REG-A=$RL_A"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-rl1
touch "$TMP/relabel_now"
add_wt wt-rl2 feat-rl
b="$(snap)"; run_scoped "$TMP/wt-rl2" --matrix "$TMP/m_rl.json"; d="$(dlt "$b" "$(snap)")"
rm -f "$TMP/relabel_now"
if [ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $1, $2}')" = "0 0" ]; then
  ok "5c. mục store ghi lại với REG-A thành UNTESTED/KEYED, khoá nội dung còn trúng ⇒ giữ PASS theo khoá, exit 0 (V4-3)"
else
  fail "5c. relabel KEYED: rc=$RC delta=$d (mong rc=0, REG-A/REG-K 0 0)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-rl2
git -C "$R" branch -q -D feat-rl

# ── 6. AG5-P1b: runner run_impacted.sh (REG-K) không có KEYS ở lượt --scoped, nhưng FAIL của nó vào sổ khoá (F1). FAIL trên CÙNG khoá
#    mà mục store còn (mô phỏng stale_rerun.py chạy lại suite trên cây đó: ghi fail_n, không đụng scoped_receipts/) ⇒ scratch mới KHÔNG
#    được mượn PASS của REG-K. Khoá của run_impacted.sh phủ cả cây nên FAIL phải ở đúng cây đó; mục store được trả lại sau FAIL
wipe_scoped
rm -rf "$COMMON/postfix-gate/suite_cache"
git -C "$R" branch -q feat-6 feat
add_wt wt-6a feat-6
run_scoped "$TMP/wt-6a"
FP6="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.tree_fingerprint(sys.argv[2]))' "$DEVKIT_DIR/bin" "$TMP/wt-6a")"
[ "$RC" = 0 ] && [ -f "$SSTORE/$FP6.json" ] || fail "6. tiền đề wt-6a: rc=$RC store=$([ -f "$SSTORE/$FP6.json" ] && echo yes || echo no)"
rm_wt wt-6a
cp -p "$SSTORE/$FP6.json" "$TMP/saved_fp6.json"
add_wt wt-6c feat-6
touch "$TMP/wt-6c/.hong"
FLAKY_RETRY=0 run_scoped "$TMP/wt-6c" --no-cache
[ "$RC" = 1 ] || fail "6. tiền đề wt-6c: rc=$RC (mong 1: REG-K FAIL, ghi fail_n vào sổ khoá)"
rm -f "$TMP/wt-6c/.hong"
rm_wt wt-6c
mkdir -p "$SSTORE" && cp -p "$TMP/saved_fp6.json" "$SSTORE/$FP6.json"
add_wt wt-6b feat-6
b="$(snap)"; run_scoped "$TMP/wt-6b"; d="$(dlt "$b" "$(snap)")"
if [ "$RC" = 0 ] && [ "$(printf '%s' "$d" | awk '{print $2}')" = "1" ]; then
  ok "6. khoá REG-K đã có FAIL (sổ khoá) ⇒ scratch mới chạy thật REG-K, không mượn PASS từ store (AG5-P1b)"
else
  fail "6. mượn PASS của REG-K dù khoá đã FAIL: rc=$RC delta=$d (mong REG-K chạy 1 lần)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-6b
git -C "$R" branch -q -D feat-6

# ── 7. AG5-P1a: lượt --scoped chép PASS từ full_pass.json riêng (reuse_full_pass) là lượt mượn: không hồi sinh mục store mà một FAIL đã xoá
wipe_scoped
rm -rf "$COMMON/postfix-gate/suite_cache"
git -C "$R" branch -q feat-7 feat
git -C "$R" worktree add -q "$TMP/wt-7a" feat-7
(cd "$TMP/wt-7a" && CLAUDE_PROJECT_DIR="$TMP/wt-7a" python3 "$GATE" --diff origin/main --run-tests --full --no-checklist >/dev/null 2>&1)
FP7="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.tree_fingerprint(sys.argv[2]))' "$DEVKIT_DIR/bin" "$TMP/wt-7a")"
FULL7="$(git -C "$TMP/wt-7a" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
EXIT7="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("exit"))' "$FULL7" 2>/dev/null || echo NONE)"
[ "$EXIT7" = 0 ] || fail "7. tiền đề: --full ở wt-7a không ghi full_pass.json exit 0 ($EXIT7)"
rm -rf "$SSTORE"
add_wt wt-7c feat-7
touch "$TMP/wt-7c/.hong"
FLAKY_RETRY=0 run_scoped "$TMP/wt-7c" --no-cache
[ "$RC" = 1 ] && [ ! -e "$SSTORE/$FP7.json" ] || fail "7. tiền đề wt-7c FAIL: rc=$RC (mong 1, không còn mục store FP7)"
rm -f "$TMP/wt-7c/.hong"
rm_wt wt-7c
run_scoped "$TMP/wt-7a"
if [ "$RC" = 0 ] && [ ! -e "$SSTORE/$FP7.json" ]; then
  ok "7. --scoped dùng lại full_pass.json riêng (exit 0) không ghi lại mục store đã bị FAIL xoá (AG5-P1a)"
else
  fail "7. lượt chép full_pass.json đã hồi sinh mục store: rc=$RC store FP7=$([ -e "$SSTORE/$FP7.json" ] && echo yes || echo no)"; printf '%s\n' "$OUT" | tail -15
fi
rm_wt wt-7a
git -C "$R" branch -q -D feat-7

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_scoped_receipt_reuse"; exit 0; }
echo "FAIL: test_gate_scoped_receipt_reuse ($FAILS)"; exit 1
