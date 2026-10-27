[04:06:32] super-board run started — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[04:06:35] initial Ready count: 1
[04:06:42] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:06:59] dispatch lane=build issue=#319 pid=36467 claim=ToanMobile
[04:07:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:08:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:08:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:09:22] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:09:56] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:10:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:11:04] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:11:39] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:12:15] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:12:50] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:13:25] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:13:59] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:14:33] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:15:07] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:15:41] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:16:15] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 36467) holds it
[04:16:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:17:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:17:57] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:18:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:19:06] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:19:40] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:20:14] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:20:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:21:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:21:58] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:22:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:23:06] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:23:40] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:24:14] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:24:48] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:25:19] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1070s
[04:25:22] reaped stale lock + swept assignee on #319 (pid=36467)
[04:25:29] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:25:36] dispatch lane=qa issue=#319 pid=89270 claim=ToanMobile
[04:26:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:26:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 89270) holds it
[04:27:17] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:27:51] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:28:24] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:28:58] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:29:35] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:30:11] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:30:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:31:19] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:31:50] worker of #319 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=347s
[04:31:53] reaped stale lock + swept assignee on #319 (pid=89270)
[04:31:56] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[04:32:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[04:33:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[04:33:41] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[04:33:53] dispatch lane=review issue=#319 pid=70550 claim=ToanMobile
[04:34:27] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:35:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:35:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:36:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:36:42] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:37:16] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live review lane (pid 70550) holds it
[04:37:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:38:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:38:53] worker of #319 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=293s
[04:38:56] reaped stale lock + swept assignee on #319 (pid=70550)
[04:39:03] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[04:39:19] dispatch lane=build issue=#319 pid=49172 claim=ToanMobile
[04:39:52] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:40:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:41:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:41:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:42:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:42:42] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:43:16] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:43:50] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:44:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:44:56] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:45:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:46:03] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:46:37] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:47:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:47:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 49172) holds it
[04:48:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:48:51] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:49:25] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:49:58] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:50:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[04:51:05] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[05:54:30] ⚠ self-reload: git fetch origin main failed; retrying next check
[05:54:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[05:55:00] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1613s
[05:55:03] reaped stale lock + swept assignee on #319 (pid=49172)
kept card 319: issue state OPEN, not CLOSED
[05:55:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:55:40] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:56:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:56:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:57:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:58:04] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:58:40] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:59:15] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[05:59:50] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:00:27] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:01:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:01:39] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:02:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:02:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:03:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:04:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:04:39] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[06:05:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:05:47] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:06:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:06:55] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:07:30] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:08:04] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:08:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:09:15] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:09:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:10:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:11:04] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:11:40] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:12:14] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:12:49] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:13:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:13:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:14:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:15:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:15:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[06:16:15] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:16:49] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:17:24] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:17:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:18:33] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:19:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:19:45] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:20:20] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:20:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:21:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:22:04] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:22:40] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:23:14] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:23:49] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:24:24] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:25:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:25:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[06:26:20] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:26:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:27:34] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:28:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:28:49] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:29:25] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:30:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:30:35] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:31:12] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:31:46] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:32:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:32:56] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:33:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:34:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:34:40] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:35:14] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[06:35:48] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:36:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:36:57] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:37:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:38:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:38:45] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:39:22] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:39:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:40:35] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:41:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:41:47] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[06:41:56] dispatch lane=qa issue=#319 pid=45472 claim=ToanMobile
[06:42:31] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:43:05] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:43:42] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[06:44:20] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[06:44:57] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[06:45:36] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
kept card 319: live qa lane (pid 45472) holds it
[06:46:13] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:46:48] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:47:29] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:48:06] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:48:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:49:22] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:50:00] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:50:40] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:51:17] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:51:52] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:52:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:53:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:53:46] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:54:18] worker of #319 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=721s
[06:54:21] reaped stale lock + swept assignee on #319 (pid=45472)
[06:54:33] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[06:54:55] dispatch lane=review issue=#319 pid=39227 claim=ToanMobile
[06:55:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:56:08] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:56:47] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live review lane (pid 39227) holds it
[06:57:25] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:58:00] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[06:58:32] worker of #319 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=210s
[06:58:36] reaped stale lock + swept assignee on #319 (pid=39227)
[06:58:44] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:59:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[06:59:57] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:00:33] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:01:08] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:01:45] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:02:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:02:57] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:03:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:04:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:04:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:05:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:05:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:06:26] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:07:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:07:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:08:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:08:55] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:09:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:10:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:10:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:11:17] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:11:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:12:27] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:13:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:13:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:14:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:14:56] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:15:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:16:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:16:51] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:17:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:18:06] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:18:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:19:19] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:19:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:20:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:21:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:21:59] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[07:22:46] dispatch lane=build issue=#319 pid=23329 claim=ToanMobile
[07:23:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:24:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:24:48] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:25:28] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:26:06] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:26:46] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[07:27:17] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=256s
[07:27:23] reaped stale lock + swept assignee on #319 (pid=23329)
[07:27:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:28:06] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:28:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:29:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:29:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:30:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:31:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:31:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:32:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:33:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:33:37] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:34:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:34:47] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:35:22] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:35:57] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:36:33] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:37:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:37:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:38:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:38:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:39:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:40:08] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:40:44] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:41:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:41:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:42:37] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:43:14] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:43:53] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:44:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:45:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:45:47] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:46:25] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:47:01] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:47:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:48:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:48:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:49:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:50:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:50:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:51:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:51:55] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:52:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:53:06] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:53:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:54:15] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:54:50] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:55:26] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:56:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:56:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:57:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:57:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:58:25] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[07:59:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[07:59:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:00:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:00:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:01:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:02:06] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:02:45] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:03:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:04:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:04:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:05:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:06:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:06:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[08:07:35] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[08:07:59] dispatch lane=qa issue=#319 pid=72897 claim=ToanMobile
[08:08:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[08:09:28] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:10:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:10:51] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:11:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:12:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:12:48] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:13:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:14:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:14:58] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:15:37] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:16:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:17:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:17:41] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:18:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:19:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[08:19:39] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:20:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:21:05] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:21:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:22:29] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:23:08] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:23:50] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:24:28] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:25:07] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:25:43] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:26:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:27:02] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:27:42] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:28:22] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:29:04] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[08:29:46] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:30:27] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:31:07] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:31:50] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:32:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:33:12] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:33:53] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:34:33] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:35:13] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:35:53] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:36:34] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:37:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:38:00] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:38:42] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:39:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[08:40:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:40:41] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:41:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:41:55] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:42:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:43:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:43:47] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:44:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:45:04] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:45:39] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:46:14] tick — cap reached (machine at 5 workers, 2 here) — skipping GraphQL fetch, sleeping 30s
[08:46:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:47:24] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:48:00] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:48:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:49:11] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[08:49:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:50:20] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:50:55] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:51:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:52:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:52:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:53:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:53:57] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:54:32] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:55:08] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:55:43] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:56:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:56:52] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:57:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[08:58:03] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[08:58:44] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[08:59:32] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[09:00:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[09:00:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:01:22] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:01:58] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:02:34] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:03:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:03:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:04:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:05:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:05:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:06:25] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:07:02] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:07:40] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:08:19] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:08:57] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:09:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:10:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live qa lane (pid 72897) holds it
[09:11:04] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:11:42] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:12:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:12:57] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:13:28] worker of #319 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=3916s
[09:13:33] reaped stale lock + swept assignee on #319 (pid=72897)
[09:13:47] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[09:14:08] review lane issue=#319: PR #395 approved at head a25974c9baf78a43b2af2ac45083f26aba7c8a28 — merge-only, no fresh review
[09:14:09] dispatch lane=review issue=#319 pid=92562 claim=ToanMobile
[09:14:56] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:15:59] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:17:05] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:17:46] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:18:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:19:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:19:38] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:20:17] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:20:48] worker of #319 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=397s
[09:20:53] reaped stale lock + swept assignee on #319 (pid=92562)
[09:21:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:21:37] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:22:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:22:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:23:30] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:24:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:24:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:25:17] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:25:53] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:26:46] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:27:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:28:01] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:28:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:29:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:29:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:30:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:31:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:31:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:32:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:32:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:33:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:34:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:34:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:35:10] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:35:44] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:36:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:36:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:37:26] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:38:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:38:34] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:39:10] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:39:48] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:40:22] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:40:57] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:41:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:42:07] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:42:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:43:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:43:50] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:44:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:45:04] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:45:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:46:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:46:48] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:47:24] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:48:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:48:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:49:17] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:49:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:50:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:51:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[09:51:48] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:52:25] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:53:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:53:39] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:54:28] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[09:54:33] initial Ready count: 1
[09:54:37] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:55:11] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:55:46] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:56:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:56:56] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:57:31] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:58:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:58:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:59:12] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[09:59:47] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:00:21] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:00:55] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:01:29] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:02:03] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:02:37] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:03:11] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:03:45] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:04:19] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:04:54] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:05:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:06:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:06:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:07:10] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:07:44] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:08:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:08:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:09:26] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:10:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:10:34] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:11:08] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:11:42] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:12:16] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:12:50] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:13:24] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:13:58] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:14:32] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:15:06] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:15:41] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:16:15] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:16:49] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:17:23] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:17:56] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:18:30] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:19:05] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:19:38] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:20:13] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:20:46] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:21:20] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:22:00] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:22:20] dispatch lane=build issue=#319 pid=9014 claim=ToanMobile
[10:22:55] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:23:29] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:24:03] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:24:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 9014) holds it
[10:25:21] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:25:56] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:26:31] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:27:06] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:27:41] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:28:16] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:28:51] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:29:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:30:00] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:30:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:31:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:31:44] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:32:18] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:32:53] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:33:27] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:34:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:34:36] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:35:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 9014) holds it
[10:35:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:36:19] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:36:53] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:37:23] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=890s
[10:37:27] reaped stale lock + swept assignee on #319 (pid=9014)
[10:37:33] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:37:40] dispatch lane=qa issue=#319 pid=16883 claim=ToanMobile
[10:38:14] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:38:48] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:39:23] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:39:57] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:40:31] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:41:02] worker of #319 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=191s
[10:41:04] reaped stale lock + swept assignee on #319 (pid=16883)
[10:41:08] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:41:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:42:17] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:42:51] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:43:25] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:44:00] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:44:34] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:45:09] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:45:43] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: issue state OPEN, not CLOSED
[10:46:18] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:46:52] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:47:28] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:48:02] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:48:36] tick — cap reached (machine at 5 workers, 0 here) — skipping GraphQL fetch, sleeping 30s
[10:49:14] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:49:27] dispatch lane=review issue=#319 pid=3514 claim=ToanMobile
[10:50:01] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:50:36] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:51:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:51:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:52:19] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:52:53] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:53:27] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:54:02] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:54:36] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:55:10] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:55:45] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live review lane (pid 3514) holds it
[10:56:19] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:56:54] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:57:28] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:58:03] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:58:37] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:59:11] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[10:59:46] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:00:20] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:00:55] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:01:30] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:02:09] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:02:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:03:26] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:04:02] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:04:38] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:05:13] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:05:49] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live review lane (pid 3514) holds it
[11:06:24] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:06:59] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:07:35] tick — cap reached (machine at 5 workers, 1 here) — skipping GraphQL fetch, sleeping 30s
[11:08:14] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:08:54] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:09:31] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:10:10] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:10:47] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:11:24] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:12:01] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:12:39] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:13:17] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:13:54] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:14:32] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:15:11] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:15:49] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
kept card 319: live review lane (pid 3514) holds it
[11:16:27] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:17:04] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:17:41] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:18:18] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:18:55] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:19:33] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:20:10] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:20:46] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=0(#319) r_workers=1/5 waiting_on_you=0
[11:21:16] worker of #319 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1901s
[11:21:19] reaped stale lock + swept assignee on #319 (pid=3514)
[11:21:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:22:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:22:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:23:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:23:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:24:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:25:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:25:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:26:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:26:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:27:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:28:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:28:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:29:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:30:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:30:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:31:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:31:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:32:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:33:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:33:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:34:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:34:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:35:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:36:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:36:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:37:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:37:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:38:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:39:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:39:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:40:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:40:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:41:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:42:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:42:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:43:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:43:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:44:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:45:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:45:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:46:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:46:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:47:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:48:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:48:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:49:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:50:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:50:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:51:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:51:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:52:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:53:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:53:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:54:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:54:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:55:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:56:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:56:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:57:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:57:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:58:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:59:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[11:59:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:00:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:01:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:01:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:02:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:02:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:03:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:04:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:04:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:05:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:05:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:06:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:07:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:07:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:08:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:08:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:09:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:10:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:10:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:11:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:11:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:12:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:13:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:13:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:14:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:14:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:15:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:16:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:16:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:17:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:18:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=0(#319) q_workers=1/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:18:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:19:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:19:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:20:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:21:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:21:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:22:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:22:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:23:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:24:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:24:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:25:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:25:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:26:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:27:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:27:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:28:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:28:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:29:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:30:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:30:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:31:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:31:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:32:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:33:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:33:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:34:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:34:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:35:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:36:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:36:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:37:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:37:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:38:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:39:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:39:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:40:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:40:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:41:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:42:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:42:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:43:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:43:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:44:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:45:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:45:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:46:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:46:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:47:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:48:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:48:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:49:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:49:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:50:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:51:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:51:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:52:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:52:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:53:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:54:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:54:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:55:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:55:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:56:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:57:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:57:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:58:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:59:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[12:59:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:00:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:00:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:01:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:02:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:02:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:03:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:03:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:04:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:05:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:05:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:06:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:06:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:07:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:08:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:08:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:09:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:09:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:10:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:11:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:11:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:12:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:12:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:13:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:14:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:14:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:15:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:15:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:16:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:17:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:17:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:18:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:18:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:19:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:20:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:20:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:21:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:21:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:22:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:23:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:23:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:24:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:24:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:25:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:26:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:26:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:27:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:27:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:28:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:29:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:29:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:30:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:30:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:31:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:32:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:32:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:33:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:33:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:34:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:35:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:35:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:36:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:37:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:37:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:38:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:38:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:39:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:39:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:40:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:41:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:41:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:42:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:42:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:43:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:44:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:44:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:45:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:46:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:46:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:47:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:47:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:48:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:49:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:49:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:50:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:51:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:51:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:52:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:52:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:53:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:54:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:54:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:55:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:55:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:56:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:56:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:57:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:58:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:58:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:59:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[13:59:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:00:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:01:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:01:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:02:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:02:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:03:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:04:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:04:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:05:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:05:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:06:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:07:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:07:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:08:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:08:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:09:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:10:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:10:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:11:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:11:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:12:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:13:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:13:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:14:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:14:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:15:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:16:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:16:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:17:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:17:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:18:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:19:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:19:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:20:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:20:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:21:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:22:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:22:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:23:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:23:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:24:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:25:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:25:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:26:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:27:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:27:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:28:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:28:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:29:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:29:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:30:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:31:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:31:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:32:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:33:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:33:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:34:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:34:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:35:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:35:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:36:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:37:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:37:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:38:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:38:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:39:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:40:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:40:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:41:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:41:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:42:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:43:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:43:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:44:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:45:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:45:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:46:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:46:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:47:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:47:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:48:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:49:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:49:47] tick — Ready=5 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:50:03] dispatch lane=build issue=#391 pid=46362 claim=ToanMobile
[14:50:39] tick — Ready=4 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:50:55] dispatch lane=build issue=#392 pid=59179 claim=ToanMobile
[14:51:31] tick — Ready=3 Building=2 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#391 +59179:392) b_workers=2/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:51:46] dispatch lane=build issue=#393 pid=74588 claim=ToanMobile
kept card 391: live build lane (pid 46362) holds it
kept card 392: live build lane (pid 59179) holds it
kept card 393: live build lane (pid 74588) holds it
[14:52:23] tick — Ready=2 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#391 +59179:392 74588:393) b_workers=3/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:52:38] dispatch lane=build issue=#397 pid=90878 claim=ToanMobile
[14:53:15] tick — Ready=1 Building=4 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#391 +59179:392 74588:393 90878:397) b_workers=4/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[14:53:30] dispatch lane=build issue=#406 pid=29493 claim=ToanMobile
[14:54:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:54:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:55:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:55:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:56:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:57:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:57:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:58:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:58:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:59:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:00:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:00:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:01:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:02:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 393: live build lane (pid 74588) holds it
[15:03:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 392: live build lane (pid 59179) holds it
kept card 391: live build lane (pid 46362) holds it
kept card 397: live build lane (pid 90878) holds it
kept card 406: live build lane (pid 29493) holds it
[15:03:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:04:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:05:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:05:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:06:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:06:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:07:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:08:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:08:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:09:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:09:44] worker of #392 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1105s
[15:09:46] reaped stale lock + swept assignee on #392 (pid=59179)
[15:09:52] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391 +74588:393 90878:397 29493:406) b_workers=4/5 q_idle=1(#319) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[15:09:58] dispatch lane=qa issue=#392 pid=37272 claim=ToanMobile
[15:10:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:11:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:11:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:12:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:12:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:13:26] worker of #392 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=176s
[15:13:29] reaped stale lock + swept assignee on #392 (pid=37272)
kept card 393: live build lane (pid 74588) holds it
kept card 397: live build lane (pid 90878) holds it
kept card 391: live build lane (pid 46362) holds it
kept card 406: live build lane (pid 29493) holds it
[15:13:40] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#391 +74588:393 90878:397 29493:406) b_workers=4/5 q_idle=1(#392) q_workers=0/5 r_idle=1(#319) r_workers=0/5 waiting_on_you=0
[15:13:58] dispatch lane=review issue=#392 pid=12746 claim=ToanMobile
[15:13:58] qa workers: 5/5 running on the machine (5 here): holding
[15:14:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:15:15] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#391 +90878:397 29493:406) b_workers=3/5 q_idle=1(#392) q_workers=0/5 r_idle=0(#392) r_workers=1/5 waiting_on_you=0
[15:15:16] worker of #393 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1401s
[15:15:26] dispatch lane=qa issue=#393 pid=17506 claim=ToanMobile
[15:16:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:16:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:17:11] worker of #392 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=182s
[15:17:15] reaped stale lock + swept assignee on #392 (pid=12746)
[15:17:26] tick — Ready=1 Building=3 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391 +90878:397 29493:406) b_workers=3/5 q_idle=0(#393) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:17:48] dispatch lane=build issue=#392 pid=7352 claim=ToanMobile
[15:18:19] worker of #397 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1520s
[15:18:22] reaped stale lock + swept assignee on #397 (pid=90878)
[15:18:31] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +29493:406 7352:392) b_workers=3/5 q_idle=0(#393) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:18:41] dispatch lane=qa issue=#397 pid=97825 claim=ToanMobile
[15:19:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:19:47] worker of #392 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=95s
[15:19:47] ⚠ worker of #392 (lane build) ended 95s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":53835,"stop_reason":"end_turn","session_id":"fd78131b-4c0c-4d9b-9a75-210bdb414b2d","total_cost_usd":0.4590474,"usage":{"input_tokens":32,"cache_creation_input_tokens":72284,"cache_r
[15:19:51] reaped stale lock + swept assignee on #392 (pid=7352)
[15:19:59] tick — Ready=0 Building=2 QA=3 Review=0 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=0(#393 +97825:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:20:06] dispatch lane=qa issue=#392 pid=55770 claim=ToanMobile
[15:20:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:21:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:21:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:22:19] worker of #393 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=401s
[15:22:22] reaped stale lock + swept assignee on #393 (pid=17506)
[15:22:29] tick — Ready=0 Building=2 QA=2 Review=1 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=0(#393 +97825:397 55770:392) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:22:39] dispatch lane=review issue=#393 pid=25828 claim=ToanMobile
[15:22:40] worker of #392 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=152s
[15:22:45] dispatch lane=qa issue=#392 pid=32568 claim=ToanMobile
[15:23:16] worker of #397 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=248s
[15:23:19] reaped stale lock + swept assignee on #397 (pid=97825)
[15:23:29] tick — Ready=0 Building=2 QA=0 Review=3 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=0(#392) q_workers=1/5 r_idle=0(#393) r_workers=1/5 waiting_on_you=0
[15:23:49] dispatch lane=review issue=#397 pid=8368 claim=ToanMobile
kept card 397: live review lane (pid 8368) holds it
kept card 391: live build lane (pid 46362) holds it
[15:24:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 406: live build lane (pid 29493) holds it
kept card 392: live qa lane (pid 32568) holds it
kept card 393: live review lane (pid 25828) holds it
[15:25:03] 💀 zombie qa worker on #392 (pid=32568) — card moved to 'Review'; killing
[15:25:17] tick — Ready=0 Building=2 QA=0 Review=3 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#393 +8368:397) r_workers=2/5 waiting_on_you=0
[15:25:35] review lane issue=#392: PR #408 approved at head 56d6696eb1c82805f53b5b5d4e15bceedc6545bd — merge-only, no fresh review
[15:25:36] dispatch lane=review issue=#392 pid=20727 claim=ToanMobile
[15:26:13] ♻ self-reload: origin/main changed super-board-run.sh (f61f63f → 4d09b88) — restarting on the new code (5 live worker(s) will be adopted)
[15:26:14] super-board run started (self-reload) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[15:26:18] adopted live build worker on #391 (pid=46362) from the previous run
[15:26:18] adopted live review worker on #392 (pid=20727) from the previous run
[15:26:18] adopted live review worker on #393 (pid=25828) from the previous run
[15:26:18] adopted live review worker on #397 (pid=8368) from the previous run
[15:26:19] adopted live build worker on #406 (pid=29493) from the previous run
[15:26:27] initial Ready count: 0
[15:26:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:27:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[15:27:41] worker of #393 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=271s
[15:27:45] reaped stale lock + swept assignee on #393 (pid=25828)
[15:28:01] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:28:44] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:29:24] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:30:03] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:30:42] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:31:21] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:32:01] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:32:41] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:33:23] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:34:03] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:34:43] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:35:25] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:36:09] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
kept card 406: live build lane (pid 29493) holds it
kept card 397: live review lane (pid 8368) holds it
kept card 391: live build lane (pid 46362) holds it
kept card 392: live review lane (pid 20727) holds it
[15:36:50] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:37:30] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:38:11] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391 +29493:406) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:38:53] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:38:54] worker of #406 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2718s
[15:39:04] dispatch lane=qa issue=#406 pid=59533 claim=ToanMobile
[15:39:42] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:40:19] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:40:56] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:41:33] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:42:11] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:42:54] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:43:42] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=0(#392 +8368:397) r_workers=2/5 waiting_on_you=0
[15:44:14] worker of #392 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1104s
[15:44:18] reaped stale lock + swept assignee on #392 (pid=20727)
[15:44:19] worker of #397 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1205s
[15:44:23] reaped stale lock + swept assignee on #397 (pid=8368)
[15:44:35] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:45:05] dispatch lane=build issue=#397 pid=59020 claim=ToanMobile
[15:45:44] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391 +59020:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:46:16] worker of #397 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=47s
[15:46:17] ⚠ worker of #397 (lane build) ended 47s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":16783,"stop_reason":"end_turn","session_id":"77935aeb-1e07-4376-9af7-5de5a73faaeb","total_cost_usd":0.273739,"usage":{"input_tokens":10,"cache_creation_input_tokens":57512,"cache_re
[15:46:21] reaped stale lock + swept assignee on #397 (pid=59020)
[15:46:45] ↩ stranded #397: Building → Ready (branch issue-397-runaway-no-done)
[15:46:47] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:47:17] dispatch lane=build issue=#397 pid=19682 claim=ToanMobile
kept card 391: live build lane (pid 46362) holds it
kept card 397: live build lane (pid 19682) holds it
kept card 406: live qa lane (pid 59533) holds it
[15:47:59] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:48:37] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:49:15] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:49:53] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:50:31] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:51:08] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391 +19682:397) b_workers=2/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:51:47] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:51:48] worker of #397 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=262s
[15:52:02] dispatch lane=qa issue=#397 pid=91657 claim=ToanMobile
[15:52:42] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:53:26] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:54:08] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:54:46] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:55:22] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:56:03] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:56:42] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:57:27] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
kept card 406: live qa lane (pid 59533) holds it
kept card 391: live build lane (pid 46362) holds it
kept card 397: live qa lane (pid 91657) holds it
[15:58:11] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:58:53] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[15:59:35] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:00:16] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:00:55] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:01:35] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:02:18] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:02:58] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:03:38] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:04:17] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:04:53] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:05:33] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:06:10] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=2/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:06:48] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=1/5 r_idle=1(#392) r_workers=0/5 waiting_on_you=0
[16:06:48] worker of #406 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1662s
[16:06:59] dispatch lane=review issue=#406 pid=27876 claim=ToanMobile
[16:07:36] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=1/5 r_idle=0(#406) r_workers=1/5 waiting_on_you=0
kept card 391: live build lane (pid 46362) holds it
kept card 406: live review lane (pid 27876) holds it
kept card 397: live qa lane (pid 91657) holds it
[16:08:15] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=1/5 r_idle=0(#406) r_workers=1/5 waiting_on_you=0
[16:08:46] worker of #406 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=85s
[16:08:50] reaped stale lock + swept assignee on #406 (pid=27876)
[16:08:58] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=0(#406 +91657:397) q_workers=1/5 r_idle=1(#406) r_workers=0/5 waiting_on_you=0
[16:09:29] worker of #397 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1021s
[16:09:34] reaped stale lock + swept assignee on #397 (pid=91657)
[16:09:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#406) r_workers=0/5 waiting_on_you=0
[16:09:54] dispatch lane=review issue=#397 pid=19150 claim=ToanMobile
[16:10:31] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:11:09] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:11:40] worker of #397 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=79s
[16:11:41] ⚠ worker of #397 (lane review) ended 79s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":29488,"stop_reason":"end_turn","session_id":"4dafc6fa-48a1-418e-8e52-fb9fd88c9b44","total_cost_usd":0.39025049999999994,"usage":{"input_tokens":16,"cache_creation_input_tokens":7528
[16:11:45] reaped stale lock + swept assignee on #397 (pid=19150)
[16:11:54] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:12:16] dispatch lane=build issue=#397 pid=51012 claim=ToanMobile
[16:12:54] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391 +51012:397) b_workers=2/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:13:25] worker of #397 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=48s
[16:13:26] ⚠ worker of #397 (lane build) ended 48s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":18246,"stop_reason":"end_turn","session_id":"31ea436f-3a6f-432d-89c0-b3d8b7abaef7","total_cost_usd":0.31078599999999995,"usage":{"input_tokens":12,"cache_creation_input_tokens":6343
[16:13:29] reaped stale lock + swept assignee on #397 (pid=51012)
[16:13:38] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:13:55] dispatch lane=review issue=#397 pid=22740 claim=ToanMobile
[16:14:34] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:15:15] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:15:56] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:16:34] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:17:13] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:17:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
kept card 391: live build lane (pid 46362) holds it
[16:18:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=0(#397) r_workers=1/5 waiting_on_you=0
[16:19:02] worker of #397 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=285s
[16:19:05] reaped stale lock + swept assignee on #397 (pid=22740)
[16:19:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:19:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:20:29] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:21:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:21:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:22:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:23:04] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:23:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:24:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:24:55] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:25:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:26:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:26:43] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:27:20] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:27:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
kept card 391: live build lane (pid 46362) holds it
[16:28:33] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:29:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:29:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:30:23] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:31:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:31:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:32:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:32:53] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:33:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:34:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:34:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:35:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:35:57] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:36:33] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:37:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:37:45] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#391) b_workers=1/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:38:15] worker of #391 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=6479s
[16:38:18] reaped stale lock + swept assignee on #391 (pid=46362)
[16:38:24] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#406) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:38:31] dispatch lane=qa issue=#391 pid=68061 claim=ToanMobile
kept card 391: live qa lane (pid 68061) holds it
[16:39:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#391) b_workers=0/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:39:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:40:16] worker of #391 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=77s
[16:40:20] reaped stale lock + swept assignee on #391 (pid=68061)
[16:40:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:41:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:41:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:42:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:42:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:43:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:44:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:44:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:45:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:45:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:46:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:47:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:47:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:48:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:48:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:49:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:50:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:50:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:51:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:52:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:52:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:53:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:53:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:54:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:55:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:55:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:56:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:56:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:57:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:58:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:58:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:59:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[16:59:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:00:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:01:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:01:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:02:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:02:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:03:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:04:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:04:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:05:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:05:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:06:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:07:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:07:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:08:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:08:52] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:09:28] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:10:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:10:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:11:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:11:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:12:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:13:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:13:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:14:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:14:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:15:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:16:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:16:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:17:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:17:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:18:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:19:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:19:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:20:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:21:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:21:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:22:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:22:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:23:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:24:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:24:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:25:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:25:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:26:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:27:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:27:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:28:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:28:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:29:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:30:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:30:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:31:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:32:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:32:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:33:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:34:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:34:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:35:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:35:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:36:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:37:08] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:37:20] preflight hold/unclear for #413: no `## Acceptance Criteria` items (`-`, `*`, `1.`, `1)`) — not dispatched, card to Blocked
[17:38:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:38:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:39:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:39:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:40:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:41:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:41:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:42:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:42:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:43:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:44:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:44:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:45:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:45:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:46:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:47:12] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#391) b_workers=0/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:47:30] dispatch lane=build issue=#413 pid=56787 claim=ToanMobile
[17:48:08] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413) b_workers=1/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:48:16] dispatch lane=qa issue=#391 pid=22241 claim=ToanMobile
[17:48:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413) b_workers=1/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:49:29] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413) b_workers=1/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:50:06] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413) b_workers=1/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:50:27] dispatch lane=build issue=#416 pid=85520 claim=ToanMobile
[17:51:08] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 56787) holds it
kept card 416: live build lane (pid 85520) holds it
kept card 391: live qa lane (pid 22241) holds it
[17:51:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:52:23] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:53:02] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:53:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:54:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:55:00] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:55:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:56:20] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:57:03] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:57:45] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:58:25] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:59:07] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[17:59:52] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:00:38] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:01:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
kept card 391: live qa lane (pid 22241) holds it
kept card 413: live build lane (pid 56787) holds it
[18:02:12] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
kept card 416: live build lane (pid 85520) holds it
[18:03:01] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:03:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:04:32] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:05:19] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:06:04] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:06:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:07:29] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:08:12] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:08:50] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:09:29] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:10:06] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:10:43] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:11:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:11:59] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 56787) holds it
kept card 416: live build lane (pid 85520) holds it
kept card 391: live qa lane (pid 22241) holds it
[18:12:36] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:13:14] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:13:54] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:14:31] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:15:09] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:15:48] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=0(#391) q_workers=1/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:16:19] worker of #391 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1674s
[18:16:22] reaped stale lock + swept assignee on #391 (pid=22241)
[18:16:32] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#397) r_workers=0/5 waiting_on_you=0
[18:16:50] dispatch lane=review issue=#391 pid=85860 claim=ToanMobile
[18:17:30] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[18:18:07] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[18:18:44] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[18:19:21] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[18:19:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[18:20:30] worker of #391 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=199s
[18:20:33] reaped stale lock + swept assignee on #391 (pid=85860)
[18:20:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:21:10] dispatch lane=build issue=#391 pid=90227 claim=ToanMobile
[18:21:49] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:22:28] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 391: live build lane (pid 90227) holds it
kept card 413: live build lane (pid 56787) holds it
kept card 416: live build lane (pid 85520) holds it
[18:23:08] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:23:46] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:24:25] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:25:09] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:25:50] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:26:32] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:27:19] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:28:04] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:28:55] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:29:41] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:30:24] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:31:06] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:31:48] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:32:41] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 56787) holds it
[18:33:29] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 416: live build lane (pid 85520) holds it
kept card 391: live build lane (pid 90227) holds it
[18:34:16] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:35:00] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:35:41] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:36:20] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:36:59] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:37:38] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:38:20] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:39:00] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:39:41] tick — Ready=0 Building=3 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:40:23] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:41:04] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:41:44] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:42:26] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:43:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 391: live build lane (pid 90227) holds it
kept card 413: live build lane (pid 56787) holds it
kept card 416: live build lane (pid 85520) holds it
[18:43:50] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:44:37] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:45:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:46:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:46:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:47:38] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:48:23] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:49:06] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:49:51] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:50:40] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:51:33] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:52:22] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:53:09] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=3/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:53:44] worker of #413 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3966s
[18:53:49] reaped stale lock + swept assignee on #413 (pid=56787)
kept card 416: live build lane (pid 85520) holds it
[18:54:07] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=1(#391) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 391: live build lane (pid 90227) holds it
[18:54:24] dispatch lane=qa issue=#413 pid=30898 claim=ToanMobile
[18:55:10] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:55:56] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[18:56:33] 💀 zombie review worker on #391 (pid=85860) — card moved to 'Building'; killing
[18:56:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[18:57:39] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[18:58:24] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[18:59:11] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[18:59:57] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:00:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:01:23] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:02:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:02:55] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:03:42] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 391: issue state OPEN, not CLOSED
kept card 413: live qa lane (pid 30898) holds it
kept card 416: live build lane (pid 85520) holds it
[19:04:28] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:05:13] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:05:55] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:06:36] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:07:15] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:07:57] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:08:41] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:09:28] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:10:10] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:10:49] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:11:28] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:12:09] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:12:48] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:13:28] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:14:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416 90227:391) b_workers=2/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 30898) holds it
kept card 416: live build lane (pid 85520) holds it
[19:14:45] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 391: issue state OPEN, not CLOSED
[19:14:54] dispatch lane=qa issue=#391 pid=47356 claim=ToanMobile
[19:15:33] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:16:14] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:16:54] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:17:32] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:18:09] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:18:51] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:19:35] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:20:16] tick — Ready=0 Building=1 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:20:58] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:21:43] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413 +47356:391) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:22:18] 💀 zombie qa worker on #391 (pid=47356) — card moved to 'Review'; killing
[19:22:30] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:22:49] dispatch lane=review issue=#391 pid=29153 claim=ToanMobile
[19:23:27] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[19:24:08] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
kept card 413: live qa lane (pid 30898) holds it
kept card 416: live build lane (pid 85520) holds it
kept card 391: live review lane (pid 29153) holds it
[19:24:49] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[19:25:29] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[19:26:06] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[19:26:51] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=0(#391) r_workers=1/5 waiting_on_you=0
[19:27:41] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:28:14] worker of #391 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=285s
[19:28:17] reaped stale lock + swept assignee on #391 (pid=29153)
[19:28:27] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:29:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:29:43] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:30:20] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:31:01] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:31:45] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:32:27] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:33:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:33:47] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:34:29] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 30898) holds it
kept card 416: live build lane (pid 85520) holds it
[19:35:10] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:35:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:36:37] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:37:21] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:38:04] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:38:46] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:39:29] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:40:13] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:40:55] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:41:38] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:42:22] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:43:03] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:43:44] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:44:23] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:45:00] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 30898) holds it
kept card 416: live build lane (pid 85520) holds it
[19:45:40] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:46:19] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:46:57] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:47:36] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:48:15] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:48:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=0 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:49:33] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#413 +85520:416) b_workers=1/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:50:04] worker of #416 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=7166s
[19:50:06] reaped stale lock + swept assignee on #416 (pid=85520)
[19:50:13] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:50:44] worker of #413 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=3350s
[19:50:47] reaped stale lock + swept assignee on #413 (pid=30898)
[19:50:54] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#391) r_workers=0/5 waiting_on_you=0
[19:51:05] dispatch lane=review issue=#413 pid=34853 claim=ToanMobile
[19:51:43] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=0(#413) r_workers=1/5 waiting_on_you=0
[19:52:20] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=0(#413) r_workers=1/5 waiting_on_you=0
[19:52:59] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=0(#413) r_workers=1/5 waiting_on_you=0
[19:53:40] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=0(#413) r_workers=1/5 waiting_on_you=0
[19:54:11] worker of #413 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=167s
[19:54:14] reaped stale lock + swept assignee on #413 (pid=34853)
[19:54:22] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:54:40] dispatch lane=build issue=#413 pid=66690 claim=ToanMobile
[19:55:17] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#413) b_workers=1/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 66690) holds it
[19:55:54] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#413) b_workers=1/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:56:31] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=0(#413) b_workers=1/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:57:02] worker of #413 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=112s
[19:57:03] ⚠ worker of #413 (lane build) ended 112s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":49868,"stop_reason":"end_turn","session_id":"f134863e-1f6c-4b86-82b8-e6e7a9a1f234","total_cost_usd":0.46884780000000004,"usage":{"input_tokens":22,"cache_creation_input_tokens":8188
[19:57:06] reaped stale lock + swept assignee on #413 (pid=66690)
[19:57:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:57:19] dispatch lane=qa issue=#413 pid=88968 claim=ToanMobile
[19:57:56] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:58:33] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:59:15] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[19:59:54] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:00:31] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:01:09] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:01:50] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:02:31] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:03:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:03:51] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:04:29] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:05:10] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:05:49] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 88968) holds it
[20:06:27] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:07:05] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:07:46] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:08:28] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:09:08] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:09:47] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:10:26] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:11:06] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:11:44] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:12:23] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:13:02] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:13:40] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:14:18] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:14:56] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:15:34] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:16:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 88968) holds it
[20:16:51] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:17:28] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:18:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:18:44] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:19:21] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:19:58] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:20:35] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:21:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:21:49] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:22:26] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:23:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:23:48] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:24:30] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#413) r_workers=0/5 waiting_on_you=0
[20:25:08] 💀 zombie review worker on #413 (pid=34853) — card moved to 'QA'; killing
[20:25:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:25:20] dispatch lane=qa issue=#413 pid=52716 claim=ToanMobile
[20:25:58] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:26:36] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 413: live qa lane (pid 52716) holds it
[20:27:13] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:27:50] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:28:27] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:29:05] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:29:46] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:30:31] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:31:15] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:31:53] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:32:29] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:33:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:33:52] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:34:34] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:35:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:35:49] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:36:26] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +52716:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:36:56] worker of #413 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=668s
[20:36:59] reaped stale lock + swept assignee on #413 (pid=52716)
[20:37:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:37:14] dispatch lane=qa issue=#413 pid=35105 claim=ToanMobile
kept card 413: live qa lane (pid 35105) holds it
[20:37:51] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +35105:413) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:38:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +35105:413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:39:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=0(#413 +35105:413) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:39:37] 💀 zombie qa worker on #413 (pid=35105) — card moved to 'Blocked'; killing
[20:39:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:40:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:41:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:41:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:42:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:42:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:43:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:44:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:44:49] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:45:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:46:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:46:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:47:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:47:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:48:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:49:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:49:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:50:19] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:50:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:51:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:52:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:52:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:53:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:54:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:54:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:55:16] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:55:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:56:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:57:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:57:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:58:19] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:58:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:59:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:00:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:00:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:01:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:01:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:02:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:03:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:03:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:04:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:04:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:05:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:06:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:06:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:07:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:08:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:08:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:09:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:09:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:10:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:11:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:11:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:12:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:13:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:13:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:14:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:14:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:15:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:16:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:16:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:17:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:18:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:18:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:19:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:20:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:20:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:21:13] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:21:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:22:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:23:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:23:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:24:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:25:25] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:26:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:26:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:27:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:28:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:28:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:29:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:29:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:30:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:31:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:31:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:32:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:33:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:33:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:34:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:34:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:35:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:36:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:36:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:37:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:37:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:38:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:39:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:39:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:40:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:40:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:41:37] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:42:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:42:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:43:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:44:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:44:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:45:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:45:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:46:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:47:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:47:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:48:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:48:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:49:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:50:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:50:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:51:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:51:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:52:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:53:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:53:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:54:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:55:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:55:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:56:17] tick — Ready=2 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:56:31] preflight hold/unclear for #419: no `## Acceptance Criteria` items (`-`, `*`, `1.`, `1)`) — not dispatched, card to Blocked
[21:57:16] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=3 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:57:29] preflight hold/unclear for #421: no `## Acceptance Criteria` items (`-`, `*`, `1.`, `1)`) — not dispatched, card to Blocked
[21:58:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:58:51] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[21:59:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:00:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:00:41] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:01:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:01:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:02:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:03:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:03:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:04:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:05:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:05:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:06:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:06:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:07:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:08:03] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:08:39] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:09:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:09:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:10:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:11:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:11:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:12:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:12:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:13:27] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:14:04] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:14:40] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:15:17] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:15:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:16:29] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:17:05] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:17:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:18:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:18:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:19:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:20:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:20:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:21:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:21:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:22:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:23:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:23:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:24:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:24:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:25:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:26:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:26:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:27:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:27:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:28:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:29:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:29:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:30:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:30:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:31:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:32:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:32:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:33:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:33:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:34:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:35:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:35:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:36:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:37:00] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:37:36] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:38:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:38:48] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:39:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:39:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:40:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:41:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:41:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:42:22] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:42:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:43:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:44:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:44:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:45:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:45:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:46:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:47:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:47:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:48:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:48:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:49:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:50:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:50:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:51:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:51:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:52:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:53:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:53:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:54:20] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:54:56] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:55:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:56:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:56:44] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:57:19] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:57:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:58:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:59:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[22:59:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:00:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:00:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:01:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:02:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:02:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:03:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:03:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:04:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:05:07] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:05:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:06:19] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:06:54] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:07:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:08:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:08:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:09:18] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:09:53] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:10:30] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:11:06] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:11:43] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:12:19] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:12:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:13:32] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:14:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:14:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:15:33] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:16:09] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:16:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:17:24] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:18:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:18:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:19:14] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:19:50] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:20:26] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:21:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:21:38] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:22:15] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:22:55] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:23:31] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:24:08] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:24:45] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:25:21] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:25:57] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:26:34] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:27:10] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:27:46] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:28:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:28:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:29:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:30:11] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:30:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:31:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:31:59] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:32:35] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:33:12] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:33:47] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:34:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:34:58] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=4 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:35:35] tick — Ready=2 Building=0 QA=0 Review=0 Blocked=2 lanes: b_idle=1(#413) b_workers=0/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:35:49] dispatch lane=build issue=#416 pid=4573 claim=ToanMobile
[23:36:26] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416) b_workers=1/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:36:46] dispatch lane=build issue=#413 pid=65205 claim=ToanMobile
[23:37:24] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:38:05] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:38:45] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:39:25] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:40:04] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:40:42] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:41:21] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:42:06] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:42:46] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 65205) holds it
kept card 416: live build lane (pid 4573) holds it
kept card 419: a PR of it merged under 900s ago (Reviewer's post-merge steps)
[23:43:22] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:44:00] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:44:41] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:45:20] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:46:02] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:46:41] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:47:23] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:48:09] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:48:48] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:49:26] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:50:04] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:50:42] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:51:19] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:51:59] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:52:36] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:53:13] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 416: live build lane (pid 4573) holds it
[23:53:55] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 413: live build lane (pid 65205) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-419-vanished-flaky: a live session holds its checkout lock
kept branch issue-419-wait-bg-merge: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-419-vanished-flaky
[23:54:33] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:55:19] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:56:06] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:56:45] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:57:22] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:58:02] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:58:41] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[23:59:22] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[00:00:06] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=2 lanes: b_idle=0(#416 +65205:413) b_workers=2/5 q_idle=1(#413) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
