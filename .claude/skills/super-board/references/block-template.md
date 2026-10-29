# Block exit template

`Blocked` is an exit ramp, not a workflow step. There is no `Skipped` column (removed in v3.0.0).

## When / who moves cards there

| Where | When | Who |
|---|---|---|
| Blocked | Card needs a person (needs-you, incl. a pre-flight `hold`: duplicate work or missing AC), a rebuild cap or a real red, work in another repo, or a zombie past its reclaim turns | Any lane, from any workflow column |
| Ready + `waiting-on:#N` | Card only waits on another card (pre-flight `sequence`, file overlap, waiting for an open card to close) — never Blocked (#601); a new card is never moved to Blocked with a numbered `blocked-by:` just to wait | `super-board-waiting-on.py mark`; `sweep` drops the label when N closes |
| Done (closed as not planned) | Card dropped on purpose: out of scope, won't do | Any lane; 🤷 comment below |

Once moved, the card waits. **A card that only waits on other cards does not go to Blocked
(#601):** it stays in `Ready` with the label `waiting-on:#N` (`super-board-waiting-on.py mark`), the
planner and runner skip it, and `super-board-waiting-on.py sweep` drops the label once N is
CLOSED/MERGED, so the card builds. `super-board-waiting-on.py migrate` moves older Blocked cards that
only wait on open cards to `Ready` + `waiting-on:#N`. The wave planner still sweeps `Blocked` at the
start of every wave, and any card whose `## Blocked by` issues have all closed is moved back to
`Ready` automatically, with a comment saying what cleared it. Everything else — credentials, permissions, product decisions — still waits for a person.

The old label `⏳ chờ thẻ khác` (planner `pending`) is left only on legacy Blocked cards not yet
migrated, so the board tells "waiting on another card, nothing to do" from "needs a person"; the
runner removes it when the sweep frees the card. `super-board status` lists the two groups apart.

That sweep is why the `blocked-by:` line below is mandatory. Before it existed, `Blocked` was
terminal: on 2026-08-20 five cards sat there long after their blockers had merged, because the only
record of what they were waiting for was English prose in a comment nobody re-read.

## Required Block comment template (mandatory on every transition into Blocked)

The bot must write a structured comment on **both the issue and the PR** (if a PR exists) explaining *why* it moved the card and *what it couldn't safely decide*. Exception: a 🙋 merge approval uses one canonical issue request below; the PR links to it without duplicating its machine lines. Format:

```
[<role>] [blocker] 🛑 blocked · <reason emoji> <one-line reason>
Card:        #<N> <title>
PR:          #<P> (if exists)
Reason tag:  <emoji from table below>
Why blocked: <concrete; 1 line — name the specific thing that is missing or wrong>
Evidence:    <the command + output, file:line, or error that shows it — not a paraphrase>
Checked:     <what the bot verified before blocking, so nobody re-checks it — or "-">
What blocks: <what specific external action would change this — credentials, perms, decisions>
Why I (bot) cannot decide:
             <one line explaining the decision the bot refuses to make on its own —
              "involves billing config; this is a customer money decision",
              "requires choosing between two valid auth providers; ambiguous from spec",
              "would drop a Postgres table; destructive, needs human sign-off">
To unblock:  <concrete action the human can take, in their own checklist form>
             [ ] <step 1>
             [ ] <step 2>
Owner:       <who acts next — "Eric", "repo admin", "design" — never "someone">
Move back:   drag this card to Ready after the steps above are done
blocked-by:  <comma-separated issue numbers, or "-" if nothing on this board clears it>
```

One line per field. The header is the comment header of writing-standard.md § 4: `<role>` is
the lane that writes it (`builder` · `qa` · `reviewer` · `collect` · `orchestrator`). The Block
template is the one comment allowed past 8 lines — its fields are what the human and the sweep
need. The reader is a human deciding in ten seconds whether this is theirs: lead with the fact,
show the evidence, name the owner. No narration of what the bot tried in what order. Run the
prose through `humanizer` when installed.

### The `blocked-by:` line is mandatory

Last line of the block, always present, machine-read. It sits alongside the other machine lines the
lanes already emit (`root-cause-hash:`, `gh-quota-on-exit:`, `move-mutation-result:`) and follows the
same rule: **prose above for the human, one parseable line below for the loop.**

- `blocked-by: 32, 91` — this card returns to `Ready` the moment both close. The sweep does it.
  Since #601 a numbered line is only for: older Blocked cards not yet migrated (`super-board-waiting-on.py migrate`
  turns them into Ready + `waiting-on:#N`), the runner's suite fuse (`blocked-by: <kept card>`). A pre-flight
  `hold — in progress` duplicate waits like a sequence (run.md): `waiting-on:#N`, stays Ready. A new card that only waits for another card to close uses `waiting-on:#N`
  (stays Ready), never Blocked with this line.
- `blocked-by: -` — nothing on this board clears it. It waits for a person, and the sweep leaves it
  alone. Use this for every `🔐`, `💳`, `🔑`, `🧑`, `🎨` and `🙋` block.
- `blocked-by: agent` — the runner parked it (a crashed build worker, a no-op worker): agent work, no person, nothing to wait
  for. Not human-gated, never swept (#529).

Write only issues that are still OPEN: generate the line with
`python3 .claude/bin/super-board-blocked-by.py line --repo <owner/name> <N,M…>` (closed numbers are dropped, its stderr gives the
reason for the Block comment; nothing open prints `blocked-by: -`; exit 79 = state unreadable, write nothing). A closed blocker on
the line frees the card at once and the Builder rebuilds it (agent-workbench#253: #200 built 6 times).

Write the numbers alone. **Never `blocked-by: none — but #26 must merge first`**: a line that says
none and then names an issue is read as *no blocker* by the sweep and as *one blocker* by a human,
and the sweep is the one that acts. That exact shape shipped on a real board and is the reason
`super-board-deps.sh` refuses to guess at it.

The same rule governs the issue body's `## Blocked by` section, which is where the sweep looks when
a card has no block comment yet. Bullets of the form `- #N — why`, or a single `- None.` — nothing
else parses.

### A person must act → mark the card (`needs-you`)

A board view shows no comments. A card that waits for a person carries the mark ON the card: the
`needs-you` label (the Labels field is shown on every board view since 2026-10-19) and one pinned-style
`🙋 Cần bạn: <exactly what the person must do> · xong thì <what next>` comment. On 2026-10-19 about 25
person-only cards were dragged to Ready by mistake because nothing on the card said so.

Every Block whose `blocked-by:` is `-` because a person must act — reason tags 🙋 🧑 🔐 🔑 💳, and 🛡/❓ **only** when a human credential, external console login, legal identity, real-human playtest cohort, or physical hardware not replaceable by an emulator is genuinely required — runs this right after posting the Block comment:

> **Iron Law of Autonomous Execution (`NEVER` mark `needs-you` for agent-doable work):**
> `needs-you` is strictly reserved for steps an agent **cannot** perform without a human (missing passwords/API keys/secrets, Play Console / App Store / Supabase / `@BotFather` login, legal/company filings, live DB migrations outside `allowed_envs`, ≥5 real human playtesters, or physical car/hardware driving).
> Agents MUST **NEVER** mark `needs-you` or move to `Blocked` for work agents can do themselves: testing a PR on a machine or Android/iOS emulator (`PhoneConnect`, Xcode Simulator), rerunning `post-fix-gate --full` or waiting for CPU load, a suite that keeps timing out (it hangs or the machine is loaded: find which test hangs — `PYTHONFAULTHANDLER=1` + `kill -ABRT` — fix it or file a card; never ask a person to raise the limit or accept evidence instead of exit 0), cleaning up dirty worktrees, auto-approving test/regression matrices (`AUTO-APPROVE`), making technical/UI/architecture/scope decisions ("Decide, don't ask"), splitting oversized tickets (`< 400` lines), or running local CLI / GitHub Actions workflows (`gh workflow run`, `kokoro_vi.py`, `chmod +x`). `super-board-needs-you.py mark` mechanically rejects these actions with exit `64`.

```
python3 .claude/bin/super-board-needs-you.py mark --repo <owner/name> --issue <N> \
  --action "<the To unblock steps in one line: exactly what the person does>" \
  --next "<then what: gỡ nhãn needs-you rồi kéo thẻ về Ready | comment done …>"
```

- One call, idempotent: the same text writes nothing, a new action edits the same comment, the
  label is created with one colour (`D93F0B`) when the repo lacks it, and the old `human-gated`
  label is migrated into `needs-you`.
- The comment carries no `Reason tag:`, `blocked-by:`, `approval-request:` or `<!--` line (the
  helper refuses them, exit 64): the Block comment and a 🙋 merge request stay the only lines
  `super-board-deps.sh` and `super-board-approval.py` read.
- A card that waits only on other cards (`blocked-by: 32, 91`) is never marked: the sweep skips
  `needs-you` cards, so it would stay Blocked after #32 closes.
- A 🙋 merge hold (merge gate exit 7 or 8): `--next "comment đúng một chữ done trên issue để duyệt (hoặc tự merge PR #<P>)"` — never "drag to Ready": only an exact
  `done` comment resumes it (`super-board-approval.py` `DONE`), so "done rồi" or "xong" do nothing.
- `--action` is one line of at most 500 characters: shorten long commands, the full ones stay in the Block comment.
- Never unmark a card a lane may still do. The person who did the step removes the label, or runs
  `super-board-needs-you.py unmark --repo <owner/name> --issue <N>` (the comment, and the `🙋` line of a
  `## Cần người` body section, become ✅ notes).
- Exit 1 = a gh call failed: retry once, then name it in the lane report. The Block still stands.

A card dropped on purpose uses the same template with the header `[<role>] [report] 🤷 dropped ·
<reason>`, replaces `Why blocked` with `Why dropped` and `What blocks` with `Why out of scope`, is
closed as not planned (`gh issue close <N> --reason "not planned"`) and moves to Done.

## Reason emoji vocabulary

| Emoji | Class                       | Examples                                                                 |
|-------|-----------------------------|--------------------------------------------------------------------------|
| 🔐    | Credentials / secrets       | missing API key, expired token, no test login                            |
| 💳    | Billing / quota             | paid API rate-limit hit, free tier exhausted, requires plan upgrade      |
| 🔑    | Permissions / access        | gh scope denied, org admin required, write access missing                |
| ❓    | Ambiguity / spec gap        | two valid interpretations, AC contradicts PROJECT.md, dependency unclear |
| 🛡    | Safety / destructive        | would drop a table, would push to prod, would rotate live secrets        |
| 🧑    | Human review needed         | unresolved human PR comment, design decision, branding choice            |
| 🤷    | Out-of-scope                | wrong project, deferred to other milestone, manual-only ticket           |
| 📦    | Wrong-place                 | belongs on a different board / repo                                      |
| 🎨    | Pure design                 | no measurable AC; needs design pass first                                |
| 👯    | Duplicate                   | pre-flight: a merged PR already delivers it, or an open PR / card is building it |
| ⏳    | Sequenced                   | not a Block reason since #601: an open PR touches the same files → card stays Ready with `waiting-on:#N` (no Block comment) |
| 🙋    | Needs you (human-only step) | merge gate exit 7 (merge_policy: money/auth/schema/size — review and merge it, or comment `done` to approve) or exit 8: a migration for a DB the robot may not touch, an allowed migrate command failed, a `needs-you:` step in the PR body, `migrations.human_steps` |

## 🙋 Needs you — a command only a human may run

There is no "Needs you" column: the card goes to **Blocked**, tagged 🙋, with the `needs-you`
label on the issue and the PR. Use it whenever the next step is a command the robot must not run
itself — the merge gate's exit 7 (merge_policy routes the merge to a human: review and merge
it yourself, or comment `done` to approve and let the next wave merge it) and exit 8 (migrations against a database outside `migrations.allowed_envs`,
an allowed migrate command that failed, a declared human step), or any lane that hits one.

Checklist first: the person sees what to do before why. The why and the evidence fold away.
Merge gate exit 7 (a human merges) has one item before `done`: `- [ ] Review and merge PR #<P>
(or comment done to approve it)`. Include any `needs-you:` commands printed with
that policy hold too: the approval covers those human steps as well as the code.

```
[reviewer] [blocker] 🙋 Your turn on #<N> — <title>
- [ ] Run `<exact command 1, copy-paste ready>` on the **<env>** database
- [ ] <exact command 2, if any>
- [ ] Comment `done` here
After a trusted human confirms this version, the next wave returns it to Review for verification.

<details><summary>Why, and what I checked</summary>

PR #<P> <one line — e.g. "adds prisma/migrations/0042_add_plan">. <env> isn't in the databases the robot may migrate.
Tests green on <base>@<sha>; migrated <test, staging>.
Evidence: <the gate's `needs-you:` lines, verbatim>
Reason tag: 🙋 needs you · Owner: <Eric | repo admin>
approval-request: <copy the gate's exact JSON here>
blocked-by: -
</details>
```

Example (what the person sees on GitHub):

> **🙋 Your turn on #812 — Add plan column**
> - [ ] Run `npx prisma migrate deploy` on the **live** database
> - [ ] Comment `done` here
>
> After a trusted human confirms this version, the next wave returns it to Review for verification.
> ▸ Why, and what I checked

The `Reason tag:` and `blocked-by: -` lines stay (inside the fold): the planner reads them
(`super-board-deps.sh` → `needsYou`, `humanGated`). Mark the issue with `super-board-needs-you.py mark`
("A person must act" above) and give the PR the label (`gh pr edit <P> --add-label needs-you`).

**The checklist commands are exact.** Copy them from the gate's `needs-you: <command>` lines;
never paraphrase ("run the migration on prod"). A placeholder such as `<your live migrate command>`
means the config has no command for that env — say so in the fold and name the config key
(`migrations.commands.live`).

**Approval request.** Copy the gate's `approval-request:` line verbatim into this
issue comment. It records the full PR head and the exact policy/human steps being
confirmed. The issue must be linked by the PR's closing reference (`Closes #N`).
For a standalone PR, post the canonical request on the PR instead. Keep a single
request location: the PR's status comment links to the issue request and does not
repeat `Reason tag: 🙋` or `approval-request:`. Never edit a request after posting;
post a new one when the code, steps or actual human question changes. Do not
repost the same pending request on every poll or retry. Generic credential or
product blocks without a PR remain manual; a bare `done` does not automate them.

**Resume.** A human with current repository write, maintain or admin permission
comments `done` after the newest request, in the same thread. This supports a solo
owner approving their own PR. The planner verifies identity, permission, linked
PR and current full head before putting the card in `resume`; the Reviewer then
re-runs the merge gate. The gate also verifies the current policy and human steps,
re-verifies against the base, re-runs allowed migrations, and rechecks approval
just before merging. Changed code, a newer human block, edited evidence, missing
permissions or unreadable GitHub evidence keep it on hold. A still-failing command
also sends it back here. Old bare comments and `needs-you:done` labels never count;
legacy blocked cards need one fresh pinned request and a fresh human reply. Move
those legacy cards to Review once to generate it. If a PR changes while still
Blocked, the planner's `refreshApproval` sends it to Review to create the new
request automatically; it does not mark the new code approved.

**Trust boundary.** GitHub Bot accounts cannot supply human approval. GitHub cannot
distinguish a person from an agent using that person's token; agents must never
write the human's `done` response. The final approval check is a fresh snapshot;
GitHub atomically protects the head at merge, but does not lock issue comments.
A human can still merge a PR manually under the repository's normal rules.

## Hard rule

**The bot is forbidden from moving any card to Blocked, or dropping it to Done, *without* this full template populated. A 1-line "needs creds" comment is a contract violation and fails Reviewer's thread gate.**
