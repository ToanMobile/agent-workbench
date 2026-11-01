#!/usr/bin/env bash
# review_sign.py seals a summary only inside the review-fanout folder of the repo's git common dir (review of #742 at 14108864,
# BUG-REV 8ec050fad4, r23c): sign() took any folder named review-fanout, e.g. /tmp/review-fanout/<H>/summary.json, so an agent could
# write meta.json (code_hash=H) and fake ok/pass envelopes there, run review-merge.py --dir on it and copy the sealed PASS into the
# real <git common dir>/review-fanout/<H>. DK_BIN overrides the bin dir (RED run).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${DK_BIN:-$DEVKIT_DIR/bin}"
S="$BIN/review_sign.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"   # the seal key of this test only
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
mkrepo() { mkdir -p "$1" && (cd "$1" && git init -q && git config user.email t@t && git config user.name t && echo x > README \
  && git add -A && git commit -qm i); }
P="$TMP/p"; Q="$TMP/q"; mkrepo "$P"; mkrepo "$Q"
git -C "$P" worktree add -q -b w "$TMP/w"
H="$(python3 -c 'import hashlib; print(hashlib.sha256(b"r23c").hexdigest())')"
# summary <run dir> [repo]: a PASS summary naming code state H (and repo, when given)
summary() { mkdir -p "$1"; rm -f "$1/summary.json.sig"; python3 - "$1/summary.json" "$H" "${2:-}" <<'PY'
import json, sys
meta = {"code_hash": sys.argv[2]}
if sys.argv[3]:
    meta["repo"] = sys.argv[3]
json.dump({"verdict": "PASS", "reasons": [], "meta": meta}, open(sys.argv[1], "w"))
PY
}
refused() {   # refused <label> <run dir> [env…]: sign exits non-zero and writes no seal
  local label="$1" d="$2"; shift 2
  env "$@" python3 "$S" sign "$d/summary.json" >/dev/null 2>&1; local rc=$?
  [ "$rc" != 0 ] && [ ! -e "$d/summary.json.sig" ] && ok "refused: $label" || fail "sealed: $label (rc=$rc)"
}
sealed() {
  local label="$1" d="$2"
  python3 "$S" sign "$d/summary.json" >/dev/null 2>&1; local rc=$?
  [ "$rc" = 0 ] && [ -s "$d/summary.json.sig" ] && ok "control, sealed: $label" || fail "control not sealed: $label (rc=$rc)"
}

summary "$TMP/review-fanout/$H" "$P";        refused "/tmp-style review-fanout/<H> outside any git dir, meta.repo = the repo" "$TMP/review-fanout/$H"
summary "$TMP/x/review-fanout/$H";           refused "review-fanout/<H> outside any git dir, no meta.repo" "$TMP/x/review-fanout/$H"
summary "$Q/.git/review-fanout/$H" "$P";     refused "under another repo's git dir than meta.repo names" "$Q/.git/review-fanout/$H"
summary "$Q/.git/review-fanout/$H" "$P";     refused "GIT_DIR pointing at that other git dir does not move the check" "$Q/.git/review-fanout/$H" "GIT_DIR=$Q/.git"
summary "$P/.git/review-fanout/$H/x" "$P";   refused "a folder below the run dir" "$P/.git/review-fanout/$H/x"
summary "$P/.git/review-fanout/$H" "$P";     sealed "the repo's own <git common dir>/review-fanout/<H>" "$P/.git/review-fanout/$H"
rm -rf "$P/.git/review-fanout"
summary "$P/.git/review-fanout/$H" "$TMP/w"; sealed "a linked worktree's run, kept in the common dir" "$P/.git/review-fanout/$H"
rm -rf "$P/.git/review-fanout"
summary "$P/.git/review-fanout/$H";          sealed "no meta.repo, inside a git common dir (the git dir that holds it)" "$P/.git/review-fanout/$H"

# end to end: review-merge.py finalising a hand-built run dir in /tmp leaves no sealed PASS to copy into the real one
R="$TMP/review-fanout/$H"; rm -rf "$R"; mkdir -p "$R"
python3 - "$R" "$H" "$P" <<'PY'
import json, os, sys
run, h, repo = sys.argv[1:4]
req = ["claude", "antigravity", "ocr", "registry"]
json.dump({"repo": repo, "base": "HEAD", "code_hash": h, "depth": "light", "files": ["README"], "untracked": [], "required": req,
           "skipped_by_override": ["grok"], "reduced": True, "changed_lines": 1, "models": {}}, open(os.path.join(run, "meta.json"), "w"))
for r in req:
    json.dump({"reviewer": r, "status": "ok", "verdict": "pass", "findings": [], "usage": {"tokens": 0, "usd": 0.0}},
              open(os.path.join(run, r + ".json"), "w"))
json.dump({"reviewer": "grok", "status": "skipped", "verdict": "skipped", "findings": []}, open(os.path.join(run, "grok.json"), "w"))
PY
(cd "$P" && python3 "$BIN/review-merge.py" --dir "$R" --repo "$P" >/dev/null 2>&1)
[ -f "$R/summary.json" ] && ok "fixture: review-merge.py wrote the hand-built run's summary" || fail "fixture: review-merge.py wrote no summary"
[ ! -e "$R/summary.json.sig" ] && ok "review-merge.py on a run dir outside the git dir: the summary is not sealed" \
  || fail "review-merge.py sealed a hand-built run dir in $R"

# a throwaway git repo's sealed summary copied into $P/.git/review-fanout/<H> is rejected too (meta.common_dir binding)
HP="$(bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash)"
RQ="$Q/.git/review-fanout/$HP"; rm -rf "$RQ"; mkdir -p "$RQ"
python3 - "$RQ" "$HP" "$Q" <<'PY'
import json, os, sys
run, h, repo = sys.argv[1:4]
req = ["claude", "antigravity", "grok", "ocr", "registry"]
json.dump({"repo": repo, "base": "HEAD", "code_hash": h, "depth": "light", "files": ["README"], "untracked": [], "required": req,
           "skipped_by_override": [], "reduced": False, "changed_lines": 1, "models": {}}, open(os.path.join(run, "meta.json"), "w"))
for r in req:
    m = {"claude": "claude-opus-4-5", "grok": "grok-4.7", "antigravity": "gemini-4-argon-high"}.get(r, "")
    json.dump({"reviewer": r, "status": "ok", "verdict": "pass", "findings": [], "model": m, "usage": {"tokens": 0, "usd": 0.0}},
              open(os.path.join(run, r + ".json"), "w"))
PY
(cd "$Q" && python3 "$BIN/review-merge.py" --dir "$RQ" --repo "$Q" >/dev/null 2>&1)
[ -s "$RQ/summary.json.sig" ] && ok "fixture: throwaway repo Q seals its own run" || fail "fixture: throwaway repo Q did not seal"
mkdir -p "$P/.git/review-fanout/$HP" && cp "$RQ/summary.json" "$RQ/summary.json.sig" "$RQ/summary.md" "$P/.git/review-fanout/$HP/"
st="$(bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --status 2>/dev/null | awk '{print $1}')"
[ "$st" != PASS ] && ok "throwaway git repo's sealed PASS copied into P is rejected (--status $st)" \
  || fail "throwaway git repo's sealed PASS answered PASS in P"
[ "$FAILS" = 0 ] && { echo "review sign run dir: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
