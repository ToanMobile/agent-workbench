#!/usr/bin/env bash
# Regression test (#515, from #462) for bin/agent-health.py: on 2026-10-24 a third-party installer wrote THROUGH the symlink
# .claude/hooks/guard-protected-push.py and put an old guard over the kit's own hooks/guard-protected-push.py; another file the kit tracks
# (scripts/testing/capture_3d_proof.py) was deleted. Health stayed green until `agent-kit integrate` broke. Health now compares the files
# the kit tracks with the kit's HEAD: one that differs or is gone is a red line naming the file and the restore command (printed, never run).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# A draft kit: the tracked files of this kit, committed in a repo of their own (HEAD = the clean state).
K="$TMP/kit"; mkdir -p "$K"
(cd "$DEVKIT_DIR" && git ls-files -z . | tar --null -T - -cf -) | tar -xf - -C "$K"
(cd "$K" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm kit)
W="$TMP/proj"; mkdir -p "$W" && (cd "$W" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
bash "$K/bin/install.sh" -t "$W" -a claude -p backend -y --no-githooks >/dev/null 2>&1

health() { python3 "$K/bin/agent-health.py" -t "$W" 2>&1 | strip; }
RED='kit files? .*(differ from|khác HEAD)'   # only the failing line carries it
LINK="$W/.claude/hooks/guard-protected-push.py"

[ -L "$LINK" ] || fail "setup: $LINK is not a symlink into the draft kit"

out="$(health)"
echo "$out" | grep -qE "$RED" && fail "a clean kit was reported: $(echo "$out" | grep -E "$RED")" || ok "clean kit: nothing reported"

# the 2026-10-24 shape: an old file written through the symlink
echo '# old guard' > "$LINK"
out="$(health)"
echo "$out" | grep -E "$RED" | grep -q 'hooks/guard-protected-push.py' && ok "overwrite through a symlink is named" \
  || fail "overwrite through the symlink not reported: $(echo "$out" | grep -E '⚠|✖' | head -5 | tr '\n' ' ')"
echo "$out" | grep -E "$RED" | grep -q 'git -C .* checkout -- hooks/guard-protected-push.py' && ok "the restore command is printed" \
  || fail "no restore command for the overwritten file"
echo "$out" | grep -qE '✖.*(differ from|khác HEAD)' && ok "the line is red (✖), not a warning" || fail "the overwrite line is not red"
[ "$(cd "$K" && git diff HEAD --name-only | wc -l | tr -d ' ')" = 1 ] && ok "health did not restore anything" || fail "health changed the kit"
(cd "$K" && git checkout -q -- hooks/guard-protected-push.py)

# the 24/10 deletion
rm -f "$K/scripts/testing/capture_3d_proof.py"
out="$(health)"
echo "$out" | grep -E "$RED" | grep -q 'scripts/testing/capture_3d_proof.py' && ok "a deleted kit file is named" \
  || fail "deleted kit file not reported: $(echo "$out" | grep -E '⚠|✖' | head -5 | tr '\n' ' ')"
(cd "$K" && git checkout -q -- scripts/testing/capture_3d_proof.py)

# #828: `git commit -- <path>` runs the pre-commit on a TEMP index (GIT_INDEX_FILE=$GIT_DIR/next-index-*.lock) that holds the commit's own
# work; the real index lacks it, so a kit file being committed looked "overwritten" and health REJECTed the commit. The pre-commit hands
# that index to health as DEVKIT_PRECOMMIT_INDEX (a name suite_env keeps): files it stages are the developer's own work.
echo '# edited by the developer' >> "$K/scripts/testing/capture_3d_proof.py"
echo '# stray edit outside the commit' >> "$K/hooks/guard-protected-push.py"
GD="$(cd "$K" && git rev-parse --absolute-git-dir)"
TMPIDX="$GD/next-index-828.lock"
(cd "$K" && cp "$GD/index" "$TMPIDX" && GIT_INDEX_FILE="$TMPIDX" git add scripts/testing/capture_3d_proof.py)
out="$(DEVKIT_PRECOMMIT_INDEX="$TMPIDX" health)"
echo "$out" | grep -E "$RED" | grep -q 'capture_3d_proof.py' && fail "a kit file staged in the commit's temp index is reported (#828)" \
  || ok "pathspec commit: the file being committed is not reported (#828)"
echo "$out" | grep -E "$RED" | grep -q 'hooks/guard-protected-push.py' && ok "a kit file outside the commit still goes red (#462 kept)" \
  || fail "the stray edit outside the commit is no longer reported"
out="$(DEVKIT_PRECOMMIT_INDEX="$TMP/elsewhere/x.lock" health)"
echo "$out" | grep -E "$RED" | grep -q 'capture_3d_proof.py' && ok "an index path outside this kit's git dir is ignored" \
  || fail "an index path outside this kit's git dir was trusted"
# R1: a missing index path, or a symlink to one inside the git dir, must not hide the stray edit (#462 kept)
out="$(DEVKIT_PRECOMMIT_INDEX="$GD/no-such-index.lock" health)"
echo "$out" | grep -E "$RED" | grep -q 'hooks/guard-protected-push.py' && ok "a missing temp index is ignored (R1)" \
  || fail "a missing temp index hid the stray edit (R1)"
ln -s "$GD/index" "$GD/next-index-link.lock"
out="$(DEVKIT_PRECOMMIT_INDEX="$GD/next-index-link.lock" health)"
echo "$out" | grep -E "$RED" | grep -q 'capture_3d_proof.py' && ok "a symlinked temp index is ignored (R1)" \
  || fail "a symlinked temp index was trusted (R1)"
rm -f "$GD/next-index-link.lock"
# R3: the pre-commit hook clears an inherited value before exporting its own
grep -q 'unset DEVKIT_PRECOMMIT_INDEX' "$K/scripts/git/git-pre-commit.sh" && ok "pre-commit clears an inherited DEVKIT_PRECOMMIT_INDEX (R3)" \
  || fail "pre-commit keeps an inherited DEVKIT_PRECOMMIT_INDEX (R3)"
rm -f "$TMPIDX"
(cd "$K" && git checkout -q -- scripts/testing/capture_3d_proof.py hooks/guard-protected-push.py)

# R2: a REAL `git commit -- <path>` through the real hook. A second kit copy K2 has post-fix-gate swapped for a stub that does what
# suite_env does (drops GIT_INDEX_FILE, keeps DEVKIT_PRECOMMIT_INDEX) and runs health; deleting the export in git-pre-commit.sh turns this red.
K2="$TMP/kit2"; mkdir -p "$K2"
(cd "$DEVKIT_DIR" && git ls-files -z . | tar --null -T - -cf -) | tar -xf - -C "$K2"
cat > "$K2/bin/post-fix-gate.py" <<'STUB'
#!/usr/bin/env python3
import json, os, subprocess, sys

def load_active_matrix():  # agent-health imports this file (module name "pfg") to read the matrix: answer, never recurse
    return {"rules": []}, ""

if __name__ == "__main__":  # without this guard the import above re-ran the body: agent-health -> stub -> agent-health ... a fork bomb
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent-health.py"), "-t", os.environ["HEALTH_TARGET"]],
                         capture_output=True, text=True, env=env, timeout=120).stdout
    open(os.environ["HEALTH_OUT"], "w").write(out)
    print(json.dumps({"mode": "staged", "static_ok": True, "tests_ok": True}))
    sys.exit(2)
STUB
(cd "$K2" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm kit --no-verify)
printf '#!/bin/sh\nexec bash "%s/scripts/git/git-pre-commit.sh"\n' "$K2" > "$K2/.git/hooks/pre-commit"; chmod +x "$K2/.git/hooks/pre-commit"
echo '# committed via pathspec' >> "$K2/scripts/testing/capture_3d_proof.py"
echo '# stray edit outside the commit' >> "$K2/hooks/guard-protected-push.py"
HEALTH_TARGET="$W" HEALTH_OUT="$TMP/h2.txt" git -C "$K2" commit -q -m pathspec -- scripts/testing/capture_3d_proof.py >"$TMP/c2.txt" 2>&1
rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/h2.txt" ] || fail "setup: the pathspec commit did not reach health (rc=$rc): $(tail -3 "$TMP/c2.txt" | tr '\n' ' ')"
strip < "$TMP/h2.txt" | grep -E "$RED" | grep -q 'capture_3d_proof.py' && fail "real pathspec commit: the committed kit file was reported (R2)" \
  || ok "real pathspec commit: the committed kit file is not reported (R2)"
strip < "$TMP/h2.txt" | grep -E "$RED" | grep -q 'hooks/guard-protected-push.py' && ok "real pathspec commit: the stray edit still goes red (R2, #462 kept)" \
  || fail "real pathspec commit: the stray edit was hidden (R2)"

out="$(health)"
echo "$out" | grep -qE "$RED" && fail "a restored kit is still reported" || ok "restored kit: nothing reported"

[ "$FAILS" -eq 0 ] && echo "✅ test_agent_health_kit_overwritten: all passed" || { echo "❌ test_agent_health_kit_overwritten: $FAILS failed"; exit 1; }
