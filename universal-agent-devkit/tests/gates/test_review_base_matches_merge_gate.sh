#!/usr/bin/env bash
# Regression (BUG-REV base mismatch, 31/10): hooks/review_gate.sh ran review-fanout with --base verified while
# .claude/bin/super-board-merge-gate.sh looks the verdict up with --base merge-base(head, origin/<base>) -> two code hashes,
# the gate always saw NONE (exit 6). The hook must use --base merge-base, which must hash identically to the gate's SHA base.
set -u
HERE="$(cd "$(dirname "$0")/../.." && pwd)"; F="$HERE/bin/review-fanout.sh"; HOOK="$HERE/hooks/review_gate.sh"
pass=0; fail=0; ok() { echo "ok - $1"; pass=$((pass+1)); }; ko() { echo "FAIL - $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$HERE/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g init -q -b main "$T/up" && echo a > "$T/up/a.txt" && g -C "$T/up" add a.txt && g -C "$T/up" commit -qm init
g clone -q "$T/up" "$T/w" 2>/dev/null
echo b > "$T/up/b.txt" && g -C "$T/up" add b.txt && g -C "$T/up" commit -qm upstream-moves
g -C "$T/w" checkout -qb feat && echo c > "$T/w/c.py" && g -C "$T/w" add c.py && g -C "$T/w" commit -qm feat
g -C "$T/w" fetch -q origin
MB="$(git -C "$T/w" merge-base HEAD origin/main)"
h_kw="$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$T/w" --base merge-base --hash 2>/dev/null)"
h_sha="$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$T/w" --base "$MB" --hash 2>/dev/null)"
[ -n "$h_kw" ] && [ "$h_kw" = "$h_sha" ] && ok "--base merge-base hashes like the gate's merge-base SHA" || ko "hash mismatch kw=$h_kw sha=$h_sha"
h_head="$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$T/w" --base HEAD --hash 2>/dev/null)"
[ "$h_kw" != "$h_head" ] && ok "merge-base is not HEAD (covers the whole branch)" || ko "merge-base resolved to HEAD"
grep -q '^review_base = "merge-base"' "$HOOK" && ok "hook uses --base merge-base" || ko "hook review_base is not merge-base"
grep -q 'merge-base "\$HEAD_SHA" "\$BASE_SHA"' "$HERE/../.claude/bin/super-board-merge-gate.sh" && ok "gate still queries merge-base(head, origin/<base>)" || ko "gate base convention changed"
# no origin remote: falls back to the verified head instead of failing
g init -q -b main "$T/solo" && echo a > "$T/solo/a.txt" && g -C "$T/solo" add a.txt && g -C "$T/solo" commit -qm init
h_solo="$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$T/solo" --base merge-base --hash 2>/dev/null)"
[ -n "$h_solo" ] && ok "no origin: falls back (hash produced)" || ko "no origin: no hash"
echo "# $pass passed, $fail failed"; [ "$fail" -eq 0 ]
