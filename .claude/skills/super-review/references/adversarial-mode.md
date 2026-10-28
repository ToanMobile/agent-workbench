# Super Review — Adversarial mode

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Adversarial mode (folded from super-truth)

Activated per `config.truth_gate`:
- `off` — never adversarial.
- `non-trivial` (default) — diff ≥10 lines OR labels in `{security, migration, payments, auth}` trigger adversarial.
- `always` — every card.

When activated, spawn 2 sub-agents in parallel:
- **Code-grounder.** Verify cited file:line still exists and matches claims.
- **Historian.** `git blame` the changed lines; check for ADRs / prior incidents.

**Use this brief verbatim.** Fill the `<…>` slots; do not reword, add or drop lines. A
reviewer that wrote its own brief once told the sub-agents over-engineering was blocking,
and a correct PR was held for it.

```
You are the <Code-grounder | Historian> in an adversarial truth-check of PR #<P>.
Job: <Code-grounder: verify every file:line the PR cites still exists and does what the PR
claims. | Historian: git blame the changed lines; look for ADRs, prior incidents, reverted
attempts.>
Read the issue ACs and the diff first and form your own hypotheses. Only then read the
builder's summary below, as claims to check, not as the frame.
ACs: <paste>
Diff: <merge-base diff or path to it>
Builder's summary (claims): <paste>
Budget: at most 50 gh calls; prefer local git. Over budget: confidence "insufficient_data".
Class every finding: Gap / Bug / Verification miss / Scope drift / Over-engineering / No issue.
Severity: Blocker / Should fix / Nit.
Over-engineering is ALWAYS Should fix and NEVER Blocker on its own. It does not lower your
confidence score.
Confidence 0-100 = how sure you are the PR's claims are true and the code does what the ACs
ask. Design taste and over-building do not count against it.
Return: findings (class, severity, file:line, one line each) and confidence.
```

**After collecting, the Reviewer re-applies the rules itself.** Whatever a sub-agent wrote:
reclass any Over-engineering finding marked Blocker to Should fix, and ignore it when
deciding merge or bounce (step 7). A sub-agent that lowered its confidence only because of
over-engineering is re-scored without it. The merge decision is the Reviewer's, not the
sub-agents'.

**Aggregation rule: take the MINIMUM of the two scores.** Rationale: one strong skeptic should be enough to block.

Compare aggregate to `config.truth_threshold` (default `70`):
- **Below threshold** → Reviewer MUST NOT approve. Inspect the lowest-confidence sub-agent finding:
  - If the finding is a code defect, logic hazard, or missing unit test (`Bug`, `Gap`, `Scope drift`) → open a `[builder]`-prefixed PR thread quoting the finding, write the Reviewer report (`bounced`), and move card **Review → Ready** with `loop:rebuild-N` (**NEVER** `Blocked` or `needs-you`).
  - If the finding is a test/runtime verification gap (`Verification miss`) that an agent can run on an emulator/simulator/local test runner → verify it directly in the Reviewer lane, or open a `[qa]`-prefixed PR thread and move card **Review → QA** with `loop:rebuild-N` (**NEVER** `Blocked` or `needs-you`).
  - Move to `Blocked` (`🛡`) **ONLY** when the finding requires an irreversible destructive live operation (dropping a live DB table, rotating live production secrets) or after `config.rebuild_cap` bounces have been exhausted.
- **Above threshold** → continue to approval decision.
