#!/usr/bin/env bash
# Regression test: EN/VI output language (P2-4), web/backend profiles (P2-5) and
# profile-based skill filtering (P1-5). Installs only into temp projects.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$DEVKIT_DIR/bin/install.sh"
CFG="$DEVKIT_DIR/bin/agent-config.py"
HEALTH="$DEVKIT_DIR/bin/agent-health.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset DEVKIT_LANG CLAUDE_PROJECT_DIR TARGET_DIR
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Vietnamese letters with diacritics — English output must contain none.
VI='[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ]'
# has_vi <file>: exit 0 when the file holds one of $VI, printing up to 3 such lines. Matched as characters in python: grep reads a
# multibyte bracket class BYTE by byte under a POSIX locale (Linux CI, LANG unset), so "═" (E2 95 90) matched "Ố" (E1 BB 90).
has_vi() {
  python3 -c 'import re,sys
rx = re.compile(sys.argv[1])
hits = ["%d:%s" % (i, l.rstrip("\n")) for i, l in enumerate(open(sys.argv[2], encoding="utf-8", errors="replace"), 1) if rx.search(l)]
print(" ".join(hits[:3]))
sys.exit(0 if hits else 1)' "$VI" "$1"
}
no_vi() { # <label> <file>
  local hits
  if hits="$(has_vi "$2")"; then fail "$1 (Vietnamese left: $hits)"; else ok "$1"; fi
}

newproj() { # <name> <marker-file> [content]
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q
  [ -n "${2:-}" ] && printf '%s\n' "${3:-}" > "$d/$2"
  printf '%s' "$d"
}
install_q() { bash "$INSTALL" "$@" </dev/null >"$TMP/out" 2>&1; }

# ---------------------------------------------------------------- P2-4 i18n
P="$(newproj node package.json '{"name":"x","scripts":{"test":"echo ok"}}')"
install_q -t "$P" -y --lang=en; rc=$?
[ "$rc" = 0 ] && ok "install --lang=en exits 0" || { fail "install --lang=en: rc=$rc"; tail -5 "$TMP/out"; }
no_vi "install --lang=en: no Vietnamese in installer/adapter/profile output" "$TMP/out"
grep -q '"lang": "en"' "$P/.agents/active-profile.json" && ok "--lang=en saved in .agents/active-profile.json" || fail "lang not saved"

python3 "$CFG" --status -t "$P" >"$TMP/out" 2>&1
no_vi "agent-config reuses the saved language (no --lang, no DEVKIT_LANG)" "$TMP/out"
DEVKIT_LANG=en python3 "$CFG" -p universal -t "$TMP/cfg_en" >"$TMP/out" 2>&1
no_vi "DEVKIT_LANG=en agent-config output is English" "$TMP/out"
python3 "$CFG" -p universal -t "$TMP/cfg_en" >"$TMP/out" 2>&1
no_vi "default language without config is English" "$TMP/out"
python3 "$CFG" -p universal -t "$TMP/cfg_vi" --lang vi >"$TMP/out" 2>&1
has_vi "$TMP/out" >/dev/null && ok "--lang vi produces Vietnamese output" || fail "--lang vi does not output vi"
python3 "$CFG" -p universal -t "$TMP/cfg_vi" --lang en >"$TMP/out" 2>&1
no_vi "--lang beats the saved language" "$TMP/out"

python3 "$HEALTH" -t "$P" --lang en >"$TMP/out" 2>&1
no_vi "agent-health --lang en output is English" "$TMP/out"

G="$(newproj gate)"
mkdir -p "$G/src" && echo 'fun a() = 1' > "$G/src/A.kt" && git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -qm base
printf 'fun a() {\n  try { x() } catch (e: Exception) {}\n  Thread.sleep(5)\n}\n' > "$G/src/A.kt"
(cd "$G" && DEVKIT_LANG=en python3 "$GATE" --allow-no-tests >"$TMP/out" 2>&1)
no_vi "DEVKIT_LANG=en post-fix-gate output (with findings) is English" "$TMP/out"
grep -q "REJECT" "$TMP/out" && ok "English gate still REJECTs the findings" || fail "English gate verdict changed"

# ---------------------------------------------------------------- P2-5 web/backend profiles
for p in web backend; do
  d="$DEVKIT_DIR/profiles/$p"
  if [ -f "$d/profile.json" ] && [ -f "$d/DESIGN.md" ] && [ -f "$d/instincts.md" ] && [ -f "$d/regression_matrix.json" ] \
     && [ -f "$DEVKIT_DIR/$(python3 -c "import json;print(json.load(open('$d/profile.json'))['rules_file'])")" ] \
     && [ -e "$DEVKIT_DIR/rules/$p-rules.md" ]; then
    ok "profile $p ships profile.json, rules, DESIGN.md, instincts.md, matrix"
  else
    fail "profile $p is missing standard artefacts"
  fi
done
install_q -t "$(newproj node2 package.json '{}')" -y; grep -Eq "Profile: +web" "$TMP/out" && ok "-y on a package.json project selects web" || fail "-y package.json: $(grep 'Profile:' "$TMP/out")"
install_q -t "$(newproj go go.mod 'module x')" -y; grep -Eq "Profile: +backend" "$TMP/out" && ok "-y on a go.mod project selects backend" || fail "-y go.mod: $(grep 'Profile:' "$TMP/out")"
install_q -t "$(newproj py pyproject.toml '[project]')" -y; grep -Eq "Profile: +backend" "$TMP/out" && ok "-y on a pyproject project selects backend" || fail "-y pyproject: $(grep 'Profile:' "$TMP/out")"
for alias in web frontend 7 backend api 8; do
  python3 "$CFG" -p "$alias" -t "$TMP/alias_$alias" >/dev/null 2>&1 && ok "agent-config accepts '$alias'" || fail "agent-config rejects '$alias'"
done

# Matrix runner detection fails closed when no runner is present.
B="$(newproj be_empty)"
cmd="$(python3 -c "import json;print(json.load(open('$DEVKIT_DIR/profiles/backend/regression_matrix.json'))['rules'][0]['mandatory_regression_tests'][0]['command'])")"
(cd "$B" && bash -c "$cmd" >/dev/null 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "backend matrix: no runner detected -> FAIL (exit $rc), never a silent PASS" || fail "backend matrix passes without a runner"
W="$(newproj web_empty)"
cmd="$(python3 -c "import json;print(json.load(open('$DEVKIT_DIR/profiles/web/regression_matrix.json'))['rules'][0]['mandatory_regression_tests'][0]['command'])")"
(cd "$W" && bash -c "$cmd" >/dev/null 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "web matrix: no package.json -> FAIL (exit $rc)" || fail "web matrix passes without package.json"

# ---------------------------------------------------------------- P1-5 skill filter
ANDROID_ONLY="android-real-device-qa compose-recomp-audit deploy unity-gc-audit"
ANDROID_CMDS="android-qa.md android-real-device-qa.md build.md deploy.md gc-audit.md recomp-audit.md compose-recomp-audit.md unity-gc-audit.md"
for mode in symlink copy; do
  U="$(newproj "u_$mode" package.json '{}')"
  install_q -t "$U" -a claude,gemini -p universal -m "$mode"
  bad=""; for s in $ANDROID_ONLY; do [ -e "$U/.agents/skills/$s" ] && bad="$bad $s"; done
  [ -z "$bad" ] && ok "universal ($mode): no Android/Unity skills in .agents/skills" || fail "universal ($mode): installed$bad"
  bad=""; for c in $ANDROID_CMDS; do [ -e "$U/.claude/commands/$c" ] && bad="$bad $c"; done
  [ -z "$bad" ] && ok "universal ($mode): no Android/Unity commands in .claude/commands" || fail "universal ($mode): commands$bad"
  [ -e "$U/.agents/skills/qc" ] && [ -e "$U/.claude/commands/fix.md" ] && ok "universal ($mode): general skills/commands still installed" || fail "universal ($mode): general skills missing"
done

A="$(newproj android build.gradle '')"
install_q -t "$A" -a claude,gemini -p android
miss=""; for s in android-real-device-qa compose-recomp-audit deploy; do [ -e "$A/.agents/skills/$s" ] || miss="$miss $s"; done
[ -z "$miss" ] && ok "android: every Android skill installed" || fail "android: missing$miss"
[ ! -e "$A/.agents/skills/unity-gc-audit" ] && ok "android: game-only skill unity-gc-audit not installed (apps never get game skills)" || fail "android: unity-gc-audit leaked into an app profile"
[ -e "$A/.claude/commands/deploy.md" ] && ok "android: /deploy command installed" || fail "android: /deploy missing"

# Agent Sprite Forge (vendored, MIT): 2D art skills. Neither android nor game installs them (game: Blender 3D is the only asset source, 15/10).
SPRITE_FORGE="generate2dmedia generate2dsprite video2dsprite"
leak=""; for s in $SPRITE_FORGE; do { [ -e "$A/.agents/skills/$s" ] || [ -L "$A/.agents/skills/$s" ]; } && leak="$leak $s"; done
[ -z "$leak" ] && ok "android: no Sprite Forge skills" || fail "android: Sprite Forge leaked:$leak"
G="$(newproj game_sf package.json '{}')"
install_q -t "$G" -a claude,gemini -p game
[ -e "$G/.agents/skills/unity-gc-audit" ] && ok "game: the install ran (unity-gc-audit is there)" || fail "game: the install produced no unity-gc-audit, the absence check below proves nothing"
leak=""; for s in $SPRITE_FORGE; do { [ -e "$G/.agents/skills/$s" ] || [ -L "$G/.agents/skills/$s" ]; } && leak="$leak $s"; done
[ -z "$leak" ] && ok "game: no Sprite Forge skills (Blender 3D is the only asset source)" || fail "game: Sprite Forge installed:$leak"
# a project installed before 15/10 still has the three skills linked: the next install of the profile removes them
planted=""; for s in $SPRITE_FORGE; do ln -s "$DEVKIT_DIR/skills/$s" "$G/.agents/skills/$s" 2>/dev/null && [ -L "$G/.agents/skills/$s" ] && planted="$planted $s"; done
[ "$planted" = " $SPRITE_FORGE" ] && ok "game: the three stale Sprite Forge links were planted" || fail "game: could not plant the stale links (planted:$planted), the re-install check below proves nothing"
install_q -t "$G" -a claude,gemini -p game
leak=""; for s in $SPRITE_FORGE; do { [ -e "$G/.agents/skills/$s" ] || [ -L "$G/.agents/skills/$s" ]; } && leak="$leak $s"; done
[ -z "$leak" ] && ok "game: re-installing over a project that already had the Sprite Forge skills removes them" || fail "game: re-install left Sprite Forge skills:$leak"
# DevKit billing rule (vendor patch 2, 13/10 security review): upstream says a configured API key is the owner's consent to spend, with
# no per-call question; under the DevKit billing needs the user's go-ahead. No vendored text may keep that claim, and generate2dmedia
# names the approval step (dry run, estimate, yes, then a budget cap).
consent="$(grep -rlE "owner's consent|key is consent|no per-call question" $(for s in $SPRITE_FORGE; do printf '%s ' "$DEVKIT_DIR/skills/$s"; done) 2>/dev/null)"
[ -z "$consent" ] && ok "Sprite Forge: no vendored text treats a configured key as consent to spend" \
  || fail "Sprite Forge: key-is-consent text left in:$(printf ' %s' $consent | sed "s|$DEVKIT_DIR/skills/||g")"
grep -q -- '--dry-run' "$DEVKIT_DIR/skills/generate2dmedia/SKILL.md" && grep -q -- '--budget-usd' "$DEVKIT_DIR/skills/generate2dmedia/SKILL.md" \
  && grep -q 'Paid calls (DevKit' "$DEVKIT_DIR/skills/generate2dmedia/SKILL.md" \
  && ok "generate2dmedia: paid calls need the user's yes after a dry run, then a budget cap" || fail "generate2dmedia: no DevKit paid-call approval step"

# Switching the project to a profile that excludes skills removes only DevKit items.
echo "my own deploy notes" > "$TMP/mine.md"
rm -f "$A/.claude/commands/build.md" && cp "$TMP/mine.md" "$A/.claude/commands/build.md"
install_q -t "$A" -a claude,gemini -p web
[ ! -e "$A/.agents/skills/deploy" ] && [ ! -e "$A/.claude/commands/deploy.md" ] && ok "android -> web: DevKit Android links removed" || fail "android -> web: Android links left behind"
grep -qx "my own deploy notes" "$A/.claude/commands/build.md" 2>/dev/null && ok "android -> web: user's own build.md kept" || fail "android -> web: user's build.md removed"

# Every profile lists only existing skills.
for d in "$DEVKIT_DIR"/profiles/*/; do
  p="$(basename "$d")"
  _ps_script="$DEVKIT_DIR/scripts/governance/profile_skills.py"
  [ -f "$_ps_script" ] || _ps_script="$DEVKIT_DIR/scripts/profile_skills.py"
  python3 "$_ps_script" "$p" >/dev/null 2>"$TMP/err" && ok "profile $p: skill filter names only existing skills" || fail "profile $p: $(cat "$TMP/err")"
done

# ---------------------------------------------------------------- gate reads .agents/regression_matrix.active.json
M="$(newproj matrix)"
echo 'x' > "$M/README.md" && git -C "$M" add -A && git -C "$M" -c user.email=t@t -c user.name=t commit -qm base
python3 "$CFG" -p backend -t "$M" >/dev/null 2>&1
echo 'package main' > "$M/main.go"
(cd "$M" && python3 "$GATE" --json >"$TMP/out" 2>&1)
grep -q "REG-BE-01" "$TMP/out" && ok "gate uses .agents/regression_matrix.active.json written by agent-config" || fail "gate ignores the .agents/ matrix"
grep -q '"matrix_problem": null' "$TMP/out" && ok "unmodified DevKit profile matrix (uncommitted) is trusted" || fail "DevKit profile matrix flagged untrusted: $(grep -o '"matrix_problem": [^,]*' "$TMP/out")"
python3 - "$M/.agents/regression_matrix.active.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "true"
json.dump(d, open(sys.argv[1], "w"))
PY
(cd "$M" && python3 "$GATE" --run-tests >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "edited, uncommitted matrix -> UNVERIFIED (exit 2), never PASS" || fail "edited uncommitted matrix: exit $rc"

echo
[ "$FAILS" -eq 0 ] && echo "i18n/profiles: all checks passed" || echo "i18n/profiles: $FAILS check(s) failed"
exit "$FAILS"
