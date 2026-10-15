#!/usr/bin/env bash
# Pin test (W4b, workflow-improvements I.0): the daily /devkit-audit runs `nightly.py run <repo>` ONCE per repo whose checkout is free, and
# never installs a nightly job (user, 2026-09-24: no LaunchAgent). The procedure text is the only place that says so, so this test pins it:
#   - step 7 of "Pha 6" in references/procedure.md names `scripts/governance/nightly.py run <repo>`, the `session_lock.py --status`
#     check right before each repo, exit 0 as the only go (exit 3 held, exit 5 merge-only trunk mode = skip), one repo at a time, in the
#     background; SKILL.md says the same in its Pha 6 summary;
#   - the text does not oversell the check: `--status` exit 0 is not "no session here" (it counts a holder idle at its prompt as free), the
#     real lock check lives in nightly.py (it prints `skip: <reason>`), a session that opens during a run is a stated residual, and the hard
#     rule admits that red_proof adds a disposable worktree and that the tracked checklist files are left uncommitted;
#   - nothing under skills/devkit-audit tells anyone to install or register a nightly job (`nightly install`, `nightly add`, `launchctl`).
# Each pin has a mutant (a copy of the skill folder with that one pin removed) that must be caught, so the greps cannot pass vacuously.
# It only reads text: nightly.py is never run here (tests/verification/test_nightly.sh covers `run <path>` on a fixture).
# DEVKIT_AUDIT_DIR=<copy> runs the same checks on another copy of the skill folder.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="${DEVKIT_AUDIT_DIR:-$DEVKIT_DIR/skills/devkit-audit}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# verify <skill dir>: prints one line per broken pin, nothing when all hold.
verify() {
  local d="$1" proc="$1/references/procedure.md" step
  [ -f "$proc" ] && [ -f "$d/SKILL.md" ] || { echo "missing procedure.md or SKILL.md under $d"; return; }
  # the step: from its "7." line to the next "## " heading, and only if it sits inside Pha 6 (the heading before it)
  step="$(awk '/^## /{ph=$0; if (on) exit} /^7\. Hàng RED-proof chờ/ && ph ~ /^## Pha 6\./ {on=1} on{print}' "$proc")"
  [ -n "$step" ] || { echo "step 7 'Hàng RED-proof chờ' is not inside Pha 6 of procedure.md"; return; }
  printf '%s\n' "$step" | grep -q 'scripts/governance/nightly\.py run <' || echo "step 7 does not call scripts/governance/nightly.py run <repo>"
  printf '%s\n' "$step" | grep -q 'session_lock\.py --status' || echo "step 7 does not check session_lock.py --status"
  printf '%s\n' "$step" | grep -q 'exit 0 mới chạy' || echo "step 7 does not make exit 0 the only go"
  printf '%s\n' "$step" | grep -qi 'exit 3' || echo "step 7 does not name exit 3 (held) as a skip"
  printf '%s\n' "$step" | grep -q 'exit 5' || echo "step 7 does not name exit 5 (trunk mode, merge-only) as a skip"
  printf '%s\n' "$step" | grep -q 'MỘT repo một lúc' || echo "step 7 does not say one repo at a time"
  printf '%s\n' "$step" | grep -q 'run_in_background' || echo "step 7 does not run it in the background"
  # H1 (review of lane A13): `--status` exit 0 is NOT "no session here" (an idle holder counts as free); the real lock check is in nightly.py
  printf '%s\n' "$step" | grep -q 'Exit 0 KHÔNG có nghĩa là không có phiên nào' || echo "step 7 does not say that --status exit 0 does not mean no session is there"
  printf '%s\n' "$step" | grep -q 'Phép kiểm khoá chặt hơn nằm trong `nightly\.py run <repo>`' || echo "step 7 does not say the lock check lives in nightly.py"
  printf '%s\n' "$step" | grep -q 'in `skip: <lý do>`' || echo "step 7 does not name the 'skip: <reason>' line nightly.py prints"
  printf '%s\n' "$step" | grep -q 'Phần dư đã biết: phiên mở trong lúc' || echo "step 7 does not state the residual: a session that opens during a run"
  grep -q 'nightly\.py run' "$d/SKILL.md" || echo "SKILL.md does not mention nightly.py run in its Pha 6 summary"
  grep -q 'điều kiện cần, chưa đủ' "$d/SKILL.md" || echo "SKILL.md Pha 6 summary says --status exit 0 is enough"
  grep -q 'phiên mở giữa lúc một suite đang chạy là phần dư đã biết' "$d/SKILL.md" || echo "SKILL.md does not state the open-during-a-run residual"
  # the hard rule must own up to what the exception does: red_proof's disposable worktree, and the tracked checklist files left dirty
  grep -q 'git worktree add --detach' "$d/SKILL.md" || echo "SKILL.md hard rule does not admit red_proof's git worktree add --detach"
  grep -q 'để chúng chưa commit cho commit kế tiếp' "$d/SKILL.md" || echo "SKILL.md hard rule does not say the tracked checklist files are left uncommitted"
  if grep -q 'Không worktree hay nhánh mới\.' "$d/SKILL.md"; then echo "SKILL.md still says 'Không worktree hay nhánh mới.' flatly while red_proof adds a worktree"; fi
  # (the word LaunchAgent alone is allowed: lessons.md says "không LaunchAgent")
  if grep -rniE 'launchctl|nightly(\.py)? +(install|add)' "$d" --include='*.md' >/dev/null 2>&1; then
    echo "the skill folder tells someone to install or register a nightly job: $(grep -rniE 'launchctl|nightly(\.py)? +(install|add)' "$d" --include='*.md' | head -1 | cut -c1-120)"
  fi
}

out="$(verify "$SKILL")"
[ -z "$out" ] && ok "procedure.md step 7 + SKILL.md: nightly.py run <repo> once per free repo, exit 0 only, 3 and 5 skip, one at a time, background, no install" || fail "$out"

# mutants: each removes ONE pin from a copy and verify must say so
mutant() {  # mutant <name> <file under the skill dir> <sed expression>
  local c="$TMP/m-$1"; rm -rf "$c"; cp -R "$SKILL" "$c"
  sed -e "$3" "$c/$2" > "$c/$2.new" && mv "$c/$2.new" "$c/$2"
  if cmp -s "$SKILL/$2" "$c/$2"; then fail "mutant $1: the sed changed nothing, the pin is not where the test looks"; return; fi
  [ -n "$(verify "$c")" ] && ok "mutant $1 is caught" || fail "mutant $1 survived: verify said nothing"
}
mutant no-run-call  references/procedure.md 's#scripts/governance/nightly\.py run <#scripts/governance/nightly.py status <#'
mutant no-lock      references/procedure.md 's#session_lock\.py --status#session_lock.py --help#'
mutant exit5-gone   references/procedure.md 's#exit 5 (trunk#exit 9 (trunk#'
mutant exit3-gone   references/procedure.md 's#Exit 3 (phiên#Exit 4 (phiên#'
mutant any-exit     references/procedure.md 's#Chỉ exit 0 mới chạy#Chạy luôn#'
mutant parallel     references/procedure.md 's#MỘT repo một lúc#các repo cùng lúc#'
mutant foreground   references/procedure.md 's#run_in_background#foreground#'
mutant skill-line   SKILL.md                's#nightly\.py run#nightly.py status#'
mutant status-enough references/procedure.md 's#Exit 0 KHÔNG có nghĩa là không có phiên nào#Exit 0 có nghĩa là không có phiên nào#'
mutant lock-not-in-nightly references/procedure.md 's#Phép kiểm khoá chặt hơn nằm trong `nightly\.py run <repo>`#Phép kiểm khoá nằm trong `session_lock.py`#'
mutant no-skip-line references/procedure.md 's#in `skip: <lý do>`#in lý do#'
mutant no-residual  references/procedure.md 's#Phần dư đã biết: phiên mở trong lúc#Không còn rủi ro: phiên mở trong lúc#'
mutant skill-enough SKILL.md                's#điều kiện cần, chưa đủ#điều kiện đủ#'
mutant skill-no-residual SKILL.md           's#phiên mở giữa lúc một suite đang chạy là phần dư đã biết#phiên mở giữa lúc một suite đang chạy không đáng kể#'
mutant no-worktree-admission SKILL.md       's#git worktree add --detach#git status#'
mutant no-dirty-admission SKILL.md          's#để chúng chưa commit cho commit kế tiếp#để chúng như cũ#'
mutant flat-no-worktree SKILL.md            's#Audit không tự tạo worktree hay nhánh mới (trừ sandbox của red_proof nói trên)\.#Không worktree hay nhánh mới.#'
mutant step-moved  references/procedure.md 's#^7\. Hàng RED-proof chờ#6b. Hàng RED-proof chờ#'
mutant install      references/procedure.md 's#^   2\. `python3 \$KIT/scripts/governance/nightly\.py run#   2. Cài job đêm: `python3 $KIT/scripts/governance/nightly.py install`; rồi `python3 $KIT/scripts/governance/nightly.py run#'

[ "$FAILS" -eq 0 ] && echo "✅ test_devkit_audit_nightly_step: all passed" || { echo "❌ test_devkit_audit_nightly_step: $FAILS failed"; exit 1; }
