#!/usr/bin/env bash
# card #756 F10 — `regression_checklist.py drop BUG-REV-<id> --refuted-by RUN_DIR` accepted ANY run dir with a valid HMAC seal,
# and the seal key (~/.config/agent-workbench/review.key) is one per machine, shared by every repo: a sealed "refuted" summary of
# another repo (or a throwaway temp repo) with the same cluster id dropped this project's blocking row. A run counts only when it
# sits in THIS project's <git-common-dir>/review-fanout/<meta.code_hash>/ and its meta.repo is this repo or a worktree of it.
# Temp repos only, with a HOME of this test (its own review key): the real checklist is never touched.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_PROJECT_DIR
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
RC="$DEVKIT_DIR/bin/regression_checklist.py"

mkrepo() { mkdir -p "$1/.agents" && (cd "$1" && git init -q && git config user.email t@t && git config user.name t \
  && echo x > README && git add -A && git commit -qm i); }
P="$TMP/p"; Q="$TMP/q"; mkrepo "$P"; mkrepo "$Q"
WT="$TMP/p-wt"; git -C "$P" worktree add -q --detach "$WT" HEAD

# seal_run RUN_DIR META_REPO CODE_HASH CID — a review run whose verifier refuted cluster CID, sealed with this test's key
seal_run() {
  mkdir -p "$1"
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, os, sys
run, repo, code_hash, cid = sys.argv[1:5]
with open(os.path.join(run, "verifier.json"), "w", encoding="utf-8") as fh:
    json.dump({"verifications": [{"id": cid, "refuted": True, "reason": "fixture"}]}, fh)
with open(os.path.join(run, "summary.json"), "w", encoding="utf-8") as fh:
    json.dump({"verdict": "FAIL", "reasons": [], "meta": {"repo": repo, "base": "HEAD", "code_hash": code_hash},
               "findings": [{"id": cid, "severity": "P1", "state": "refuted"}]}, fh)
PY
  # sealed with the key directly (review_sign.sign itself now refuses a mismatched code_hash: case 3 is a seal made elsewhere)
  python3 - "$DEVKIT_DIR/bin/review_sign.py" "$1/summary.json" <<'PY' || fail "fixture: could not seal $1"
import importlib.util, sys
sp = importlib.util.spec_from_file_location("rs", sys.argv[1]); rs = importlib.util.module_from_spec(sp); sp.loader.exec_module(rs)
data = open(sys.argv[2], "rb").read()
open(sys.argv[2] + ".sig", "w").write(rs._mac(rs.load_key(create=True), data) + "\n")
PY
}
add_row() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$RC" --project "$P" add "[review P1] app.py:2 fixture $1" --id "REV-$1" \
  --severity P1 --module app.py --evidence "4-way review (claude)" >/dev/null 2>&1) || fail "fixture: could not add BUG-REV-$1"; }
has_row() { (cd "$P" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
sys.exit(0 if sys.argv[3] in rc.load_view(sys.argv[2])["items"] else 1)' "$DEVKIT_DIR/bin" "$P" "BUG-REV-$1"); }
drop() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$RC" --project "$P" drop "BUG-REV-$1" --refuted-by "$2" >"$TMP/drop.out" 2>&1)
  echo $?; }
refused() {   # refused CID RUN_DIR WHAT
  local rc; rc=$(drop "$1" "$2")
  if [ "$rc" = 2 ] && has_row "$1"; then ok "$3 → drop refused, row kept"
  else fail "$3 → drop rc=$rc, row $(has_row "$1" && echo kept || echo GONE): $(tail -3 "$TMP/drop.out")"; fi
}
allowed() {   # allowed CID RUN_DIR WHAT
  local rc; rc=$(drop "$1" "$2")
  if [ "$rc" = 0 ] && ! has_row "$1"; then ok "$3 → dropped"
  else fail "$3 → drop rc=$rc, row $(has_row "$1" && echo kept || echo gone): $(tail -3 "$TMP/drop.out")"; fi
}

for c in a1a1a1a1a1 b2b2b2b2b2 c3c3c3c3c3 d4d4d4d4d4 e5e5e5e5e5; do add_row "$c"; done
for c in a1a1a1a1a1 b2b2b2b2b2 c3c3c3c3c3 d4d4d4d4d4 e5e5e5e5e5; do has_row "$c" || fail "fixture: BUG-REV-$c missing"; done
H1=1111111111111111111111111111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222222222222222222222222222
H3=3333333333333333333333333333333333333333333333333333333333333333
H4=4444444444444444444444444444444444444444444444444444444444444444
H5=5555555555555555555555555555555555555555555555555555555555555555
H6=6666666666666666666666666666666666666666666666666666666666666666

# 1. a sealed refuted run of ANOTHER repo (its own review-fanout, its own meta) — same machine key, same cluster id
seal_run "$Q/.git/review-fanout/$H1" "$Q" "$H1" a1a1a1a1a1
refused a1a1a1a1a1 "$Q/.git/review-fanout/$H1" "sealed run in another repo's review-fanout (BUG-REV-rev-drop-foreign-run)"
# 2. that foreign summary copied into this project's review-fanout: the location fits, meta.repo is still the other repo
seal_run "$P/.git/review-fanout/$H2" "$Q" "$H2" b2b2b2b2b2
refused b2b2b2b2b2 "$P/.git/review-fanout/$H2" "own review-fanout but meta.repo is another repo"
# 3. a run dir whose name is not the summary's code hash
seal_run "$P/.git/review-fanout/$H3" "$P" "$H4" c3c3c3c3c3
refused c3c3c3c3c3 "$P/.git/review-fanout/$H3" "run dir name != meta.code_hash"
# 4. a review run in a linked worktree of the project (meta.repo = that worktree; review-fanout is shared via the common dir)
seal_run "$P/.git/review-fanout/$H5" "$WT" "$H5" d4d4d4d4d4
allowed d4d4d4d4d4 "$P/.git/review-fanout/$H5" "own run, meta.repo = a linked worktree of the project"
# 5. the project's own run, meta.repo = the project
seal_run "$P/.git/review-fanout/$H6" "$P" "$H6" e5e5e5e5e5
allowed e5e5e5e5e5 "$P/.git/review-fanout/$H6" "own run, meta.repo = the project"

[ "$FAILS" = 0 ] && { echo "test_rev_drop_foreign_run: PASS"; exit 0; }
echo "test_rev_drop_foreign_run: $FAILS FAILED"; exit 1
