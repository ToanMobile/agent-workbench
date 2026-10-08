# Proposal — catch the bugs an agent cannot see (state-matrix, device-first, wiring pins)

Source: OfficeReader session of 2026-10-07 (profile `android`). Written by the agent at the user's request
("gửi qua devkit để nó bổ sung kiểu này để bắt bug, chạy test kiểm tra tốt hơn").
Status: PROPOSAL — nothing here is implemented; every item names how to prove it works.

## 1. What happened (evidence, not opinion)

Four user-visible defects shipped through green unit tests, a full post-fix gate (exit 0, 7/7 regression
groups) and a first code review. Each was found by something else:

| Defect | Why tests and gate were green | What found it |
|---|---|---|
| PDF "Translate" got 1-2 words: the END selection handle of a short word (~60 px) sat inside the 80 px radius of the START handle, which was tested first | The selection logic lives in an Android `View` over native PDFium: zero tests. The translate tests used a fake engine and a fixed string. | The user, on a phone; then `adb input swipe` + the sheet showing the source text "a" |
| Page pill ~75 dp above the bottom dock (`windowInsetsPadding(navigationBars)` applied inside an area the Scaffold had already padded) | Robolectric Compose runs with insets = 0, so a doubled inset is invisible | The user, on a phone; then `ui-query` bounds (210 px → 30 px) |
| Same pill drawn over a spreadsheet's own 44 dp tab strip | Nothing models the viewer's own bottom chrome | The agent's own device screenshot of an XLSX, after the user said "display is ugly" |
| Landscape + 3-button nav: pill under the side navigation bar; `.xlsb` has tabs on top, not bottom | State combination never enumerated | A fresh-context reviewer reading the code state by state |

Common cause: the agent reasons from code and trusts green checks. Bugs that come from real geometry or from
combinations of states are outside both. The only things that caught them were (a) a real device, (b) a person
or reviewer who enumerated states.

## 2. Proposals

Each item: change, then how to prove it.

**P1 — Device-first reproduction for UI / gesture prompts.**
When the prompt classifier says UI_INTERACTION or a bug is reported about something the user sees or touches,
the first plan step is a reproduction on a device (before reading code), and the handover must carry a *before*
and an *after* artefact (screenshot or `ui-query` bounds by test tag). `proof_gate.sh` today checks only the
*after* PNG. Proof: a bug-fix reply with only an after PNG is refused with "BEFORE evidence missing".

**P2 — A "state matrix" step before a layout/overlay change is called done.**
Skill + reviewer lens that forces a table: document types × orientation × navigation mode (gesture / 3-button) ×
bars hidden × edit strips × TTS player × font scale 200 % × RTL × display cutout, one line of outcome per cell.
Add the lens to `principal-code-reviewer` and `council-*` prompts. Proof: replay today's four defects through
the lens; each must surface as a table cell marked "overlaps" or "unchecked".

**P3 — Overlap-invariant test template for Compose (profile `android`).**
A helper that renders a screen under injected `WindowInsets`, orientation and font scale, collects the bounds of
all interactive overlays by test tag, and asserts: no two intersect, each >= 48 dp, none under a system bar.
Proof: the helper, run on OfficeReader's reader screen at commit `7ee3d230a^`, fails on the doubled inset.

**P4 — Wiring pins when logic is extracted from an Android View.**
The vacuity gate correctly called a pure-helper test empty (reverting the view left it green). Make the next
step automatic: when a new `internal object` is created next to a `View` file and a test targets only the
object, generate a source-text pin test that asserts the view still calls it (and no longer contains the old
branch). Proof: reverting the view's call site turns the pin red.

**P5 — Do not let Stop hooks run Gradle while a gate run holds it.**
`testsourceset_gate.sh` compiled `:app` while `post-fix-gate.py` was running; the result was AAPT "resource
string/app_name not found" — a false P0. Serialise on the gate's lock, or report BUSY like `regression_gate.sh`
does. Proof: start a gate, trigger Stop; no AAPT error, hook reports BUSY.

**P6 — Commit-closure check at edit time, not at commit time.**
My edit lived in an *untracked* file produced by another session's refactor. Nothing said so until a reviewer
noticed that the file could not be committed alone and HEAD still held the old block. Add a check: for every
changed path, warn when it is untracked, or when HEAD's version of the same symbol is elsewhere; offer
`git archive HEAD` + overlay of the paths to be committed and compile that. Proof: the scenario above is flagged
the moment the file is edited.

**P7 — Scope `regression_invariants` to what is committed.**
It scanned another session's untracked test and blocked an unrelated commit (`?: return@collect` in a collector
lambda, which is also a false positive of the `TEST_EARLY_RETURN` rule). Scan staged + modified-tracked paths;
treat untracked foreign files as warnings. Proof: the commit goes through with that file present.

**P8 — Remember test-edit approvals by content hash.**
The same 7-15 edited tests were re-listed on every Stop (more than ten times in one session) after the user had
approved them twice. Store the approval (path + content hash) and honour it in `regression_gate.sh`; re-ask only
when the hash changes. Proof: approve once, stop twice, no second prompt; edit the file, prompt again.

**P9 — Telemetry rule for user-supplied selections (profile `android`).**
Features that act on a user selection should log a size bucket (never the content). A feature whose requests
are almost all 1-2 words is a signal no test gives. Proof: lint/rule text added; sample event name + bucket
scheme documented next to the PII rule.

**P10 — Upstream generic traps.**
`agent-kit learn` writes only to the project's `instincts.md`. When the trap is not project-specific
(overlapping touch targets must be nearest-wins; no `windowInsetsPadding` inside an area already padded by the
Scaffold), offer to copy it to the profile's instincts. Proof: the two traps from this session appear in
`profiles/android` after the command.

## 3. Suggested order

P1 + P2 (process, cheap, would have prevented most of today) → P3 + P4 (tests that outlive the session) →
P5 + P6 + P7 + P8 (friction that cost the most time this session) → P9 + P10.

## 4. Not claimed

No item here has been tried in this repo. P3's claim that Robolectric inserts zero insets is observed, not
measured for every API level. The OfficeReader fixes referenced are commit `7ee3d230a` (selection) and an
uncommitted working-tree change (pill, overlay stack).
