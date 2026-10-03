#!/usr/bin/env bash
# The few game/Android guardrails that were missing. Skills from aitmpl stay out.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

grep -q 'Application.targetFrameRate' profiles/game/rules/game-rules.md \
  || fail "game-rules.md missing targetFrameRate"
grep -q 'OnApplicationPause' profiles/game/rules/game-rules.md \
  || fail "game-rules.md missing OnApplicationPause"
grep -q 'Cấm tuyệt đối `new`' profiles/game/rules/game-rules.md \
  || fail "game-rules.md missing the Update/FixedUpdate new ban"
grep -q 'Canvas_Static' profiles/game/rules/game-rules.md \
  && grep -q 'Canvas_Dynamic' profiles/game/rules/game-rules.md \
  || fail "game-rules.md missing the static/dynamic canvas split"
grep -q 'LazyColumn' profiles/android/rules/android-rules.md \
  || fail "android-rules.md missing LazyColumn"
grep -q 'derivedStateOf' profiles/android/rules/android-rules.md \
  || fail "android-rules.md missing derivedStateOf"
grep -q '24–32dp' profiles/android/DESIGN.md \
  || fail "android DESIGN.md missing the 24–32dp visual size"
grep -q '40%' profiles/android/DESIGN.md \
  || fail "android DESIGN.md missing the thumb-zone 40%"
grep -q 'Backend API' "$(git rev-parse --show-toplevel)/DESIGN.md" \
  || fail "repo DESIGN.md should stay the backend document"
for name in mobile-design game-development unity-game-developer kotlin-specialist android-cicd; do
  [ ! -e "skills/$name" ] || fail "vendored skill skills/$name must not be in the kit"
done
ok "missing game and android guardrails are in the profile rules"
