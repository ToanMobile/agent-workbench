[14:32:04] super-board run started — config=agent-workbench base=main tick=120s max_workers=3 no_progress_cycles=6 max_dispatches=0
[14:32:09] initial Ready count: 1
[14:32:11] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:32:16] dispatch lane=build issue=#2 pid=1900 claim=ToanMobile
[14:34:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#2) q_idle=1(#_) r_idle=1(#_)
[14:35:46] STOP 📋 1 in-flight worker(s) to wrap up
[14:35:46] STOP 
[14:35:46] STOP ─── #2 (lane=build, pid=1900) ───
[14:35:49] STOP   💬 issue comment posted on #2
[14:35:55] STOP   🔓 released assignee + lane labels on #2
[14:35:56] STOP   ☠ worker(build/#2) pid=1900 SIGTERMed
[14:35:56] STOP 
[14:35:56] STOP 🧹 sweeping untracked claude -p super-board workers
[14:35:56] STOP   ⊘ orphan-worker pid=1900 already dead
[14:35:56] STOP 
[14:35:56] STOP 🛑 stopping dispatcher loop
[14:35:57] STOP   ☠ dispatcher pid=1354 SIGTERMed
[14:35:57] STOP 
[14:35:57] STOP 🧽 cleared .claude/super-board/inflight
[14:45:22] super-board run started — config=agent-workbench base=main tick=120s max_workers=3 no_progress_cycles=6 max_dispatches=0
[14:45:28] ⚠ stranded #2: kept .claude/worktrees/issue-2-build and Building status — inspect its detached commits/edits/lock before resuming
[14:45:30] initial Ready count: 0
[14:45:33] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:47:35] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:49:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:51:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:53:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:55:47] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:55:47] 🛑 halt — RUNAWAY: no card reached Done in 6 dispatch cycles
[14:55:47]    dispatches=0 reaps=0 cards-landed-this-run=0
[14:55:47]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[14:56:43] super-board run started — config=agent-workbench base=main tick=120s max_workers=3 no_progress_cycles=6 max_dispatches=0
[14:56:49] ℹ stranded #2: keeping existing worktree .claude/worktrees/issue-2-build (branch issue-2-review-gate-authorship) for Builder to resume
[14:56:58] ↩ stranded #2: Building → Ready (branch none)
[14:57:00] initial Ready count: 1
[14:57:02] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:57:08] dispatch lane=build issue=#2 pid=48982 claim=ToanMobile
[14:59:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#2) q_idle=1(#_) r_idle=1(#_)
[15:01:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#2) q_idle=1(#_) r_idle=1(#_)
[15:03:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#2) q_idle=1(#_) r_idle=1(#_)
[15:05:19] reaped stale lock + swept assignee on #2 (pid=48982)
[15:05:21] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#2) q_idle=1(#_) r_idle=1(#_)
[15:05:26] dispatch lane=qa issue=#2 pid=77025 claim=ToanMobile
[15:07:29] 💀 zombie qa worker on #2 (pid=77025) — card moved to 'Review'; killing
[15:07:32] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#2) q_idle=1(#_) r_idle=1(#_)
[15:07:39] dispatch lane=review issue=#2 pid=83291 claim=ToanMobile
[15:07:39] 🛑 halt — RUNAWAY: no card reached Done in 6 dispatch cycles
[15:07:39]    dispatches=3 reaps=1 cards-landed-this-run=0
[15:07:39]    most re-dispatched issues (count issue):
[15:07:39]      3 2
[15:07:39]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[15:07:39] super-board run finished. manifest: docs/super-board/runs/2026-10-16-agent-workbench.md
[15:27:07] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[15:27:10] reaped stale lock + swept assignee on #2 (pid=83291)
[15:27:15] initial Ready count: 3
[15:27:17] tick — Ready=3 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[15:27:22] dispatch lane=review issue=#2 pid=6918 claim=ToanMobile
[15:27:28] dispatch lane=build issue=#3 pid=7792 claim=ToanMobile
[15:28:01] reaped stale lock + swept assignee on #2 (pid=6918)
[15:28:04] tick — Ready=3 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#2)
[15:28:09] dispatch lane=review issue=#2 pid=9599 claim=ToanMobile
[15:28:43] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:29:16] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:29:50] reaped stale lock + swept assignee on #2 (pid=9599)
[15:29:53] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#2)
[15:29:58] dispatch lane=review issue=#2 pid=26944 claim=ToanMobile
[15:30:34] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:31:08] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:31:41] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:32:15] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=0(#2)
[15:32:49] reaped stale lock + swept assignee on #2 (pid=26944)
[15:32:51] 💀 zombie build worker on #3 (pid=7792) — card moved to 'Blocked'; killing
[15:32:55] tick — Ready=2 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#2)
[15:32:55] ⚠ block-rate alert: 1/3 (33%)
[15:32:59] dispatch lane=review issue=#2 pid=26319 claim=ToanMobile
[15:33:05] dispatch lane=build issue=#4 pid=26830 claim=ToanMobile
[15:33:39] tick — Ready=2 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:34:12] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:34:46] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:35:20] reaped stale lock + swept assignee on #2 (pid=26319)
[15:35:22] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#2)
[15:35:28] dispatch lane=review issue=#2 pid=44652 claim=ToanMobile
[15:36:01] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:36:35] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:37:09] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:37:43] reaped stale lock + swept assignee on #2 (pid=44652)
[15:37:46] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#2)
[15:37:51] dispatch lane=review issue=#2 pid=89123 claim=ToanMobile
[15:38:25] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:38:59] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:39:33] reaped stale lock + swept assignee on #2 (pid=89123)
[15:39:36] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#2)
[15:39:41] dispatch lane=review issue=#2 pid=12208 claim=ToanMobile
[15:40:16] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:40:50] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:41:23] reaped stale lock + swept assignee on #2 (pid=12208)
[15:41:27] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#2)
[15:41:32] dispatch lane=review issue=#2 pid=28673 claim=ToanMobile
[15:42:06] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:42:39] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:43:13] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:43:47] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#2)
[15:44:21] 💀 zombie review worker on #2 (pid=28673) — card moved to 'Blocked'; killing
[15:44:25] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:44:58] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:45:32] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:46:07] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:46:44] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:47:19] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:47:54] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:48:28] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:49:02] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:49:37] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[15:50:11] reaped stale lock + swept assignee on #4 (pid=26830)
[15:50:14] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=1(#4) q_idle=1(#_) r_idle=1(#_)
[15:50:20] dispatch lane=qa issue=#4 pid=90054 claim=ToanMobile
[15:50:25] dispatch lane=build issue=#5 pid=90679 claim=ToanMobile
[15:50:58] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[15:52:06] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[15:52:12] initial Ready count: 2
[15:52:15] tick — Ready=2 Building=0 QA=1 Review=1 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[15:52:22] dispatch lane=review issue=#2 pid=6458 claim=ToanMobile
[15:52:28] dispatch lane=qa issue=#4 pid=7481 claim=ToanMobile
[15:52:35] dispatch lane=build issue=#3 pid=8399 claim=ToanMobile
[15:53:06] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[15:53:37] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[15:54:08] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[15:54:38] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[15:55:11] reaped stale lock + swept assignee on #2 (pid=6458)
[15:55:18] reaped stale lock + swept assignee on #4 (pid=7481)
[15:55:21] tick — Ready=2 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#2)
[15:55:21] ⚠ block-rate alert: 1/2 (50%)
[15:55:26] dispatch lane=review issue=#4 pid=37097 claim=ToanMobile
[15:56:00] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:56:35] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:57:09] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:57:43] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:58:17] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:58:52] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[15:59:28] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:00:06] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:00:42] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:01:19] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:01:57] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:02:35] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:03:14] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:03:53] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:04:30] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:05:07] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:05:42] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:06:16] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:06:51] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:07:25] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:07:59] reaped stale lock + swept assignee on #4 (pid=37097)
[16:08:02] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:08:07] dispatch lane=review issue=#4 pid=20309 claim=ToanMobile
[16:08:43] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:09:19] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=0(#4)
[16:09:54] reaped stale lock + swept assignee on #4 (pid=20309)
[16:09:57] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:10:33] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:11:09] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:11:44] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:12:19] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:12:55] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:13:30] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:14:04] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:14:38] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:15:13] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:15:47] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:16:21] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:17:01] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:17:40] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:18:18] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:18:57] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:19:36] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:20:17] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:20:54] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:21:30] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:22:06] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:22:40] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:23:17] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:23:52] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#3) q_idle=1(#4) r_idle=1(#4)
[16:24:25] tick — Ready=10 Building=0 QA=1 Review=0 Blocked=2 lanes: b_idle=1(#3) q_idle=1(#4) r_idle=1(#4)
[16:24:31] dispatch lane=qa issue=#3 pid=41759 claim=ToanMobile
[16:24:36] dispatch lane=build issue=#5 pid=42211 claim=ToanMobile
[17:11:47] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[17:11:51] initial Ready count: 2
[17:11:53] tick — Ready=2 Building=0 QA=1 Review=2 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[17:11:58] dispatch lane=review issue=#4 pid=43979 claim=ToanMobile
[17:12:04] dispatch lane=qa issue=#3 pid=49177 claim=ToanMobile
[17:12:09] dispatch lane=build issue=#5 pid=58826 claim=ToanMobile
[17:12:40] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:13:11] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:13:41] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:14:12] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:14:42] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:15:13] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:15:46] reaped stale lock + swept assignee on #4 (pid=43979)
[17:15:50] tick — Ready=1 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#5) q_idle=0(#3) r_idle=1(#4)
[17:16:02] dispatch lane=review issue=#4 pid=98136 claim=ToanMobile
[17:16:32] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:17:04] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:17:35] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:18:05] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:18:36] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:19:09] reaped stale lock + swept assignee on #4 (pid=98136)
[17:19:13] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#3) r_idle=1(#4)
[17:19:13] ⚠ block-rate alert: 1/2 (50%)
[17:19:19] dispatch lane=review issue=#2 pid=49922 claim=ToanMobile
[17:19:50] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:20:21] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:20:53] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:21:25] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:21:58] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:22:29] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:23:00] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:23:31] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:24:01] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:24:33] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:25:04] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:25:36] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:26:07] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:26:39] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:27:11] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:27:43] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:28:17] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:28:49] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:29:22] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:29:56] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:30:28] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:31:01] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:31:33] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:32:04] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:32:35] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:33:05] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:33:36] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:34:07] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:34:38] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:35:08] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:35:39] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:36:12] reaped stale lock + swept assignee on #3 (pid=49177)
[17:36:15] 💀 zombie build worker on #5 (pid=58826) — card moved to 'Blocked'; killing
[17:36:19] 💀 zombie review worker on #2 (pid=49922) — card moved to 'Blocked'; killing
[17:36:24] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=2 lanes: b_idle=1(#_) q_idle=1(#3) r_idle=1(#_)
[17:36:30] dispatch lane=review issue=#4 pid=78489 claim=ToanMobile
[17:36:37] dispatch lane=qa issue=#3 pid=86964 claim=ToanMobile
[17:36:43] dispatch lane=build issue=#35 pid=95430 claim=ToanMobile
[17:37:14] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:37:45] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:38:16] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[17:38:50] reaped stale lock + swept assignee on #35 (pid=95430)
[17:38:54] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=3 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=0(#4)
[17:39:27] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=3 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=0(#4)
[17:40:02] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=3 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=0(#4)
[17:40:36] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=3 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=0(#4)
[17:41:10] 💀 zombie review worker on #4 (pid=78489) — card moved to 'Blocked'; killing
[17:41:14] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=1(#_)
[17:41:49] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#35) q_idle=0(#3) r_idle=1(#_)
[17:42:22] 💀 zombie qa worker on #3 (pid=86964) — card moved to 'Review'; killing
[17:42:26] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[17:42:32] dispatch lane=review issue=#3 pid=34652 claim=ToanMobile
[17:43:06] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:43:40] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:44:13] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:44:48] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:45:23] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:48:47] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:51:20] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:51:54] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:52:28] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:53:01] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:53:34] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:54:08] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:54:41] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:55:14] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:55:48] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:56:21] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:56:54] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:57:27] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=4 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=0(#3)
[17:58:00] 💀 zombie review worker on #3 (pid=34652) — card moved to 'Blocked'; killing
[17:58:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[17:58:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[17:59:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[17:59:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:00:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:00:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:01:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:01:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:02:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:03:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:03:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:04:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:04:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:05:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:06:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:06:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:07:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:07:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:08:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:08:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:09:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[18:09:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#35) q_idle=1(#_) r_idle=1(#_)
[19:55:22] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[19:55:27] initial Ready count: 0
[19:55:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:56:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:56:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:57:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:57:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:58:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:58:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[19:59:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:00:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:00:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:01:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:01:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:02:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:02:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:03:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:03:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:04:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:05:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:05:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:06:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=5 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:06:41] tick — Ready=1 Building=0 QA=0 Review=2 Blocked=2 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[20:06:47] dispatch lane=review issue=#4 pid=62094 claim=ToanMobile
[20:06:53] dispatch lane=build issue=#5 pid=63054 claim=ToanMobile
[20:07:26] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:07:58] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:08:31] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:09:03] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:09:36] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:10:09] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:10:42] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:11:17] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:11:50] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:12:23] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:12:57] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:13:31] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:14:04] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:14:38] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:15:11] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:15:46] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:16:22] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:16:55] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:17:29] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:18:03] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:18:38] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:19:14] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:19:48] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:20:22] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:20:56] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:21:29] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:22:03] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[20:22:37] 💀 zombie review worker on #4 (pid=62094) — card moved to 'Blocked'; killing
[20:22:41] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:22:47] dispatch lane=review issue=#2 pid=81867 claim=ToanMobile
[20:23:20] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:23:55] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:24:30] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:25:04] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:25:38] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:26:12] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:26:45] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:27:19] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:27:52] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:28:24] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:28:57] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:29:30] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:30:04] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:30:39] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:31:13] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:31:46] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:32:19] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#2)
[20:32:52] 💀 zombie review worker on #2 (pid=81867) — card moved to 'Ready'; killing
[20:32:56] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:33:29] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:34:03] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:34:36] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:35:10] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:35:43] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:36:17] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:36:50] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:37:24] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:37:57] tick — Ready=3 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:38:32] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:39:06] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:39:41] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:40:15] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:40:16] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[20:40:16]    dispatches=3 reaps=0 cards-landed-this-run=0
[20:40:16]    most re-dispatched issues (count issue):
[20:40:16]      1 5
[20:40:16]      1 4
[20:40:16]      1 2
[20:40:16]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[20:40:47] tick — runaway pause (269s left) — skipping GraphQL fetch, sleeping 30s
[20:41:17] tick — runaway pause (239s left) — skipping GraphQL fetch, sleeping 30s
[20:41:47] tick — runaway pause (209s left) — skipping GraphQL fetch, sleeping 30s
[20:42:17] tick — runaway pause (179s left) — skipping GraphQL fetch, sleeping 30s
[20:42:47] tick — runaway pause (149s left) — skipping GraphQL fetch, sleeping 30s
[20:43:18] tick — runaway pause (118s left) — skipping GraphQL fetch, sleeping 30s
[20:43:48] tick — runaway pause (88s left) — skipping GraphQL fetch, sleeping 30s
[20:44:19] tick — runaway pause (57s left) — skipping GraphQL fetch, sleeping 30s
[20:44:49] tick — runaway pause (27s left) — skipping GraphQL fetch, sleeping 30s
[20:45:22] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:45:57] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:46:31] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:47:05] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:47:39] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:48:13] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:48:48] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:49:22] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[20:49:57] reaped stale lock + swept assignee on #5 (pid=63054)
[20:49:59] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#5) q_idle=1(#_) r_idle=1(#_)
[20:50:06] dispatch lane=build issue=#3 pid=52008 claim=ToanMobile
[20:50:40] reaped stale lock + swept assignee on #3 (pid=52008)
[20:50:43] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:50:49] dispatch lane=build issue=#3 pid=23217 claim=ToanMobile
[20:51:22] reaped stale lock + swept assignee on #3 (pid=23217)
[20:51:25] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:51:33] dispatch lane=build issue=#3 pid=97715 claim=ToanMobile
[20:52:07] reaped stale lock + swept assignee on #3 (pid=97715)
[20:52:10] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:52:17] dispatch lane=build issue=#3 pid=41348 claim=ToanMobile
[20:52:50] reaped stale lock + swept assignee on #3 (pid=41348)
[20:52:53] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:52:59] dispatch lane=build issue=#3 pid=44239 claim=ToanMobile
[20:53:32] reaped stale lock + swept assignee on #3 (pid=44239)
[20:53:34] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:53:41] dispatch lane=build issue=#3 pid=47039 claim=ToanMobile
[20:54:14] reaped stale lock + swept assignee on #3 (pid=47039)
[20:54:17] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:54:23] dispatch lane=build issue=#3 pid=50026 claim=ToanMobile
[20:54:56] reaped stale lock + swept assignee on #3 (pid=50026)
[20:54:59] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:55:04] dispatch lane=build issue=#3 pid=9445 claim=ToanMobile
[20:55:38] reaped stale lock + swept assignee on #3 (pid=9445)
[20:55:41] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:55:47] dispatch lane=build issue=#3 pid=97015 claim=ToanMobile
[20:56:20] reaped stale lock + swept assignee on #3 (pid=97015)
[20:56:22] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:56:28] dispatch lane=build issue=#3 pid=77853 claim=ToanMobile
[20:57:01] reaped stale lock + swept assignee on #3 (pid=77853)
[20:57:05] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[20:57:12] dispatch lane=build issue=#3 pid=3355 claim=ToanMobile
[20:57:45] reaped stale lock + swept assignee on #3 (pid=3355)
[20:57:47] STOP 
[20:57:47] STOP 🛑 stopping dispatcher loop
[20:57:48] STOP   ☠ dispatcher pid=56616 SIGTERMed
[20:57:49] STOP   ☠ dispatcher pid=57027 SIGTERMed
[20:57:50] STOP   ☠ dispatcher pid=61468 SIGTERMed
[20:57:51] STOP   ☠ dispatcher pid=65936 SIGTERMed
[21:29:15] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[21:29:21] ℹ stranded #5: keeping existing worktree .claude/worktrees/issue-5-build (branch issue-5-push-gate-linked-worktree-receipt) for Builder to resume
[21:29:31] ↩ stranded #5: Building → Ready (branch issue-5-push-gate-linked-worktree-receipt)
[21:29:33] initial Ready count: 7
[21:29:38] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[21:29:44] dispatch lane=build issue=#3 pid=25094 claim=ToanMobile
[21:30:18] reaped stale lock + swept assignee on #3 (pid=25094)
[21:30:21] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:30:28] dispatch lane=build issue=#3 pid=15953 claim=ToanMobile
[21:31:01] reaped stale lock + swept assignee on #3 (pid=15953)
[21:31:04] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:31:10] dispatch lane=build issue=#3 pid=4128 claim=ToanMobile
[21:31:46] reaped stale lock + swept assignee on #3 (pid=4128)
[21:31:49] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:31:55] dispatch lane=build issue=#3 pid=76941 claim=ToanMobile
[21:32:28] reaped stale lock + swept assignee on #3 (pid=76941)
[21:32:30] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:32:37] dispatch lane=build issue=#3 pid=80636 claim=ToanMobile
[21:33:10] reaped stale lock + swept assignee on #3 (pid=80636)
[21:33:13] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:33:19] dispatch lane=build issue=#3 pid=49297 claim=ToanMobile
[21:33:53] reaped stale lock + swept assignee on #3 (pid=49297)
[21:33:56] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:34:03] dispatch lane=build issue=#3 pid=33378 claim=ToanMobile
[21:34:36] reaped stale lock + swept assignee on #3 (pid=33378)
[21:34:39] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:34:45] dispatch lane=build issue=#3 pid=15614 claim=ToanMobile
[21:35:19] reaped stale lock + swept assignee on #3 (pid=15614)
[21:35:22] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:35:29] dispatch lane=build issue=#3 pid=77814 claim=ToanMobile
[21:36:02] reaped stale lock + swept assignee on #3 (pid=77814)
[21:36:05] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:36:12] dispatch lane=build issue=#3 pid=57068 claim=ToanMobile
[21:36:46] reaped stale lock + swept assignee on #3 (pid=57068)
[21:36:49] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:36:56] dispatch lane=build issue=#3 pid=17734 claim=ToanMobile
[21:37:30] reaped stale lock + swept assignee on #3 (pid=17734)
[21:37:34] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:37:41] dispatch lane=build issue=#3 pid=70950 claim=ToanMobile
[21:38:14] reaped stale lock + swept assignee on #3 (pid=70950)
[21:38:18] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:38:24] dispatch lane=build issue=#3 pid=30577 claim=ToanMobile
[21:38:58] reaped stale lock + swept assignee on #3 (pid=30577)
[21:39:01] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:39:07] dispatch lane=build issue=#3 pid=76345 claim=ToanMobile
[21:39:41] reaped stale lock + swept assignee on #3 (pid=76345)
[21:39:44] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:39:50] dispatch lane=build issue=#3 pid=46351 claim=ToanMobile
[21:40:24] reaped stale lock + swept assignee on #3 (pid=46351)
[21:40:27] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:40:32] dispatch lane=build issue=#3 pid=31344 claim=ToanMobile
[21:41:06] reaped stale lock + swept assignee on #3 (pid=31344)
[21:41:08] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:41:14] dispatch lane=build issue=#3 pid=80656 claim=ToanMobile
[21:41:47] reaped stale lock + swept assignee on #3 (pid=80656)
[21:41:50] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:41:55] dispatch lane=build issue=#3 pid=15926 claim=ToanMobile
[21:42:28] reaped stale lock + swept assignee on #3 (pid=15926)
[21:42:31] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:42:37] dispatch lane=build issue=#3 pid=22528 claim=ToanMobile
[21:43:10] reaped stale lock + swept assignee on #3 (pid=22528)
[21:43:12] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:43:19] dispatch lane=build issue=#3 pid=26092 claim=ToanMobile
[21:43:52] reaped stale lock + swept assignee on #3 (pid=26092)
[21:43:54] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:44:00] dispatch lane=build issue=#3 pid=29918 claim=ToanMobile
[21:44:32] reaped stale lock + swept assignee on #3 (pid=29918)
[21:44:35] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:44:41] dispatch lane=build issue=#3 pid=37317 claim=ToanMobile
[21:45:13] reaped stale lock + swept assignee on #3 (pid=37317)
[21:45:17] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:45:23] dispatch lane=build issue=#3 pid=42702 claim=ToanMobile
[21:45:57] reaped stale lock + swept assignee on #3 (pid=42702)
[21:45:59] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:46:05] dispatch lane=build issue=#3 pid=46612 claim=ToanMobile
[21:46:39] reaped stale lock + swept assignee on #3 (pid=46612)
[21:46:41] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:46:47] dispatch lane=build issue=#3 pid=50932 claim=ToanMobile
[21:47:19] reaped stale lock + swept assignee on #3 (pid=50932)
[21:47:22] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:47:28] dispatch lane=build issue=#3 pid=54544 claim=ToanMobile
[21:48:01] reaped stale lock + swept assignee on #3 (pid=54544)
[21:48:04] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:48:09] dispatch lane=build issue=#3 pid=59733 claim=ToanMobile
[21:48:42] reaped stale lock + swept assignee on #3 (pid=59733)
[21:48:45] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:48:51] dispatch lane=build issue=#3 pid=65751 claim=ToanMobile
[21:49:24] reaped stale lock + swept assignee on #3 (pid=65751)
[21:49:27] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:49:32] dispatch lane=build issue=#3 pid=76822 claim=ToanMobile
[21:50:05] reaped stale lock + swept assignee on #3 (pid=76822)
[21:50:08] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:50:13] dispatch lane=build issue=#3 pid=83572 claim=ToanMobile
[21:50:46] reaped stale lock + swept assignee on #3 (pid=83572)
[21:50:49] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:50:54] dispatch lane=build issue=#3 pid=91024 claim=ToanMobile
[21:51:27] reaped stale lock + swept assignee on #3 (pid=91024)
[21:51:30] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[21:51:35] dispatch lane=build issue=#3 pid=96010 claim=ToanMobile
[21:52:10] super-board run started — config=agent-workbench base=main tick=30s max_workers=3 no_progress_cycles=60 max_dispatches=0
[21:52:10] account finos hit its limit — paused until 22:50; next dispatch takes the pool's next account
[21:52:13] reaped stale lock + swept assignee on #3 (pid=96010)
[21:52:17] initial Ready count: 7
[21:52:20] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[21:52:26] dispatch lane=build issue=#3 pid=99106 claim=ToanMobile
[21:52:59] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:53:32] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:54:06] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:54:40] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:55:14] tick — Ready=7 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:55:48] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:56:22] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:56:56] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:57:31] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:58:06] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:58:41] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:59:18] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[21:59:54] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:00:29] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:01:05] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:01:40] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:02:18] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:02:55] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:03:32] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:04:10] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:04:44] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:05:19] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:05:55] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:06:32] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:07:09] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:07:46] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:08:23] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:09:01] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:09:39] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:10:16] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:10:56] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:11:38] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:12:20] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:13:01] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:13:40] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:14:19] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:14:55] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:15:35] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:16:10] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:16:44] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:17:19] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:17:54] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:18:29] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:19:06] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:19:42] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:20:17] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:20:53] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:21:28] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:22:02] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:22:37] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:23:12] tick — Ready=6 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#3) q_idle=1(#_) r_idle=1(#_)
[22:23:47] reaped stale lock + swept assignee on #3 (pid=99106)
[22:23:51] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#3) q_idle=1(#_) r_idle=1(#_)
[22:24:01] dispatch lane=qa issue=#3 pid=85346 claim=ToanMobile
[22:24:09] dispatch lane=build issue=#4 pid=93396 claim=ToanMobile
[22:24:46] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:25:22] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:25:56] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:26:30] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:27:03] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:27:37] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:28:11] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:28:11] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[22:28:11]    dispatches=3 reaps=2 cards-landed-this-run=0
[22:28:11]    most re-dispatched issues (count issue):
[22:28:11]      2 3
[22:28:11]      1 4
[22:28:11]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[22:28:41] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[22:29:12] tick — runaway pause (239s left) — board read every 3 ticks, sleeping 30s
[22:29:47] tick — runaway pause (204s left) — board read every 3 ticks, sleeping 30s
[22:30:18] tick — runaway pause (173s left) — board read every 3 ticks, sleeping 30s
[22:30:49] tick — runaway pause (142s left) — board read every 3 ticks, sleeping 30s
[22:31:22] tick — runaway pause (109s left) — board read every 3 ticks, sleeping 30s
[22:31:53] tick — runaway pause (78s left) — board read every 3 ticks, sleeping 30s
[22:32:23] tick — runaway pause (48s left) — board read every 3 ticks, sleeping 30s
[22:33:01] tick — runaway pause (10s left) — board read every 3 ticks, sleeping 30s
[22:33:35] tick — Ready=6 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:34:10] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:34:44] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:35:19] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:35:53] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:36:27] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:37:00] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:37:33] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:38:06] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:38:40] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:39:14] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:39:47] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:40:21] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:40:55] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:41:29] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:42:03] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:42:37] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:43:11] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:43:45] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:44:20] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:44:57] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:45:33] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:46:08] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:46:41] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:47:15] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:47:48] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:48:22] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:48:55] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:49:29] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:50:02] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:50:37] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:51:12] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:51:46] tick — Ready=5 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#4) q_idle=0(#3) r_idle=1(#_)
[22:52:21] 💀 zombie qa worker on #3 (pid=85346) — card moved to 'Review'; killing
[22:52:25] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[22:52:34] dispatch lane=review issue=#3 pid=38863 claim=ToanMobile
[22:53:11] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:53:47] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:54:22] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:54:59] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:55:36] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:56:13] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:56:50] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:57:26] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:58:02] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:58:38] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:59:15] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[22:59:52] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:00:30] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:01:05] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:01:42] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:02:17] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:02:52] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:03:31] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:04:09] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:04:45] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:05:21] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:05:58] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:06:34] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:07:11] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:07:46] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:08:21] tick — Ready=5 Building=1 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=0(#3)
[23:08:22] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[23:08:22]    dispatches=4 reaps=2 cards-landed-this-run=0
[23:08:22]    most re-dispatched issues (count issue):
[23:08:22]      3 3
[23:08:22]      1 4
[23:08:22]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[23:08:53] tick — runaway pause (269s left) — board read every 3 ticks, sleeping 30s
[23:09:24] tick — runaway pause (238s left) — board read every 3 ticks, sleeping 30s
[23:09:58] 💀 zombie review worker on #3 (pid=38863) — card moved to 'Blocked'; killing
[23:10:02] tick — runaway pause (200s left) — board read every 3 ticks, sleeping 30s
[23:10:32] tick — runaway pause (170s left) — board read every 3 ticks, sleeping 30s
[23:11:03] tick — runaway pause (139s left) — board read every 3 ticks, sleeping 30s
[23:11:38] tick — runaway pause (104s left) — board read every 3 ticks, sleeping 30s
[23:12:09] tick — runaway pause (73s left) — board read every 3 ticks, sleeping 30s
[23:12:40] tick — runaway pause (42s left) — board read every 3 ticks, sleeping 30s
[23:13:17] tick — runaway pause (5s left) — board read every 3 ticks, sleeping 30s
[23:13:52] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:14:30] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:15:07] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:15:43] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:16:19] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:16:55] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:17:32] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:18:08] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:18:42] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:19:16] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:19:52] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:20:30] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:21:08] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:21:45] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:22:24] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:23:01] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:23:37] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:24:13] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:24:48] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:25:24] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:26:00] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:26:36] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:27:13] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:27:50] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:28:27] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:29:03] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:29:37] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:30:13] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:30:48] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:31:23] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:31:58] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:32:34] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:33:11] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:33:47] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:34:22] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:34:56] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:35:31] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:36:08] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:36:45] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:37:21] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:37:57] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:38:32] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:39:07] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:39:43] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:40:19] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:40:55] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:41:31] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:42:07] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:42:42] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:43:19] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:43:55] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:44:32] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:45:09] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:45:45] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:46:21] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:46:58] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:47:34] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:48:12] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:48:49] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:49:25] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:49:26] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[23:49:26]    dispatches=4 reaps=2 cards-landed-this-run=0
[23:49:26]    most re-dispatched issues (count issue):
[23:49:26]      3 3
[23:49:26]      1 4
[23:49:26]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[23:49:57] tick — runaway pause (269s left) — board read every 3 ticks, sleeping 30s
[23:50:27] tick — runaway pause (239s left) — board read every 3 ticks, sleeping 30s
[23:51:02] tick — runaway pause (204s left) — board read every 3 ticks, sleeping 30s
[23:51:32] tick — runaway pause (174s left) — board read every 3 ticks, sleeping 30s
[23:52:02] tick — runaway pause (144s left) — board read every 3 ticks, sleeping 30s
[23:52:36] tick — runaway pause (110s left) — board read every 3 ticks, sleeping 30s
[23:53:07] tick — runaway pause (79s left) — board read every 3 ticks, sleeping 30s
[23:53:37] tick — runaway pause (49s left) — board read every 3 ticks, sleeping 30s
[23:54:10] tick — runaway pause (16s left) — board read every 3 ticks, sleeping 30s
[23:54:43] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:55:17] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:55:51] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:56:25] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:56:59] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:57:33] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:58:07] tick — Ready=5 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:58:43] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:59:17] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[23:59:51] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:00:26] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:01:00] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:01:34] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:02:09] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:02:43] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:03:16] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:03:50] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:04:26] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:05:03] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:05:39] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:06:15] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:06:52] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:07:27] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:08:02] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:08:37] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:09:11] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:09:46] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:10:21] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:10:56] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:11:30] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:12:05] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:12:40] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:13:15] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:13:50] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:14:24] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:14:58] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:15:33] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:16:08] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:16:44] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:17:19] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:17:53] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:18:28] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:19:03] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:19:38] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:20:14] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:20:49] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:21:23] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:21:57] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:22:31] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:23:05] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:23:38] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:24:13] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:24:47] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:25:23] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:25:58] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:26:33] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:27:08] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:27:42] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:28:17] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:28:51] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:28:52] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[00:28:52]    dispatches=4 reaps=2 cards-landed-this-run=0
[00:28:52]    most re-dispatched issues (count issue):
[00:28:52]      3 3
[00:28:52]      1 4
[00:28:52]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[00:29:22] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[00:29:52] tick — runaway pause (240s left) — board read every 3 ticks, sleeping 30s
[00:30:25] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[00:30:55] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[00:31:26] tick — runaway pause (146s left) — board read every 3 ticks, sleeping 30s
[00:31:58] tick — runaway pause (114s left) — board read every 3 ticks, sleeping 30s
[00:32:28] tick — runaway pause (84s left) — board read every 3 ticks, sleeping 30s
[00:32:59] tick — runaway pause (53s left) — board read every 3 ticks, sleeping 30s
[00:33:32] tick — runaway pause (20s left) — board read every 3 ticks, sleeping 30s
[00:34:05] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:34:39] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:35:14] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:35:49] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:36:23] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:36:57] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:37:31] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:38:05] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:38:39] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:39:13] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:39:47] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:40:20] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#4) q_idle=1(#_) r_idle=1(#_)
[00:40:54] reaped stale lock + swept assignee on #4 (pid=93396)
[00:40:57] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#4) q_idle=1(#_) r_idle=1(#_)
[00:41:03] dispatch lane=qa issue=#4 pid=48478 claim=ToanMobile
[00:41:08] dispatch lane=build issue=#5 pid=49133 claim=ToanMobile
[00:41:41] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:42:14] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:42:46] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:43:19] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:43:51] tick — Ready=5 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:44:24] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:44:57] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:45:30] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:46:03] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:46:36] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:47:09] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:47:42] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:48:15] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:48:48] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:49:21] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:49:55] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:50:28] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:51:02] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:51:35] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:52:08] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:52:43] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:53:17] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:53:51] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:54:24] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:54:57] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:55:31] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:56:04] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:56:37] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:57:10] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:57:44] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:58:18] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:58:52] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:59:26] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[00:59:59] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:00:33] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:01:06] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:01:38] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:02:14] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:02:47] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#5) q_idle=0(#4) r_idle=1(#_)
[01:03:20] 💀 zombie qa worker on #4 (pid=48478) — card moved to 'Review'; killing
[01:03:24] tick — Ready=4 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=1(#_)
[01:03:29] dispatch lane=review issue=#4 pid=10959 claim=ToanMobile
[01:03:30] reconciled closed #2 -> Done (was 'Ready') — dispatching 0 workers for it
[01:04:14] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:04:48] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:05:21] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:05:56] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:06:30] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:07:03] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:07:37] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:08:10] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:08:44] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:09:17] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:09:51] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:10:25] tick — Ready=3 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:10:58] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:11:32] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:12:05] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:12:39] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:13:13] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:13:46] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:14:20] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:14:53] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#5) q_idle=1(#_) r_idle=0(#4)
[01:15:27] reaped stale lock + swept assignee on #5 (pid=49133)
[01:15:29] tick — Ready=3 Building=0 QA=1 Review=1 Blocked=1 lanes: b_idle=1(#5) q_idle=1(#_) r_idle=0(#4)
[01:15:35] dispatch lane=qa issue=#5 pid=96590 claim=ToanMobile
[01:15:40] dispatch lane=build issue=#12 pid=97412 claim=ToanMobile
[01:16:11] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:16:41] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:17:11] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:17:42] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:18:12] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:18:42] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:19:12] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:19:43] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:20:13] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:20:43] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:21:14] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:21:44] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:22:14] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:22:44] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:23:15] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:23:45] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:24:15] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:24:45] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:25:16] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:25:46] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:26:16] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:26:47] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:27:20] reaped stale lock + swept assignee on #4 (pid=10959)
[01:27:23] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:27:57] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:28:31] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:29:05] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:29:38] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:30:11] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:30:45] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:31:18] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:31:50] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:32:23] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:32:56] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:33:28] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:34:01] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:34:34] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:35:07] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:35:40] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:36:14] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:36:46] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:37:19] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:37:52] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:38:25] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:38:58] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:39:31] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:40:04] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#12) q_idle=0(#5) r_idle=1(#4)
[01:40:37] 💀 zombie qa worker on #5 (pid=96590) — card moved to 'Review'; killing
[01:40:41] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#4)
[01:40:46] dispatch lane=review issue=#5 pid=99285 claim=ToanMobile
[01:41:20] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:41:53] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:42:27] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:43:00] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:43:34] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:44:08] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:44:42] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:45:18] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:45:52] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:46:27] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:47:01] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:47:35] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:48:09] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:48:42] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:49:16] tick — Ready=2 Building=1 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=0(#5)
[01:49:17] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[01:49:17]    dispatches=10 reaps=5 cards-landed-this-run=1
[01:49:17]    most re-dispatched issues (count issue):
[01:49:17]      3 5
[01:49:17]      3 4
[01:49:17]      3 3
[01:49:17]      1 12
[01:49:17]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[01:49:47] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[01:50:17] tick — runaway pause (240s left) — board read every 3 ticks, sleeping 30s
[01:50:50] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[01:51:20] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[01:51:50] tick — runaway pause (147s left) — board read every 3 ticks, sleeping 30s
[01:52:24] tick — runaway pause (113s left) — board read every 3 ticks, sleeping 30s
[01:52:57] reaped stale lock + swept assignee on #12 (pid=97412)
[01:52:57] tick — runaway pause (80s left) — board read every 3 ticks, sleeping 30s
[01:53:27] tick — runaway pause (50s left) — board read every 3 ticks, sleeping 30s
[01:54:00] tick — runaway pause (17s left) — board read every 3 ticks, sleeping 30s
[01:54:32] tick — Ready=2 Building=0 QA=1 Review=1 Blocked=2 lanes: b_idle=1(#12) q_idle=1(#_) r_idle=0(#5)
[01:54:37] dispatch lane=qa issue=#12 pid=93982 claim=ToanMobile
[01:54:43] dispatch lane=build issue=#7 pid=96036 claim=ToanMobile
[01:55:13] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:55:44] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:56:14] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:56:44] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:57:15] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:57:45] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:58:15] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:58:45] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:59:16] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[01:59:46] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:00:16] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:00:47] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:01:17] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:01:48] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:02:18] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:02:49] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:03:20] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:03:50] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:04:21] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:04:51] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:05:21] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:05:52] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:06:22] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:06:52] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:07:22] tick — cap reached (3/3 busy) — skipping GraphQL fetch, sleeping 30s
[02:07:55] reaped stale lock + swept assignee on #5 (pid=99285)
[02:07:58] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:07:58] ⚠ block-rate alert: 3/7 (42%)
[02:08:31] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:09:04] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:09:38] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:10:10] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:10:43] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:11:16] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:11:50] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:12:22] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:12:55] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:13:28] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:14:01] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:14:33] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:15:06] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:15:39] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:16:11] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:16:44] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:17:17] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:17:50] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:18:23] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:18:56] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=0(#12) r_idle=1(#5)
[02:19:29] 💀 zombie qa worker on #12 (pid=93982) — card moved to 'Ready'; killing
[02:19:32] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:20:06] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:20:40] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:21:13] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:21:46] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:22:20] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:22:53] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:23:27] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:24:01] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:24:35] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:25:08] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:25:42] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:26:16] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:26:49] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:27:22] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:27:56] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:28:29] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:29:03] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:29:37] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:30:10] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:30:44] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:31:18] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:31:52] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:32:26] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:32:59] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:33:34] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:34:07] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:34:41] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:35:15] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:35:49] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:36:23] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:36:56] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:37:30] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:38:04] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:38:37] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:39:11] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:39:44] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:40:18] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:40:19] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[02:40:19]    dispatches=12 reaps=7 cards-landed-this-run=1
[02:40:19]    most re-dispatched issues (count issue):
[02:40:19]      3 5
[02:40:19]      3 4
[02:40:19]      3 3
[02:40:19]      2 12
[02:40:19]      1 7
[02:40:19]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[02:40:49] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[02:41:19] tick — runaway pause (240s left) — board read every 3 ticks, sleeping 30s
[02:41:52] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[02:42:22] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[02:42:52] tick — runaway pause (147s left) — board read every 3 ticks, sleeping 30s
[02:43:24] tick — runaway pause (115s left) — board read every 3 ticks, sleeping 30s
[02:43:55] tick — runaway pause (84s left) — board read every 3 ticks, sleeping 30s
[02:44:25] tick — runaway pause (54s left) — board read every 3 ticks, sleeping 30s
[02:44:58] tick — runaway pause (21s left) — board read every 3 ticks, sleeping 30s
[02:45:31] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:46:04] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:46:39] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:47:12] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:47:46] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:48:20] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:48:55] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:49:29] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:50:03] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:50:36] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:51:10] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:51:44] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:52:18] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:52:52] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:53:26] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:54:00] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:54:33] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:55:07] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:55:40] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:56:13] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:56:47] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:57:21] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:57:55] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:58:29] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:59:03] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[02:59:36] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:00:11] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:00:45] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:01:18] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:01:52] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:02:25] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:02:59] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:03:32] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:04:07] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:04:40] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:05:14] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:05:50] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:06:25] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:07:00] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:07:34] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:08:07] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:08:41] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:09:15] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:09:49] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:10:22] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:10:56] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:11:29] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:12:03] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:12:36] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:13:10] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:13:43] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:14:17] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#7) q_idle=1(#_) r_idle=1(#5)
[03:14:48] account finos hit its limit — paused until 03:50; next dispatch takes the pool's next account
[03:14:51] reaped stale lock + swept assignee on #7 (pid=96036)
[03:14:53] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#7) q_idle=1(#_) r_idle=1(#5)
[03:14:58] dispatch lane=build issue=#12 pid=98958 claim=ToanMobile
[03:15:31] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:16:04] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:16:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:17:11] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:17:45] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:18:18] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:18:52] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:18:53] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[03:18:53]    dispatches=13 reaps=8 cards-landed-this-run=1
[03:18:53]    most re-dispatched issues (count issue):
[03:18:53]      3 5
[03:18:53]      3 4
[03:18:53]      3 3
[03:18:53]      3 12
[03:18:53]      1 7
[03:18:53]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[03:19:23] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[03:19:53] tick — runaway pause (240s left) — board read every 3 ticks, sleeping 30s
[03:20:26] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[03:20:56] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[03:21:26] tick — runaway pause (147s left) — board read every 3 ticks, sleeping 30s
[03:21:59] tick — runaway pause (114s left) — board read every 3 ticks, sleeping 30s
[03:22:29] tick — runaway pause (84s left) — board read every 3 ticks, sleeping 30s
[03:22:59] tick — runaway pause (54s left) — board read every 3 ticks, sleeping 30s
[03:23:31] tick — runaway pause (22s left) — board read every 3 ticks, sleeping 30s
[03:24:04] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:24:37] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:25:11] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:25:44] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:26:18] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:26:51] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:27:25] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:27:58] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:28:32] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:29:06] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:29:39] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:30:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:30:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:31:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:31:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:32:27] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:33:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:33:34] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:34:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:34:41] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:35:15] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:35:49] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:36:23] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:36:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:37:31] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:38:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:38:39] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:39:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:39:47] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:40:21] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:40:55] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:41:29] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:42:03] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:42:36] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:43:10] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:43:43] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:44:17] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:44:51] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:45:25] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#5)
[03:45:59] reaped stale lock + swept assignee on #12 (pid=98958)
[03:46:02] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=1(#12) q_idle=1(#_) r_idle=1(#5)
[03:46:07] dispatch lane=qa issue=#12 pid=97145 claim=ToanMobile
[03:46:13] dispatch lane=build issue=#22 pid=97979 claim=ToanMobile
[03:46:46] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:47:18] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:47:51] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:48:24] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:48:57] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:49:30] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:50:03] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:50:36] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:51:09] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:51:42] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:52:15] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:52:48] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:53:21] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:53:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:54:26] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:54:59] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:55:32] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:56:06] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:56:39] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:57:23] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[03:57:23] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[03:57:23]    dispatches=15 reaps=9 cards-landed-this-run=1
[03:57:23]    most re-dispatched issues (count issue):
[03:57:23]      4 12
[03:57:23]      3 5
[03:57:23]      3 4
[03:57:23]      3 3
[03:57:23]      1 7
[03:57:23]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[03:57:54] tick — runaway pause (269s left) — board read every 3 ticks, sleeping 30s
[03:58:24] tick — runaway pause (239s left) — board read every 3 ticks, sleeping 30s
[03:58:56] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[03:59:27] tick — runaway pause (176s left) — board read every 3 ticks, sleeping 30s
[03:59:57] tick — runaway pause (146s left) — board read every 3 ticks, sleeping 30s
[04:00:30] tick — runaway pause (113s left) — board read every 3 ticks, sleeping 30s
[04:01:01] tick — runaway pause (82s left) — board read every 3 ticks, sleeping 30s
[04:01:31] tick — runaway pause (52s left) — board read every 3 ticks, sleeping 30s
[04:02:03] tick — runaway pause (20s left) — board read every 3 ticks, sleeping 30s
[04:02:36] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:03:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:03:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:04:14] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:04:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:05:20] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:05:55] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:06:27] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:07:00] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:07:33] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:08:05] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:08:38] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:09:10] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:09:43] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:10:16] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:10:48] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:11:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:11:55] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:12:28] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:13:01] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:13:33] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:14:06] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:14:39] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:15:12] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:15:45] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:16:18] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=0(#12) r_idle=1(#5)
[04:16:51] 💀 zombie qa worker on #12 (pid=97145) — card moved to 'Review'; killing
[04:16:55] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#5)
[04:17:00] dispatch lane=review issue=#12 pid=53226 claim=ToanMobile
[04:17:32] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:18:06] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:18:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:19:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:19:43] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:20:17] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:20:49] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:21:22] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:21:54] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:22:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:23:00] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:23:33] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:24:06] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:24:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:25:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:25:43] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:26:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:26:49] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:27:22] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:27:55] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:28:28] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:29:00] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:29:33] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:30:06] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:30:39] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:31:12] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:31:45] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:32:17] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:32:50] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:33:23] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:33:56] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=0(#12)
[04:34:29] 💀 zombie review worker on #12 (pid=53226) — card moved to 'Ready'; killing
[04:34:33] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:35:06] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:35:07] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[04:35:07]    dispatches=16 reaps=9 cards-landed-this-run=1
[04:35:07]    most re-dispatched issues (count issue):
[04:35:07]      5 12
[04:35:07]      3 5
[04:35:07]      3 4
[04:35:07]      3 3
[04:35:07]      1 7
[04:35:07]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[04:35:37] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[04:36:07] tick — runaway pause (240s left) — board read every 3 ticks, sleeping 30s
[04:36:40] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[04:37:10] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[04:37:40] tick — runaway pause (147s left) — board read every 3 ticks, sleeping 30s
[04:38:13] tick — runaway pause (114s left) — board read every 3 ticks, sleeping 30s
[04:38:43] tick — runaway pause (84s left) — board read every 3 ticks, sleeping 30s
[04:39:13] tick — runaway pause (54s left) — board read every 3 ticks, sleeping 30s
[04:39:46] tick — runaway pause (21s left) — board read every 3 ticks, sleeping 30s
[04:40:19] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:40:52] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:41:26] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:41:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:42:32] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:43:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:43:39] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:44:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:44:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:45:19] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:45:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:46:26] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:47:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:47:34] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:48:07] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:48:40] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:49:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:49:47] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:50:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:50:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:51:27] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:52:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:52:34] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:53:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:53:41] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:54:15] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:54:48] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:55:22] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[04:55:56] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=1(#22) q_idle=1(#_) r_idle=1(#_)
[04:56:02] dispatch lane=qa issue=#22 pid=5741 claim=ToanMobile
[04:56:08] dispatch lane=build issue=#12 pid=6417 claim=ToanMobile
[04:56:40] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:57:13] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:57:45] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:58:18] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:58:50] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:59:24] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[04:59:57] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:00:29] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:01:03] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:01:35] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:02:09] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:02:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:03:14] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:03:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:04:20] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:04:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:05:25] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:05:58] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:06:31] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:07:04] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:07:36] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:08:09] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:08:42] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:09:14] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:09:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:10:20] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:10:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:11:25] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:11:58] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:12:31] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:13:03] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:13:03] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[05:13:03]    dispatches=18 reaps=9 cards-landed-this-run=1
[05:13:03]    most re-dispatched issues (count issue):
[05:13:03]      6 12
[05:13:03]      3 5
[05:13:03]      3 4
[05:13:03]      3 3
[05:13:03]      2 22
[05:13:03]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[05:13:33] tick — runaway pause (270s left) — board read every 3 ticks, sleeping 30s
[05:14:04] tick — runaway pause (239s left) — board read every 3 ticks, sleeping 30s
[05:14:37] tick — runaway pause (206s left) — board read every 3 ticks, sleeping 30s
[05:15:07] tick — runaway pause (176s left) — board read every 3 ticks, sleeping 30s
[05:15:37] tick — runaway pause (146s left) — board read every 3 ticks, sleeping 30s
[05:16:09] tick — runaway pause (114s left) — board read every 3 ticks, sleeping 30s
[05:16:40] tick — runaway pause (83s left) — board read every 3 ticks, sleeping 30s
[05:17:10] tick — runaway pause (53s left) — board read every 3 ticks, sleeping 30s
[05:17:43] tick — runaway pause (20s left) — board read every 3 ticks, sleeping 30s
[05:18:15] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:18:48] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=0(#22) r_idle=1(#_)
[05:19:21] 💀 zombie qa worker on #22 (pid=5741) — card moved to 'Ready'; killing
[05:19:24] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:19:58] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:20:31] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:21:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:21:39] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:22:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:22:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:23:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:23:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:24:26] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:25:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:25:33] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:26:07] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:26:40] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:27:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:27:47] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:28:21] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:28:54] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:29:28] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:30:01] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:30:35] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:31:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:31:42] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:32:15] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:32:48] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:33:22] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:33:56] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:34:29] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:35:02] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:35:36] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:36:09] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:36:42] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:37:17] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:37:50] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:38:23] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:38:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:39:30] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:40:03] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:40:36] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:41:10] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:41:44] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:42:18] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:42:51] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:43:24] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:43:58] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:44:32] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:45:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:45:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:46:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:46:45] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:47:18] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:47:52] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:48:26] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:48:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:49:32] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:50:06] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:50:39] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:51:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:51:13] ⚠ RUNAWAY (daemon): no card reached Done in 60 dispatch cycles — no new dispatch for 300s
[05:51:13]    dispatches=18 reaps=9 cards-landed-this-run=1
[05:51:13]    most re-dispatched issues (count issue):
[05:51:13]      6 12
[05:51:13]      3 5
[05:51:13]      3 4
[05:51:13]      3 3
[05:51:13]      2 22
[05:51:13]    → inspect worker logs in docs/super-board/runs/2026-10-16-agent-workbench-workers/
[05:51:44] tick — runaway pause (269s left) — board read every 3 ticks, sleeping 30s
[05:52:14] tick — runaway pause (239s left) — board read every 3 ticks, sleeping 30s
[05:52:46] tick — runaway pause (207s left) — board read every 3 ticks, sleeping 30s
[05:53:16] tick — runaway pause (177s left) — board read every 3 ticks, sleeping 30s
[05:53:46] tick — runaway pause (147s left) — board read every 3 ticks, sleeping 30s
[05:54:19] tick — runaway pause (114s left) — board read every 3 ticks, sleeping 30s
[05:54:49] tick — runaway pause (84s left) — board read every 3 ticks, sleeping 30s
[05:55:19] tick — runaway pause (54s left) — board read every 3 ticks, sleeping 30s
[05:55:52] tick — runaway pause (21s left) — board read every 3 ticks, sleeping 30s
[05:56:25] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:56:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:57:32] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:58:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:58:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:59:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[05:59:45] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:00:19] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:00:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:01:26] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:01:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:02:33] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:03:06] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:03:40] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:04:14] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:04:50] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:05:24] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:05:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:06:31] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:07:05] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:07:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:08:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:08:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:09:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:09:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:10:27] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:11:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:11:34] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:12:07] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:12:41] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:13:14] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:13:48] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:14:21] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:14:55] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:15:28] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:16:01] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:16:35] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:17:09] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#12) q_idle=1(#_) r_idle=1(#_)
[06:17:42] 💀 zombie build worker on #12 (pid=6417) — card moved to 'Blocked'; killing
[06:17:46] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[06:17:51] dispatch lane=build issue=#22 pid=38291 claim=ToanMobile
[06:18:24] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:18:56] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:19:29] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:20:01] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:20:34] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:21:07] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:21:40] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:22:12] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:22:45] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:23:18] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:23:51] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:24:24] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:24:56] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:25:30] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:26:04] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:26:36] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:27:09] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:27:42] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
[06:28:15] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#22) q_idle=1(#_) r_idle=1(#_)
