#!/usr/bin/env python3
"""super-board-status.py — read-only live snapshot of the super-board pipeline.

Renders the richer status template defined in
`.claude/skills/super-board/references/status.md` (fixed 80-col Kanban
plus dedicated Workers / Block-reasons / Recent / Health sections).

The same template can be hand-rendered by the model — but the token-by-
token box-drawing takes ≈3 min per invocation, which makes the richer
view impractical in practice. This script renders it in ≈1.3 s by doing
the layout as a single Python pass.

What it does:
  1. Resolve config slug: arg | `.claude/super-board/active` | sole config.
  2. ONE GraphQL call for project items (number, title, labels, Status).
  3. ONE `gh issue view` per Blocked card for reason-tag extraction.
  4. Read today's manifest and pipe everything to the locked-template
     renderer that prints the 80-col snapshot matching the spec in
     references/status.md.

What it does NOT do:
  - Any GitHub mutations (read-only verb — same forbidden set as the skill).
  - Touch the manifest, locks, or worktrees.
  - Wait for or poll workers.

Cross-platform: pure Python 3 stdlib + `gh` CLI. Works on macOS, Linux,
Windows (PowerShell / CMD / Git Bash / WSL). No bash, no jq.

Usage:
  python .claude/bin/super-board-status.py [<config-slug>]

Exit codes:
  0  ok
  64 missing arg + no active marker + no single config
  66 config not found
  67 gh / network failure
"""

from __future__ import annotations

import datetime
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any, Callable

# Make box-drawing chars render on Windows consoles too.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass


# ───────────────────────────── lane constants ─────────────────────────────
# Used by dispatch parsing, kanban glyph lookup, and the workers section.
# Source of truth — never inline these as dict literals at call sites.

LANE_ORDER: tuple[str, ...] = ("build", "qa", "review")
LANE_GLYPH = {"build": "🔨", "qa": "🔍", "review": "✏️"}
LANE_LABEL = {"build": "Building", "qa": "QA", "review": "Review"}
LANE_ROLE = {"build": "Builder ", "qa": "Tester  ", "review": "Reviewer"}

# Board columns, left to right as they sit on the GitHub project. The kanban
# prints in exactly this order. Backlog and Done collapse to one line of numbers.
BOARD_ORDER: tuple[str, ...] = (
    "Backlog", "Ready", "Building", "QA", "Review", "Blocked", "Done",
)
# #138: a Status option outside BOARD_ORDER (the DevKit's "Needs You") gets its own box before Done, only when it holds a card.
NEEDS_YOU_STATUS = "Needs You"
COLLAPSED_TAIL = {"Backlog": "(not started, collapsed)", "Done": "(squash-merged, collapsed)"}


# ───────────────────────────── manifest grammar ─────────────────────────────
# The dispatcher's log format lives in `scripts/super-board-run.sh`. These
# regexes are the contract between the two. When the dispatcher changes a
# log line, update the regex here AND add a fixture to `tests/` so the
# divergence can't sneak back in.

TS_RE = re.compile(r"^\[(\d{2}):(\d{2}):(\d{2})\] (.*)$")
# Dispatcher emits: `dispatch lane=${lane} issue=#${issue} pid=${pid} claim=...`
# Lanes are restricted to the known set so a typo'd lane never reaches the
# LANE_GLYPH / LANE_ORDER lookups below.
DISPATCH_RE = re.compile(r"dispatch lane=(build|qa|review) issue=#(\d+) pid=(\d+)")
# Two reap variants in the dispatcher:
#   `reaped stale lock + swept assignee on #N (pid=P)`
#   `reaped stale lock for #N (pid=P)`
# And `pid=${PID:-empty}` can expand to `pid=empty` when the PID was lost.
REAP_RE = re.compile(r"reaped stale lock\b[^#]*#(\d+) \(pid=(\d+|empty)\)")
ZOMBIE_RE = re.compile(r"zombie [a-z]+ worker on #(\d+) \(pid=(\d+)\)(.*)$")
ALERT_RE = re.compile(r"block-rate alert: (.+)$")


# ───────────────────────────── pure helpers ─────────────────────────────

# Control chars (C0 + DEL) sourced from GitHub-controlled issue titles would
# otherwise reach the terminal verbatim and could redraw the kanban frame
# (e.g. a title containing `\x1b[2K\r`). Strip them at ingestion. Tabs, LF,
# and CR are all in this range — none have a legitimate place in a one-line
# title display anyway.
_CTRL_CHARS_RE = re.compile(r"[\x00-\x1f\x7f]")


def sanitize_title(s: str) -> str:
    return _CTRL_CHARS_RE.sub("", s)


def hms_to_epoch(today_iso: str, hms: str) -> int:
    """Combine an ISO date + HH:MM:SS local time into a Unix epoch.

    Pure: no module state, no I/O. `today_iso` is passed explicitly so the
    manifest parser can be unit-tested with a fixed date.
    """
    try:
        dt = datetime.datetime.strptime(f"{today_iso} {hms}", "%Y-%m-%d %H:%M:%S")
        return int(dt.timestamp())
    except ValueError:
        return 0


def parse_manifest(text: str, today_iso: str) -> dict[str, Any]:
    """Parse a super-board run manifest into structured state.

    Pure function (no I/O, no global state) so it can be unit-tested with
    hand-crafted fixtures. Returns a dict with:
      inflight: {lane → {pid, issue, ts}}    — workers currently dispatched
      recents: [{epoch, verb, glyph, issue, target, detail}, ...]
      last_tick: HH:MM:SS of the most recent `tick —` line, or None
      start_hms: HH:MM:SS of the most recent `super-board run started`, or None
      exited: True if the run has logged `exiting cleanly`
      reaped_count: number of `reaped stale lock ...` lines seen
    """
    inflight: dict[str, dict[str, str]] = {}
    recents: list[dict[str, Any]] = []
    last_tick: str | None = None
    start_hms: str | None = None
    exited = False
    reaped_count = 0

    for line in (text or "").splitlines():
        m = TS_RE.match(line)
        if not m:
            continue
        h, mi, s, rest = m.groups()
        hms = f"{h}:{mi}:{s}"
        ep = hms_to_epoch(today_iso, hms)

        if "super-board run started" in rest:
            start_hms = hms
            exited = False
            continue
        if "exiting cleanly" in rest:
            exited = True
            continue
        if rest.startswith("tick "):
            last_tick = hms
            continue

        if dm := DISPATCH_RE.search(rest):
            lane, issue, pid = dm.groups()
            # Clean lane handoffs (Build → QA → Review) don't emit reap/zombie
            # lines, so the prior lane's inflight entry would otherwise linger
            # and render as a phantom concurrent worker. A fresh dispatch into
            # a later lane for the same issue is proof the earlier lane
            # finished — drop the prior entry before recording the new one.
            for prior in LANE_ORDER[: LANE_ORDER.index(lane)]:
                if inflight.get(prior, {}).get("issue") == issue:
                    del inflight[prior]
            inflight[lane] = {"pid": pid, "issue": issue, "ts": hms}
            recents.append({
                "epoch": ep, "verb": "dispatch", "glyph": LANE_GLYPH[lane],
                "issue": f"#{issue}", "target": LANE_LABEL[lane],
                # `attempt N/3` is filled in at render time from current
                # labels — the manifest doesn't encode it at dispatch time.
                "detail": "",
            })
            continue
        if rm := REAP_RE.search(rest):
            # The dispatcher logs `reaped stale lock ...` for every reap; bump
            # the housekeeping counter here (one branch, not two) and record
            # the event. `pid=empty` matches when the dispatcher couldn't
            # recover the PID from the lock file — in that case we can't drop
            # a specific inflight entry, but the reap is still worth surfacing.
            reaped_count += 1
            issue, pid = rm.groups()
            if pid != "empty":
                for lane, v in list(inflight.items()):
                    if v["pid"] == pid:
                        del inflight[lane]
            recents.append({
                "epoch": ep, "verb": "reap", "glyph": "♻",
                "issue": f"#{issue}", "target": "",
                "detail": "stale lock + assignee swept",
            })
            continue
        if zm := ZOMBIE_RE.search(rest):
            issue, pid, det = zm.groups()
            for lane, v in list(inflight.items()):
                if v["pid"] == pid:
                    del inflight[lane]
            recents.append({
                "epoch": ep, "verb": "zombie", "glyph": "💀",
                "issue": f"#{issue}", "target": "", "detail": det.strip(" —"),
            })
            continue
        if am := ALERT_RE.search(rest):
            recents.append({
                "epoch": ep, "verb": "alert", "glyph": "⚠",
                "issue": "", "target": "", "detail": am.group(1),
            })

    return {
        "inflight": inflight,
        "recents": recents,
        "last_tick": last_tick,
        "start_hms": start_hms,
        "exited": exited,
        "reaped_count": reaped_count,
    }


def visual_width(s: str) -> int:
    """Approximate east-asian-width-aware cell count."""
    w = 0
    for c in s:
        if unicodedata.category(c) == "Mn" or ord(c) == 0xFE0F:
            continue
        if unicodedata.east_asian_width(c) in ("W", "F"):
            w += 2
        elif ord(c) >= 0x2600:  # most symbol/emoji blocks render wide
            w += 2
        else:
            w += 1
    return w


def vpad(s: str, width: int) -> str:
    """Right-pad s with spaces to occupy `width` visual cells."""
    diff = width - visual_width(s)
    return s + (" " * diff) if diff > 0 else s


def truncate_to(s: str, width: int) -> str:
    """Truncate s to <= width visual cells, adding … if shortened."""
    if visual_width(s) <= width:
        return s
    out = ""
    for c in s:
        if visual_width(out + c) > width - 1:
            return out + "…"
        out += c
    return out


def box_top(label: str, count: int) -> str:
    head = f"┌─ {label:<8} [{count}] "
    fill = "─" * (80 - visual_width(head) - 1)
    return head + fill + "┐"


def box_bot() -> str:
    return "└" + ("─" * 78) + "┘"


def box_line(body: str) -> str:
    body = truncate_to(body, 76)
    return f"│ {vpad(body, 76)} │"


def rebuild_count(item: dict[str, Any] | None) -> int:
    """Read `loop:rebuild-N` from labels; 0 if absent."""
    if not item:
        return 0
    for lab in item["labels"]:
        if m := re.match(r"loop:rebuild-(\d+)", lab):
            return int(m.group(1))
    return 0


def attempt_str(item: dict[str, Any] | None) -> str:
    """`attempt N/3` derived from the issue's current `loop:rebuild-N` label."""
    return f"{min(rebuild_count(item) + 1, 3)}/3"


def rebuild_suffix(item: dict[str, Any]) -> str:
    k = rebuild_count(item)
    return f"↻ {min(k + 1, 3)}/3" if k else ""


REASON_TABLE: list[tuple[str, str]] = [
    ("🛡", "dependency gate"),
    ("🔐", "missing creds"),
    ("💳", "quota / billing"),
    ("❓", "ambiguous AC"),
    ("⚙",  "infra / tooling"),
]


def reason_for(body: str) -> tuple[str, str]:
    """Pick the leading reason emoji from a comment body; fall back to 🚫."""
    for em, txt in REASON_TABLE:
        if em in body:
            return em, txt
    return "🚫", "other"


_BLOCKED_BY_LINE = re.compile(r"^[ \t]*blocked-by:(.*)$", re.I | re.M)
_BLOCKED_BY_OK = re.compile(r"^(-|agent|[0-9]+(,[0-9]+)*)?$")  # `agent` (#529): parked by the runner, same rule as deps.sh


def split_unreadable_blocked_by(
    blockers: list[dict[str, Any]], comments: dict[int, list[dict[str, Any]]]
) -> tuple[dict[int, str], list[dict[str, Any]]]:
    """#386: split Blocked cards into ({number: why} whose newest `blocked-by:` line deps.sh cannot parse, the rest). Same rule as
    super-board-deps.sh: `-`, empty or issue numbers alone are readable; `#377` or a sentence is not."""
    bad: dict[int, str] = {}
    for it in blockers:
        ordered = sorted(comments.get(it["number"], []), key=lambda c: c.get("createdAt", ""))
        lines = [m.group(1) for c in ordered for m in _BLOCKED_BY_LINE.finditer(c.get("body") or "")]
        if not lines:
            continue
        value = re.sub(r"[ \t\r]", "", lines[-1])
        if not _BLOCKED_BY_OK.match(value):
            bad[it["number"]] = f'`blocked-by:` reads "{value}" — it must be issue numbers alone, or `-`'
    return bad, [it for it in blockers if it["number"] not in bad]


def field_status(node: dict[str, Any]) -> str:
    """Read the `Status` single-select field from a project-item node."""
    for fv in (node.get("fieldValues", {}).get("nodes") or []):
        if fv and fv.get("field", {}).get("name") == "Status":
            return fv.get("name") or "Backlog"
    return "Backlog"


# ───────────────────────────── side-effecting helpers ─────────────────────────────

# Slugs are file-system identifiers (configs/<slug>.json, runs/<date>-<slug>.md),
# so we constrain them to a safe character class up front. Without this, a
# slug like `../../../../etc/passwd` would slide through `Path(f"...{slug}...")`
# and let an arg read arbitrary `.json` files relative to CWD. The script is
# read-only so the blast radius is limited, but the read-only contract in
# `status.md` reads stronger than what the unguarded code delivers — close
# the gap here.
_SLUG_RE = re.compile(r"\A[A-Za-z0-9._-]+\Z")


def valid_slug(slug: str) -> bool:
    # `.` and `..` are pure-dot literals that pass the regex's char class but
    # are path-traversal sentinels — reject them explicitly. (`Path(.json)`
    # would land at `.claude/super-board/configs/.json` which still wouldn't
    # escape the configs dir, but the manifest path uses the same slug too
    # and `..` there does escape.)
    if slug in (".", ".."):
        return False
    return bool(_SLUG_RE.match(slug))


def resolve_config_slug(argv: list[str]) -> str:
    if len(argv) > 1 and argv[1]:
        return argv[1]
    active = Path(".claude/super-board/active")
    if active.is_file():
        return active.read_text().strip()
    cfgs = sorted(Path(".claude/super-board/configs").glob("*.json"))
    if len(cfgs) == 1:
        return cfgs[0].stem
    print(f"usage: {argv[0]} <config-slug>  (or set .claude/super-board/active)", file=sys.stderr)
    sys.exit(64)


def gh(*args: str, check: bool = True) -> str:
    """Run gh and return stdout. Exits 67 on failure when check=True."""
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, encoding="utf-8", check=False
        )
    except FileNotFoundError:
        print("gh CLI not found on PATH", file=sys.stderr)
        sys.exit(67)
    if proc.returncode != 0:
        if check:
            print(f"gh call failed ({' '.join(args[:3])}…)", file=sys.stderr)
            if proc.stderr.strip():
                print(proc.stderr.strip(), file=sys.stderr)
            sys.exit(67)
        return ""
    return proc.stdout


# ───────────────────────────── GraphQL ─────────────────────────────
# Targeted query — number, title, labels, Status only. ~3 KB vs. 100+ KB for
# `gh project item-list --format json` (which slurps every issue body).
# `repositoryOwner(login:)` is the abstract owner; `... on ProjectV2Owner`
# picks the `projectV2` field which both User and Organization implement.
# `$after` is nullable — first page omits the `-F after=…` arg entirely
# (default null) so we don't have to pass a sentinel value.

ITEMS_QUERY = """
query($owner:String!, $number:Int!, $after:String) {
  repositoryOwner(login:$owner) {
    ... on ProjectV2Owner {
      projectV2(number:$number) {
        items(first:100, after:$after) {
          pageInfo { endCursor hasNextPage }
          nodes {
            content { ... on Issue { number title labels(first:20){nodes{name}} } }
            fieldValues(first:8) {
              nodes { ... on ProjectV2ItemFieldSingleSelectValue {
                name field { ... on ProjectV2SingleSelectField { name } } } }
            }
          }
        }
      }
    }
  }
}
"""

# Hard ceiling on pagination depth. 20 pages × 100 items = 2000 cards, which
# is well past any realistic super-board project (the dispatcher's 5000-pt/hr
# GraphQL budget makes a 20-page snapshot a meaningful chunk of quota). If a
# project ever exceeds this, we print a truncation warning rather than loop
# forever on a buggy server response.
MAX_ITEM_PAGES = 20


def paginate_items(
    fetch: Callable[[str | None], dict[str, Any]],
    max_pages: int = MAX_ITEM_PAGES,
) -> tuple[list[dict[str, Any]], bool]:
    """Walk `fetch(after) → graphql_payload` until pagination is exhausted.

    Pure: no I/O of its own — the `fetch` callable does all I/O. Returns
    (all_nodes, hit_cap), where `hit_cap` is True iff we stopped because
    of `max_pages` (i.e., the project is bigger than we surfaced).
    """
    all_nodes: list[dict[str, Any]] = []
    after: str | None = None
    for _ in range(max_pages):
        payload = fetch(after)
        items_section = (
            ((payload.get("data") or {})
                .get("repositoryOwner") or {})
                .get("projectV2") or {}
        ).get("items") or {}
        all_nodes.extend(items_section.get("nodes") or [])
        page_info = items_section.get("pageInfo") or {}
        if not page_info.get("hasNextPage"):
            return all_nodes, False
        after = page_info.get("endCursor")
        if not after:
            return all_nodes, False
    return all_nodes, True


# ───────────────────────────── main ─────────────────────────────


PERSON_LABELS = ("needs-you", "human-gated")


def group_by_status(items: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """#138: cards per Status, newest first. Every BOARD_ORDER column is a key; any other option present on the project is one too."""
    names = list(BOARD_ORDER) + sorted({i["status"] for i in items} - set(BOARD_ORDER))
    return {s: sorted([i for i in items if i["status"] == s], key=lambda x: -x["number"]) for s in names}


def waiting_on_person(items: list[dict[str, Any]], no_device: bool = False) -> list[dict[str, Any]]:
    """#138: every card in the "Needs You" column. #95: Ready and Blocked cards only a person can move on (needs-you / human-gated, any case), newest first. The runner and the
    planner never take such a card from Ready, so they get their own group instead of hiding among the Block reasons. Not QA or
    Review: a lane works those (the resume path brings an approved 🙋 card to Review with its label possibly still on).
    With no_device, also the cards held for a real device (held_for_device)."""
    def waits(i: dict[str, Any]) -> bool:
        names = [str(l).lower() for l in i.get("labels") or []]
        back_in_loop = any(n == "loop:rebase" or n.startswith("loop:rebuild-") for n in names)   # super-board-run.sh FOR_A_PERSON_JQ
        return any(n in PERSON_LABELS for n in names) and not (i.get("status") == "Ready" and back_in_loop)

    return sorted((i for i in items if i.get("status") == NEEDS_YOU_STATUS or (i.get("status") in ("Ready", "Blocked") and waits(i)) or (no_device and held_for_device(i))),
                  key=lambda x: -x["number"])


WAITING_LABEL = "⏳ chờ thẻ khác"


def waiting_on_cards(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """#235: Blocked cards that only wait on other open cards (the runner labels them WAITING_LABEL; the sweep releases them by
    itself), newest first. Apart from the cards that need a person."""
    return sorted((i for i in items if i.get("status") == "Blocked"
                   and WAITING_LABEL in [str(l).lower() for l in i.get("labels") or []]), key=lambda x: -x["number"])


def held_for_device(i: dict[str, Any]) -> bool:
    """#95: its QA needs a real device (needs-device, any case) — in QA, or in Ready labelled `qa`. The runner and the planner hold
    it while none is online (super-board-run.sh DEVICE_JQ). Not Review; a Ready card without `qa` is built first."""
    names = [str(l).lower() for l in i.get("labels") or []]
    return "needs-device" in names and (i.get("status") == "QA" or (i.get("status") == "Ready" and "qa" in names))


def no_real_device(items: list[dict[str, Any]]) -> bool:
    """True when a card is held for a device and super-board-device-online.py finds no real one. adb is asked only then."""
    if not any(held_for_device(i) for i in items):
        return False
    helper = Path(__file__).with_name("super-board-device-online.py")
    try:
        proc = subprocess.run([sys.executable, str(helper)], capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"warning: could not ask whether a real device is online ({exc}); needs-device cards shown as waiting", file=sys.stderr)
        return True
    if proc.returncode != 0 and proc.stderr.strip():
        print(f"note: {proc.stderr.strip()}", file=sys.stderr)
    return proc.returncode != 0


BRANCH_CARD_RE = re.compile(r"^issue-(\d+)-")


def _branch_card(ref: str) -> int | None:
    m = BRANCH_CARD_RE.match(ref or "")
    return int(m.group(1)) if m else None


def git_common_dir() -> Path | None:
    """<git-common-dir> of the cwd repo, where the merge train and queue keep their state; None outside a repo."""
    out = git_out("rev-parse", "--git-common-dir")
    return Path(out).resolve() if out else None


def git_out(*args: str) -> str:
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists, owned by someone else
    except OSError:
        return False
    return True


def _parse_train_state(text: str) -> tuple[int | None, int | None, str, list[dict[str, Any]]]:
    """One train state file: (pid, started_at, step, prs)."""
    pid = started = None
    step = "gate"
    prs: list[dict[str, Any]] = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "pid" and parts[1].isdigit():
            pid = int(parts[1])
        elif len(parts) >= 2 and parts[0] == "started_at" and parts[1].isdigit():
            started = int(parts[1])
        elif len(parts) >= 2 and parts[0] == "step":
            step = parts[1]
        elif len(parts) >= 2 and parts[0] == "pr" and parts[1].isdigit():
            ref = parts[3] if len(parts) > 3 else ""
            prs.append({"pr": int(parts[1]), "ref": ref, "card": _branch_card(ref)})
    return pid, started, step, prs


def read_merge_train(
    common_dir: Path | None, now: float, alive: Callable[[int], bool] = pid_alive
) -> dict[str, Any] | None:
    """The running merge train(s) from `<common>/super-board/merge-train.<pid>.state` (#676; `merge-train.state` before it, #562), else None.

    Each train writes `pid`, `started_at`, `step` (gate | merge) and one `pr <N> <sha> <ref>` line per PR, and removes its file on
    exit. #676 runs one train per PR, several at once: the live ones are merged into one view (PRs and cards of all, oldest
    `started_at`, step `merge` when any train merges, pid of the oldest). An unreadable file, a missing/dead pid or an orphan left by a
    SIGKILL is skipped. Never touches a train's claim.
    ponytail: a pid reused by an unrelated process keeps an orphan file alive; the queue's `ps` command check would close it, add
    when it shows up.
    """
    if common_dir is None:
        return None
    sb = common_dir / "super-board"
    try:
        paths = sorted(sb.glob("merge-train.*.state")) + [sb / "merge-train.state"]
    except OSError:
        return None
    live: list[tuple[int, int, str, list[dict[str, Any]]]] = []
    for path in paths:
        try:
            pid, started, step, prs = _parse_train_state(path.read_text())
        except OSError:
            continue
        if pid is None or started is None or not prs or not alive(pid):
            continue
        live.append((started, pid, step, prs))
    if not live:
        return None
    live.sort(key=lambda t: (t[0], t[1]))
    prs_all = [x for t in live for x in t[3]]
    started = live[0][0]
    step = "merge" if any(t[2] == "merge" for t in live) else "gate"
    return {"pid": live[0][1], "started_at": started, "step": step, "prs": prs_all,
            "cards": [x["card"] for x in prs_all if x["card"] is not None], "elapsed_s": max(0, int(now) - started)}


def read_queued_cards(common_dir: Path | None) -> dict[int, int]:
    """card -> PR for every PR the merge queue last saw labelled `merge-queue` (`merge-queue.labeled`: `<PR> <head> <epoch> <ref>`)."""
    if common_dir is None:
        return {}
    try:
        text = (common_dir / "super-board" / "merge-queue.labeled").read_text()
    except OSError:
        return {}
    out: dict[int, int] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0].isdigit():
            card = _branch_card(parts[3])
            if card is not None:
                out[card] = int(parts[0])
    return out


def train_tag_for(train: dict[str, Any] | None, queued: dict[int, int]) -> Callable[[int], str]:
    """Review-card tag: in the running train -> gate/merge, queued but not in the train -> waiting."""
    in_train = set(train["cards"]) if train else set()

    def tag(n: int) -> str:
        if n in in_train:
            return "🚂 merging" if train and train["step"] == "merge" else "🚂 merge gate"
        if n in queued:
            return "⏳ wait train"
        return ""

    return tag


def train_line(train: dict[str, Any]) -> str:
    cards = " ".join(f"#{c}" for c in train["cards"]) or " ".join(f"PR#{x['pr']}" for x in train["prs"])
    step = "merge" if train["step"] == "merge" else "gate --full"
    return f"🚂 Merge train: {cards} · {step} · {train['elapsed_s'] // 60}m"


def render_collapsed(label: str, lane_items: list[dict[str, Any]]) -> str:
    """One line of issue numbers, newest first, `… +N more` past 76 cols."""
    out = [box_top(label, len(lane_items))]
    if not lane_items:
        out.append(box_line("(empty)"))
    else:
        nums = [f"#{x['number']}" for x in lane_items]
        tail = "   " + COLLAPSED_TAIL[label]
        accum: list[str] = []
        for i, x in enumerate(nums):
            remaining = len(nums) - i - 1
            candidate = " ".join(accum + [x])
            proposed = candidate + (f" … +{remaining} more" if remaining > 0 else "") + tail
            if visual_width(proposed) > 76:
                break
            accum.append(x)
        remaining = len(nums) - len(accum)
        out.append(box_line(" ".join(accum) + (f" … +{remaining} more" if remaining > 0 else "") + tail))
    out.append(box_bot())
    return "\n".join(out)


def render_kanban(
    by_status: dict[str, list[dict[str, Any]]],
    glyph_for: Callable[[int], str],
    reason_glyph_for: Callable[[int], str],
    review_tag_for: Callable[[int], str] | None = None,
) -> str:
    """The kanban boxes in BOARD_ORDER. Pure: lookups come in as callables."""
    boxes: list[str] = []
    order = list(BOARD_ORDER)
    order[order.index("Done"):order.index("Done")] = [s for s in by_status if s not in BOARD_ORDER and by_status[s]]
    for label in order:
        lane_items = by_status.get(label, [])
        if label in COLLAPSED_TAIL:
            boxes.append(render_collapsed(label, lane_items))
            continue
        out = [box_top(label, len(lane_items))]
        if not lane_items:
            out.append(box_line("(empty)"))
        for it in lane_items:
            n = it["number"]
            if label == "Blocked":
                out.append(box_line(f"{reason_glyph_for(n)} #{n}  {it['title']}"))
                continue
            left = f"{glyph_for(n)} #{n}  {it['title']}"
            suffix = rebuild_suffix(it)
            if label == "Review" and review_tag_for:
                suffix = " ".join(x for x in (review_tag_for(n), suffix) if x)
            if suffix:
                budget = 76 - visual_width(suffix) - 1
                if visual_width(left) > budget:
                    left = truncate_to(left, budget)
                pad = max(1, 76 - visual_width(left) - visual_width(suffix))
                out.append(box_line(left + (" " * pad) + suffix))
            else:
                out.append(box_line(left))
        out.append(box_bot())
        boxes.append("\n".join(out))
    return "\n".join(boxes)


def main() -> int:
    config_slug = resolve_config_slug(sys.argv)
    if not valid_slug(config_slug):
        print(
            f"invalid config slug: {config_slug!r} "
            f"(allowed chars: letters, digits, '.', '_', '-')",
            file=sys.stderr,
        )
        return 64
    config_path = Path(f".claude/super-board/configs/{config_slug}.json")
    if not config_path.is_file():
        print(f"config not found: {config_path}", file=sys.stderr)
        return 66

    cfg = json.loads(config_path.read_text())
    project_owner: str = cfg["project"]["owner"]
    project_number: int = int(cfg["project"]["number"])
    runs_dir = cfg.get("paths", {}).get("runs_dir", "docs/super-board/runs")
    run_date = datetime.date.today().isoformat()
    manifest_path = Path(runs_dir) / f"{run_date}-{config_slug}.md"

    # ── fetch project items (paginated) ──
    def fetch_page(after: str | None) -> dict[str, Any]:
        args = [
            "api", "graphql",
            "-f", f"query={ITEMS_QUERY}",
            "-F", f"owner={project_owner}",
            "-F", f"number={project_number}",
        ]
        if after:
            # First page leaves `$after` unset → GraphQL defaults to null.
            args += ["-F", f"after={after}"]
        out = gh(*args)
        payload: dict[str, Any] = json.loads(out)
        if payload.get("errors"):
            print("graphql returned errors:", file=sys.stderr)
            for err in payload["errors"]:
                print(f"  - {err.get('message')}", file=sys.stderr)
            sys.exit(67)
        return payload

    items_raw, hit_cap = paginate_items(fetch_page)
    if hit_cap:
        print(
            f"warning: stopped after {MAX_ITEM_PAGES * 100} items — "
            f"kanban may not show every card",
            file=sys.stderr,
        )

    items: list[dict[str, Any]] = []
    for n in items_raw:
        c = n.get("content") or {}
        if not c.get("number"):
            continue
        items.append({
            "number": c["number"],
            "title": sanitize_title(c.get("title") or ""),
            "labels": [
                l["name"]
                for l in (c.get("labels", {}).get("nodes") or [])
                if l.get("name")
            ],
            "status": field_status(n),
        })

    by_status = group_by_status(items)

    # ── fetch reason-tag comments for Blocked only ──
    # Skip silently on error so a stale token doesn't break the rest of the
    # snapshot. The body is capped at 4000 chars; emojis in the locked
    # vocabulary land at the top of any well-formed reason-tag comment.
    reasons: dict[int, str] = {}
    blocked_comments: dict[int, list[dict[str, Any]]] = {}
    for it in by_status["Blocked"]:
        n = it["number"]
        out = gh("issue", "view", str(n), "--json", "comments", check=False)
        if not out:
            continue
        try:
            comments = json.loads(out).get("comments") or []
        except json.JSONDecodeError:
            continue
        comments.sort(key=lambda c: c.get("createdAt", ""))
        blocked_comments[n] = comments
        body = (comments[-1].get("body") if comments else "") or ""
        reasons[n] = body[:4000]

    # ── parse manifest ──
    manifest_text = manifest_path.read_text() if manifest_path.is_file() else ""
    now_epoch = int(time.time())
    state = parse_manifest(manifest_text, run_date)
    inflight = state["inflight"]
    recents = state["recents"][-5:][::-1]  # last 5, newest first
    last_tick = state["last_tick"]
    start_hms = state["start_hms"]
    exited = state["exited"]
    reaped_count = state["reaped_count"]

    # ── tiny closures over items / inflight / now_epoch ──
    def item_by_number(n: int) -> dict[str, Any] | None:
        return next((i for i in items if i["number"] == n), None)

    def glyph_for_issue(n: int) -> str:
        for lane, v in inflight.items():
            if v["issue"] == str(n):
                return LANE_GLYPH[lane]
        return "  "

    def worker_dur(hms: str) -> str:
        d = now_epoch - hms_to_epoch(run_date, hms)
        if d < 3600:
            return f"{d // 60}m"
        if d < 86400:
            return f"{d // 3600}h"
        return f"{d // 86400}d"

    def delta_ago(hms: str | None) -> str:
        if not hms:
            return "?"
        d = now_epoch - hms_to_epoch(run_date, hms)
        if d < 90:
            return f"{d}s ago"
        if d < 5400:
            return f"{d // 60}m ago"
        if d < 86400:
            return f"{d // 3600}h {(d % 3600) // 60}m ago"
        return f"{d // 86400}d ago"

    def t_minus(ep: int) -> str:
        d = now_epoch - ep
        if d < 60:
            return "T-1m" if d >= 30 else "T-0m"
        if d < 3600:
            return f"T-{d // 60}m"
        if d < 86400:
            return f"T-{d // 3600}h"
        return f"T-{d // 86400}d"

    def reason_for_issue(n: int) -> tuple[str, str]:
        return reason_for(reasons.get(n, ""))

    # ── header ──
    proj = cfg["project"]
    mode_label = "human-approves" if cfg.get("human_approves_merge") else "auto-merge"
    tg = cfg.get("truth_gate", "off")
    tt = cfg.get("truth_threshold", 70)
    gate_label = {"off": "off", "always": "always"}.get(tg, f"non-trivial (≥{tt})")
    bot_login = (
        cfg.get("notifications", {}).get("bot_identity")
        or cfg.get("claim", {}).get("assignee_login")
        or "?"
    )
    max_workers = cfg.get("max_workers", 3)

    print(f"📊 super-board · {proj['title']} (#{proj['number']})")
    print("─" * 80)
    print(f"config: {config_slug}   labels: qa · bug · feature   base: {cfg.get('base_branch', '?')}")
    print(f"mode:   {mode_label:<22} truth gate: {gate_label}")
    print()

    # ── kanban ──
    common_dir = git_common_dir()
    train = read_merge_train(common_dir, time.time())
    print(render_kanban(by_status, glyph_for_issue, lambda n: reason_for_issue(n)[0],
                        train_tag_for(train, read_queued_cards(common_dir))))

    # ── workers ──
    print()
    active = len(inflight)
    run_active = bool(last_tick) and not exited

    if not run_active and active == 0:
        print(f"▎Workers  (claim: {bot_login})")
        print("   (no active run — `super-board run` to start)")
    else:
        print(f"▎Workers  (claim: {bot_login} · {active}/{max_workers} active)")
        if active == 0:
            print("   (idle)")
        else:
            for lane in sorted(inflight, key=LANE_ORDER.index):
                v = inflight[lane]
                glyph = LANE_GLYPH[lane]
                role = LANE_ROLE[lane]
                item = item_by_number(int(v["issue"]))
                extras: list[str] = []
                if item:
                    extras = [
                        l for l in item["labels"]
                        if l.startswith("loop:") and not l.startswith("loop:in-")
                    ]
                extra = (" · " + ", ".join(extras)) if extras else ""
                print(
                    f"   {glyph} {role}  #{v['issue']}  attempt {attempt_str(item)} · "
                    f"{worker_dur(v['ts'])}{extra}"
                )
    if train:
        print(f"   {train_line(train)}")

    # ── waiting on a person (#95): its own group, out of the block reasons ──
    print()
    print("▎Waiting on you  (needs-you / human-gated — Ready: remove the label to release it · 🙋 Blocked: comment done"
          " · 📱 needs-device: plug in a real device)")
    no_device = no_real_device(items)
    person = waiting_on_person(items, no_device=no_device)
    if not person:
        print("   (none)")
    for it in person:
        device = " · 📱 no real device online" if no_device and held_for_device(it) else ""
        print(f"   #{it['number']:<5} {it['status']:<9} {it['title']}{device}")
    person_numbers = {it["number"] for it in person}

    # ── block reasons ──
    print()
    print("▎Block reasons")
    waiting_cards = [it for it in waiting_on_cards(items) if it["number"] not in person_numbers]
    waiting_numbers = {it["number"] for it in waiting_cards}
    blockers = [it for it in by_status["Blocked"] if it["number"] not in person_numbers | waiting_numbers]
    unreadable, blockers = split_unreadable_blocked_by(blockers, blocked_comments)
    print(f"   {WAITING_LABEL} ×{len(waiting_cards)}  (the sweep releases them when the blocker closes — nothing to do)"
          + ("  " + ", ".join(f"#{it['number']}" for it in waiting_cards) if waiting_cards else ""))
    for n, why in sorted(unreadable.items(), reverse=True):
        print(f"   ⚠ blocked-by không đọc được  #{n}  {why}")
    if not blockers:
        print("   (none)")
    else:
        groups: dict[str, dict[str, Any]] = {}
        for it in blockers:
            em, txt = reason_for_issue(it["number"])
            g = groups.setdefault(em, {"text": txt, "issues": []})
            g["issues"].append(f"#{it['number']}")
        for em, g in sorted(groups.items(), key=lambda kv: -len(kv[1]["issues"])):
            issues_str = ", ".join(g["issues"])
            print(f"   {em} ×{len(g['issues'])}  {g['text']:<18}  {issues_str}")

    # ── recent events ──
    print()
    print("▎Recent  (last 5 manifest events)")
    if not recents:
        print("   (no manifest events yet)")
    else:
        for r in recents:
            t = t_minus(r["epoch"])
            # Dispatch detail (`attempt N/3`) is filled in at render time
            # because the manifest doesn't encode the rebuild count at
            # dispatch time — the number shown reflects the issue's *current*
            # label. Live workers in the §Workers block above use the same
            # source, so the two stay consistent with each other.
            detail = r["detail"]
            if r["verb"] == "dispatch" and not detail:
                issue_num = int(r["issue"].lstrip("#"))
                detail = f"attempt {attempt_str(item_by_number(issue_num))}"
            if r["target"]:
                print(
                    f"   {t:<7} {r['glyph']} {r['verb']:<9} {r['issue']:<4} → "
                    f"{r['target']:<9} {detail}"
                )
            else:
                print(
                    f"   {t:<7} {r['glyph']} {r['verb']:<9} {r['issue']:<4}   "
                    f"        {detail}"
                )

    # ── health ──
    print()
    print("▎Health")
    if run_active:
        print(
            f"   last tick: {delta_ago(last_tick)}    run started: {delta_ago(start_hms)}"
            f"    workers: {active}/{max_workers}    worktrees cleaned: {reaped_count}"
        )
    elif exited and start_hms:
        print(
            f"   last run: completed {delta_ago(last_tick or start_hms)}    "
            f"workers: 0/{max_workers} idle"
        )
    else:
        print(f"   no run today    workers: 0/{max_workers} idle")

    return 0


if __name__ == "__main__":
    sys.exit(main())
