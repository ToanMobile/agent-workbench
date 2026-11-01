# shellcheck shell=bash
# Shared fixture (31/10/2026): the merge gate now requires a signed 4-way review PASS for the PR head (review-fanout.sh --status /
# --verify-summary, base = merge-base(head, origin/<base>)) and readable CI checks (gh pr checks, gh api branch protection).
# Older merge-gate / merge-train tests predate that; this fixture supplies ONLY those preconditions and leaves every assert alone:
#   sb_review_fixture <fake-bin-dir>   (call after the test's fake gh is written and chmod'ed)
# It wraps that fake gh: `gh pr checks` → one passing check, `gh api …/branches/…|…/rules/branches/…` → no required checks (answered by the
# fixture itself, the test's gh never sees them), and every headRefOid the test's gh reports gets a signed light PASS seeded into the repo's
# review-fanout run dir (code hash computed by the real review-fanout.sh --hash on a clean checkout of that head).
# The HMAC key lives in an isolated HOME ($SB_REVIEW_FIXTURE_HOME), never in the user's ~/.config.
sb_review_fixture() {
  local bin="$1" dk
  dk="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../universal-agent-devkit/bin" && pwd -P)"
  [ -x "$bin/gh" ] || { echo "sb_review_fixture: no fake gh in $bin" >&2; return 1; }
  if [ -z "${SB_REVIEW_FIXTURE_HOME:-}" ]; then
    export SB_REVIEW_FIXTURE_HOME="$(cd "$bin/.." && pwd -P)/sb-review-home"
  fi
  mkdir -p "$SB_REVIEW_FIXTURE_HOME"; export HOME="$SB_REVIEW_FIXTURE_HOME"
  export SB_REVIEW_FIXTURE_DK="$dk"
  # the test may rewrite its fake gh later and call this again: the newest fake becomes the inner one (never wrap the wrapper)
  grep -q "^# sb-review-fixture wrapper" "$bin/gh" 2>/dev/null || mv -f "$bin/gh" "$bin/gh.sb-inner"
  cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
# sb-review-fixture wrapper
inner="$(dirname "$0")/gh.sb-inner"
seed() {   # seed <head sha>: signed light PASS for merge-base(head, origin/<base>) in the repo the gate runs gh from
  local sha="$1" common tmp mb h run base="${SB_REVIEW_FIXTURE_BASE:-main}" cands c
  common=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
  common=$(cd "$common" && pwd -P)
  git cat-file -e "$sha^{commit}" 2>/dev/null || return 0
  cands=$(git rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null; git ls-remote origin "refs/heads/$base" 2>/dev/null | cut -f1)
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/sb-review-fixture.XXXXXX")
  git clone -q --shared --no-checkout "$common" "$tmp/c" 2>/dev/null && git -C "$tmp/c" -c advice.detachedHead=false checkout -q --detach "$sha" 2>/dev/null || { rm -rf "$tmp"; return 0; }
  for c in $(printf '%s\n' $cands | sort -u); do
    git -C "$tmp/c" cat-file -e "$c^{commit}" 2>/dev/null || continue
    mb=$(git -C "$tmp/c" merge-base "$sha" "$c" 2>/dev/null) || continue
    h=$(cd "$tmp/c" && env -u REVIEW_SKIP_REVIEWERS -u REVIEW_CLAUDE_MODEL -u REVIEW_GROK_MODEL -u REVIEW_AGY_MODEL \
        -u REVIEW_CLAUDE_BIN -u REVIEW_GROK_BIN -u REVIEW_AGY_CLI -u REVIEW_DEEP_LINES -u REVIEW_REGRESSION_STATUS \
        bash "$SB_REVIEW_FIXTURE_DK/review-fanout.sh" --repo "$tmp/c" --base "$mb" --hash 2>/dev/null) || continue
    [ -n "$h" ] || continue
    run="$common/review-fanout/$h"
    [ -s "$run/summary.json.sig" ] && continue
    mkdir -p "$run"
    python3 - "$run/summary.json" "$h" <<'PY'
import json, sys
req = ["claude", "antigravity", "grok", "ocr", "registry"]
json.dump({"verdict": "PASS", "reasons": [], "meta": {"code_hash": sys.argv[2], "depth": "light", "required": req},
           "reviewers": {r: {"status": "ok", "verdict": "pass"} for r in req}, "reduced": False, "skipped_by_override": []},
          open(sys.argv[1], "w"), indent=1)
PY
    python3 "$SB_REVIEW_FIXTURE_DK/review_sign.py" sign "$run/summary.json" >/dev/null 2>&1
  done
  rm -rf "$tmp"
}
case " $* " in
  " api "*/branches/*)   # branch protection / rulesets: answered here (old fakes never knew these endpoints)
    path=$2; jqx=""
    while [ $# -gt 0 ]; do [ "$1" = --jq ] && jqx=$2; shift; done
    case "$path" in
      */rules/branches/*) body='[]' ;;
      */branches/*) body='{"protected":false,"protection":{"enabled":false,"required_status_checks":{"enforcement_level":"off","contexts":[],"checks":[]}}}' ;;
      *) exec "$inner" api "$path" ;;
    esac
    if [ -n "$jqx" ]; then printf '%s' "$body" | jq -r "$jqx"; else printf '%s\n' "$body"; fi
    exit 0 ;;
  *" pr checks "*)
    echo '[{"name":"ci/test","state":"SUCCESS","bucket":"pass"}]'; exit 0 ;;
  *" pr view "*headRefOid*|*" pr list "*headRefOid*)
    out=$("$inner" "$@"); rc=$?
    for s in $(printf '%s\n' "$out" | grep -oE '[0-9a-f]{40}' | sort -u); do seed "$s"; done
    printf '%s\n' "$out"; exit $rc ;;
  *) exec "$inner" "$@" ;;
esac
SH
  chmod +x "$bin/gh"
}
