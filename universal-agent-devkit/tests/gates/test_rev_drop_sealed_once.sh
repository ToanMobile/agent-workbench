#!/usr/bin/env bash
# #742 review 409a7296, BUG-REV 30f955ea7f (INSTINCT-098): `regression_checklist.py drop BUG-REV-<id> --refuted-by RUN_DIR`
# checked the HMAC seal on one read of summary.json (review_sign.verify) and took findings / meta.code_hash / meta.repo from a
# SECOND read. A writer in the run dir could keep the genuinely sealed FAIL in place while the seal was checked, then swap in a
# forged summary saying "refuted" (verifier.json is not sealed at all) and drop a blocking row no verifier refuted. The verdict
# must come from the very bytes the seal covers (review_sign.load_verified). The swap is made deterministic: a copy of the kit's
# bin/ whose review_sign._sealed_bytes replaces summary.json with the forged file right after its sealed read.
# Temp repo and a HOME of this test (its own review key): the real checklist is never touched.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_PROJECT_DIR
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

KIT="$TMP/kit"; mkdir -p "$KIT"; cp -R "$DEVKIT_DIR/bin" "$KIT/bin"
mv "$KIT/bin/review_sign.py" "$KIT/bin/review_sign_real.py"
cat > "$KIT/bin/review_sign.py" <<'PY'
# test double: the real review_sign, whose _sealed_bytes swaps summary.json for summary.json.forged right after the sealed read
import importlib.util, os, shutil
_sp = importlib.util.spec_from_file_location("review_sign_real", os.path.join(os.path.dirname(os.path.abspath(__file__)), "review_sign_real.py"))
_real = importlib.util.module_from_spec(_sp)
_sp.loader.exec_module(_real)
_orig = _real._sealed_bytes
def _swap(path):
    data = _orig(path)
    if data is not None and os.path.exists(path + ".forged"):
        shutil.copyfile(path + ".forged", path)
    return data
_real._sealed_bytes = _swap
globals().update({k: v for k, v in vars(_real).items() if not k.startswith("__")})
PY
RC="$KIT/bin/regression_checklist.py"

P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
H1=1111111111111111111111111111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222222222222222222222222222

# run RUN_DIR CODE_HASH CID SEALED_STATE [FORGED_STATE]: sealed summary (cluster CID in SEALED_STATE), verifier.json refuting CID,
# and — with FORGED_STATE — an unsealed summary.json.forged that the test double swaps in after the seal check
run() {
  mkdir -p "$1"
  python3 - "$1" "$P" "$2" "$3" "$4" "${5:-}" "$KIT/bin/review_sign_real.py" <<'PY'
import importlib.util, json, os, sys
run, repo, h, cid, sealed, forged, rs_path = sys.argv[1:8]
json.dump({"verifications": [{"id": cid, "refuted": True, "reason": "fixture"}]}, open(os.path.join(run, "verifier.json"), "w"))
def summary(state):
    return json.dumps({"verdict": "FAIL", "reasons": [], "meta": {"repo": repo, "base": "HEAD", "code_hash": h},
                       "findings": [{"id": cid, "severity": "P1", "state": state}]}).encode()
data = summary(sealed)
open(os.path.join(run, "summary.json"), "wb").write(data)
sp = importlib.util.spec_from_file_location("rs", rs_path); rs = importlib.util.module_from_spec(sp); sp.loader.exec_module(rs)
open(os.path.join(run, "summary.json.sig"), "w").write(rs._mac(rs.load_key(create=True), data) + "\n")
if forged:
    open(os.path.join(run, "summary.json.forged"), "wb").write(summary(forged))
PY
}
add_row() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$RC" --project "$P" add "[review P1] app.py:2 fixture $1" --id "REV-$1" \
  --severity P1 --module app.py --evidence "4-way review (claude)" >/dev/null 2>&1) || fail "fixture: could not add BUG-REV-$1"; }
has_row() { (cd "$P" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
sys.exit(0 if sys.argv[3] in rc.load_view(sys.argv[2])["items"] else 1)' "$KIT/bin" "$P" "BUG-REV-$1"); }
drop() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$RC" --project "$P" drop "BUG-REV-$1" --refuted-by "$2" >"$TMP/drop.out" 2>&1)
  echo $?; }

add_row a1a1a1a1a1; add_row b2b2b2b2b2
has_row a1a1a1a1a1 && has_row b2b2b2b2b2 || fail "fixture: rows missing"

# 1. sealed FAIL with the finding still blocking; a forged "refuted" summary is swapped in right after the seal check
run "$P/.git/review-fanout/$H1" "$H1" a1a1a1a1a1 blocking refuted
rc=$(drop a1a1a1a1a1 "$P/.git/review-fanout/$H1")
if [ "$rc" = 2 ] && has_row a1a1a1a1a1; then ok "summary swapped after the seal check: drop refused, row kept (verdict read from the sealed bytes)"
else fail "summary swapped after the seal check: drop rc=$rc, row $(has_row a1a1a1a1a1 && echo kept || echo GONE): $(tail -3 "$TMP/drop.out")"; fi
# 2. control: a genuinely sealed run whose verifier refuted the finding still drops the row (through the same test double)
run "$P/.git/review-fanout/$H2" "$H2" b2b2b2b2b2 refuted
rc=$(drop b2b2b2b2b2 "$P/.git/review-fanout/$H2")
if [ "$rc" = 0 ] && ! has_row b2b2b2b2b2; then ok "control: sealed refuted run drops the row"
else fail "control: drop rc=$rc, row $(has_row b2b2b2b2b2 && echo kept || echo gone): $(tail -3 "$TMP/drop.out")"; fi

[ "$FAILS" = 0 ] && { echo "test_rev_drop_sealed_once: PASS"; exit 0; }
echo "test_rev_drop_sealed_once: $FAILS FAILED"; exit 1
