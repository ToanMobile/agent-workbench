[05:19:38] super-board run started — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[05:19:39] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=687s
[05:19:42] reaped stale lock + swept assignee on #226 (pid=19501)
[05:19:42] worker of #240 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=9611s
[05:19:44] reaped stale lock + swept assignee on #240 (pid=81043)
[05:19:44] worker of #307 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=15517s
[05:19:47] reaped stale lock + swept assignee on #307 (pid=65772)
[05:19:47] worker of #320 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3334s
[05:19:50] reaped stale lock + swept assignee on #320 (pid=4777)
[05:19:50] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1608s
[05:19:53] reaped stale lock + swept assignee on #323 (pid=44909)
[05:19:57] initial Ready count: 5
[05:20:09] tick — Ready=5 Building=0 QA=2 Review=2 Blocked=4 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[05:20:09] ⚠ block-rate alert: 4/5 (80%)
[05:20:22] dispatch lane=review issue=#226 pid=46217 claim=ToanMobile
[05:20:29] dispatch lane=qa issue=#323 pid=47264 claim=ToanMobile
[05:20:40] preflight sequence/overlap for #353: open PRs touch the same files — build after them — not dispatched, card to Blocked
[05:21:29] ⏳ #353: label '⏳ chờ thẻ khác' (waits on other cards)
[05:21:29] tick — Ready=4 Building=0 QA=2 Review=2 Blocked=5 lanes: b_idle=1(#_) b_workers=0/5 q_idle=0(#323) q_workers=1/5 r_idle=0(#226) r_workers=1/5 waiting_on_you=0
[05:21:40] dispatch lane=review issue=#307 pid=66667 claim=ToanMobile
[05:21:46] dispatch lane=qa issue=#240 pid=69822 claim=ToanMobile
[05:21:55] preflight #330: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[07:28:02] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[07:28:02] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=165s
[07:28:05] reaped stale lock + swept assignee on #226 (pid=46217)
[07:28:06] worker of #240 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=22s
[07:28:08] reaped stale lock + swept assignee on #240 (pid=69822)
[07:28:09] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=131s
[07:28:11] reaped stale lock + swept assignee on #307 (pid=66667)
[07:28:12] worker of #323 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=220s
[07:28:14] reaped stale lock + swept assignee on #323 (pid=47264)
[07:28:18] initial Ready count: 5
[07:28:24] ⚠ #226 (lane review): worker ended with the card still in Review and no new comment — no-op 1 of 2; last log line: {"type":"system","subtype":"task_summary","detail":null,"uuid":"6650c999-5f1d-4bc4-b1f9-8755426358d9","session_id":"7aa12aae-18c7-4a88-bce3-8da65859b9c9"}
[07:28:25] ⚠ #240 (lane qa): worker ended with the card still in QA and no new comment — no-op 1 of 2; last log line: {"type":"system","subtype":"task_summary","detail":null,"uuid":"9a79e66e-261f-4827-9637-ac9928f4667f","session_id":"97687622-7da9-4d12-af8f-b1103702fba1"}
[07:28:26] ⚠ #307 (lane review): worker ended with the card still in Review and no new comment — no-op 1 of 2; last log line: {"type":"system","subtype":"task_summary","detail":null,"uuid":"02652026-4ec2-41a8-9a2d-4513fec16677","session_id":"d4aabefd-5711-4983-b13a-db783af2e1ac"}
[07:28:33] tick — Ready=5 Building=0 QA=1 Review=2 Blocked=5 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[07:28:33] ⚠ block-rate alert: 5/5 (100%)
[07:28:47] dispatch lane=review issue=#226 pid=36144 claim=ToanMobile
[07:28:55] dispatch lane=qa issue=#240 pid=40995 claim=ToanMobile
[07:29:16] dispatch lane=build issue=#323 pid=52632 claim=ToanMobile
[07:29:48] tick — Ready=4 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#323) b_workers=1/5 q_idle=0(#240) q_workers=1/5 r_idle=0(#226) r_workers=1/5 waiting_on_you=0
[07:29:58] dispatch lane=review issue=#307 pid=73741 claim=ToanMobile
[07:30:08] preflight #330: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[07:30:14] dispatch lane=build issue=#330 pid=80164 claim=ToanMobile
[07:30:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:31:15] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=108s
[07:31:15] ⚠ worker of #323 (lane build) ended 108s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":63737,"stop_reason":"end_turn","session_id":"565fc47e-65ae-46ba-97ca-17a54a6cf7db","total_cost_usd":0.5442397999999999,"usage":{"input_tokens":36,"cache_creation_input_tokens":83193
[07:31:18] reaped stale lock + swept assignee on #323 (pid=52632)
[07:31:28] ⏳ #353: label '⏳ chờ thẻ khác' removed
[07:31:29] tick — Ready=3 Building=1 QA=2 Review=2 Blocked=4 lanes: b_idle=0(#323 +80164:330) b_workers=1/5 q_idle=0(#240) q_workers=1/5 r_idle=0(#226 +73741:307) r_workers=2/5 waiting_on_you=0
[07:31:35] dispatch lane=qa issue=#323 pid=19027 claim=ToanMobile
[07:32:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:32:36] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=138s
[07:32:39] reaped stale lock + swept assignee on #307 (pid=73741)
[07:32:49] tick — Ready=5 Building=1 QA=2 Review=1 Blocked=3 lanes: b_idle=0(#323 +80164:330) b_workers=1/5 q_idle=0(#240 +19027:323) q_workers=2/5 r_idle=0(#226) r_workers=1/5 waiting_on_you=0
[07:33:11] dispatch lane=build issue=#307 pid=17162 claim=ToanMobile
[07:33:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:34:14] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=301s
[07:34:17] reaped stale lock + swept assignee on #226 (pid=36144)
[07:34:22] tick — Ready=4 Building=2 QA=2 Review=1 Blocked=3 lanes: b_idle=0(#307 +80164:330) b_workers=2/5 q_idle=0(#240 +19027:323) q_workers=2/5 r_idle=1(#226) r_workers=0/5 waiting_on_you=0
[07:34:34] dispatch lane=review issue=#226 pid=42512 claim=ToanMobile
[07:34:34] qa workers: 5/5 running on the machine (5 here): holding
[07:34:34] qa workers: 5/5 running on the machine (5 here): holding
[07:35:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:35:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:36:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:36:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:37:13] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=131s
[07:37:16] reaped stale lock + swept assignee on #226 (pid=42512)
[07:37:21] tick — Ready=5 Building=2 QA=2 Review=0 Blocked=3 lanes: b_idle=0(#307 +80164:330) b_workers=2/5 q_idle=0(#240 +19027:323) q_workers=2/5 r_idle=1(#226) r_workers=0/5 waiting_on_you=0
[07:37:38] dispatch lane=build issue=#226 pid=54199 claim=ToanMobile
[07:38:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:38:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live build lane (pid 17162) holds it
kept card 330: live build lane (pid 80164) holds it
[07:39:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:39:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:40:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:40:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:41:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:42:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:42:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:43:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:43:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:44:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[07:44:56] worker of #330 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=875s
[07:45:01] reaped stale lock + swept assignee on #330 (pid=80164)
[07:45:09] tick — Ready=4 Building=2 QA=3 Review=0 Blocked=3 lanes: b_idle=0(#307 +54199:226) b_workers=2/5 q_idle=0(#240 +19027:323) q_workers=2/5 r_idle=1(#226) r_workers=0/5 waiting_on_you=0
[08:58:34] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[08:58:34] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1091s
[08:58:37] reaped stale lock + swept assignee on #226 (pid=54199)
[08:58:37] worker of #240 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=2020s
[08:58:41] reaped stale lock + swept assignee on #240 (pid=40995)
[08:58:41] worker of #323 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=916s
[08:58:43] reaped stale lock + swept assignee on #323 (pid=19027)
[08:58:44] adopted live build worker on #307 (pid=17162) from the previous run
[08:58:47] initial Ready count: 6
kept card 307: live build lane (pid 17162) holds it
[08:58:56] tick — Ready=6 Building=1 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#307) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[08:58:56] ⚠ block-rate alert: 2/6 (33%)
[08:59:06] dispatch lane=review issue=#240 pid=90089 claim=ToanMobile
[08:59:12] dispatch lane=qa issue=#226 pid=96468 claim=ToanMobile
[08:59:30] dispatch lane=build issue=#319 pid=16429 claim=ToanMobile
[09:00:01] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=5182s
[09:00:04] reaped stale lock + swept assignee on #307 (pid=17162)
[09:00:06] tick — Ready=5 Building=1 QA=3 Review=1 Blocked=2 lanes: b_idle=0(#307 +16429:319) b_workers=1/5 q_idle=0(#226) q_workers=1/5 r_idle=0(#240) r_workers=1/5 waiting_on_you=0
[09:00:13] dispatch lane=qa issue=#307 pid=82195 claim=ToanMobile
[09:00:30] dispatch lane=build issue=#320 pid=95886 claim=ToanMobile
[09:01:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:01:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:02:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:02:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:03:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:03:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:04:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:04:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:05:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:05:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:06:28] worker of #307 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=365s
[09:06:32] reaped stale lock + swept assignee on #307 (pid=82195)
[09:06:50] ⏳ #78: label '⏳ chờ thẻ khác' removed
[09:06:58] ↩ unblocked #78: Blocked → Ready (cleared by #240)
[09:07:00] tick — Ready=5 Building=2 QA=2 Review=1 Blocked=1 lanes: b_idle=0(#320 +16429:319) b_workers=2/5 q_idle=0(#226) q_workers=1/5 r_idle=0(#240) r_workers=1/5 waiting_on_you=0
[09:07:20] dispatch lane=review issue=#307 pid=83004 claim=ToanMobile
[09:07:20] qa workers: 5/5 running on the machine (5 here): holding
[09:07:20] qa workers: 5/5 running on the machine (5 here): holding
[09:07:55] 💀 zombie review worker on #240 (pid=90089) — card moved to 'Done'; killing
[09:08:14] tick — Ready=6 Building=2 QA=2 Review=1 Blocked=1 lanes: b_idle=0(#320 +16429:319) b_workers=2/5 q_idle=0(#226) q_workers=1/5 r_idle=0(#_ +83004:307) r_workers=1/5 waiting_on_you=0
[09:08:26] dispatch lane=qa issue=#330 pid=8997 claim=ToanMobile
[09:09:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 330: live qa lane (pid 8997) holds it
kept card 320: live build lane (pid 95886) holds it
kept card 226: live qa lane (pid 96468) holds it
kept card 307: live review lane (pid 83004) holds it
[09:09:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:10:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:10:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:11:13] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=206s
[09:11:17] reaped stale lock + swept assignee on #307 (pid=83004)
[09:11:27] tick — Ready=7 Building=2 QA=2 Review=0 Blocked=1 lanes: b_idle=0(#320 +16429:319) b_workers=2/5 q_idle=0(#226 +8997:330) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[09:11:57] dispatch lane=build issue=#307 pid=15623 claim=ToanMobile
[09:12:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:13:05] worker of #330 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=275s
[09:13:09] reaped stale lock + swept assignee on #330 (pid=8997)
[09:13:26] tick — Ready=6 Building=3 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#320 +16429:319 15623:307) b_workers=3/5 q_idle=0(#226) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[09:13:58] dispatch lane=build issue=#323 pid=13998 claim=ToanMobile
[09:14:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:15:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:15:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:16:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:16:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:17:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:17:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:18:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:19:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 16429) holds it
kept card 307: live build lane (pid 15623) holds it
kept card 320: live build lane (pid 95886) holds it
kept card 323: live build lane (pid 13998) holds it
[09:19:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:20:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:20:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:21:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:21:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:22:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:22:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:23:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:23:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:24:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:25:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:25:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:26:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:26:35] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1633s
[09:26:37] reaped stale lock + swept assignee on #226 (pid=96468)
[09:26:54] tick — Ready=5 Building=3 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#320 +16429:319 15623:307 13998:323) b_workers=4/5 q_idle=1(#226) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[09:27:07] dispatch lane=review issue=#321 pid=6017 claim=ToanMobile
[09:27:07] qa workers: 5/5 running on the machine (5 here): holding
[09:27:07] qa workers: 5/5 running on the machine (5 here): holding
[09:27:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:28:09] 💀 zombie build worker on #319 (pid=16429) — card moved to 'Blocked'; killing
[09:28:14] tick — Ready=5 Building=3 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#320 +15623:307 13998:323) b_workers=3/5 q_idle=1(#226) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[09:28:26] dispatch lane=review issue=#226 pid=90800 claim=ToanMobile
[09:28:26] qa workers: 5/5 running on the machine (5 here): holding
[09:28:26] qa workers: 5/5 running on the machine (5 here): holding
[09:28:56] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=102s
[09:28:56] ⚠ worker of #321 (lane review) ended 102s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":37930,"stop_reason":"end_turn","session_id":"95247c6c-12f6-41b4-bf83-fd06df0e18ef","total_cost_usd":0.44967560000000006,"usage":{"input_tokens":24,"cache_creation_input_tokens":7927
[09:28:59] reaped stale lock + swept assignee on #321 (pid=6017)
[09:29:10] tick — Ready=5 Building=3 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#320 +15623:307 13998:323) b_workers=3/5 q_idle=1(#226) q_workers=0/5 r_idle=0(#321 +90800:226) r_workers=1/5 waiting_on_you=0
[09:29:18] dispatch lane=qa issue=#330 pid=15290 claim=ToanMobile
[09:29:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 330: live qa lane (pid 15290) holds it
kept card 323: live build lane (pid 13998) holds it
kept card 307: live build lane (pid 15623) holds it
kept card 226: live review lane (pid 90800) holds it
[09:30:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:30:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:31:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:31:57] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=194s
[09:31:59] reaped stale lock + swept assignee on #226 (pid=90800)
[09:32:03] tick — Ready=6 Building=3 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#320 +15623:307 13998:323) b_workers=3/5 q_idle=0(#330) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[09:32:17] preflight sequence/overlap for #226: open PRs touch the same files — build after them — not dispatched, card to Blocked
[09:33:06] ⏳ #226: label '⏳ chờ thẻ khác' (waits on other cards)
[09:33:06] tick — Ready=5 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#320 +15623:307 13998:323) b_workers=3/5 q_idle=0(#330) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[09:33:22] dispatch lane=build issue=#346 pid=54553 claim=ToanMobile
[09:33:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:34:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:34:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:35:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:35:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:36:26] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1455s
[09:36:29] reaped stale lock + swept assignee on #307 (pid=15623)
[09:36:32] tick — Ready=4 Building=3 QA=2 Review=0 Blocked=3 lanes: b_idle=0(#320 +13998:323 54553:346) b_workers=3/5 q_idle=0(#330) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[09:36:39] dispatch lane=qa issue=#307 pid=11560 claim=ToanMobile
[09:37:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:37:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:38:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:38:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:39:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:39:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live build lane (pid 54553) holds it
kept card 323: live build lane (pid 13998) holds it
kept card 330: live qa lane (pid 15290) holds it
[09:40:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:41:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:41:33] worker of #330 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=733s
[09:41:37] reaped stale lock + swept assignee on #330 (pid=15290)
[09:41:46] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#320 +13998:323 54553:346) b_workers=3/5 q_idle=0(#330 +11560:307) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[09:42:04] dispatch lane=review issue=#330 pid=21122 claim=ToanMobile
[09:42:04] qa workers: 5/5 running on the machine (5 here): holding
[09:42:04] qa workers: 5/5 running on the machine (5 here): holding
[09:42:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:43:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:43:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:44:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:44:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:45:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:45:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:46:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[09:47:00] worker of #330 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=284s
[09:47:03] reaped stale lock + swept assignee on #330 (pid=21122)
[09:47:08] tick — Ready=5 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#320 +13998:323 54553:346) b_workers=3/5 q_idle=0(#330 +11560:307) q_workers=1/5 r_idle=1(#330) r_workers=0/5 waiting_on_you=0
[10:18:22] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[10:18:23] worker of #307 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1252s
[10:18:26] reaped stale lock + swept assignee on #307 (pid=11560)
[10:18:26] worker of #320 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4122s
[10:18:29] reaped stale lock + swept assignee on #320 (pid=95886)
[10:18:29] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2891s
[10:18:32] reaped stale lock + swept assignee on #323 (pid=13998)
[10:18:32] worker of #346 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1013s
[10:18:35] reaped stale lock + swept assignee on #346 (pid=54553)
[10:18:38] initial Ready count: 5
[10:18:42] ⚠ self-reload: cannot create worktree .claude/worktrees/self-reload-39243-1792811922: s/needs-you-guard-approval-link, /Volumes/Data/Toan/agent-workbench/.claude/worktrees/verify-t0052 — chỉ gộp và gỡ worktree do CHÍNH phiên này tạo mà đã xong (`agent-kit worktree finish <path>`); worktree của phiên khác, kể cả đang sạch, thì để yên và chờ nó xong
[10:18:42] ⚠ self-reload: origin/main has a newer super-board-run.sh but this runner keeps the old code — main has local commits and merging origin/main through worktree finish failed (conflict, red gate or dirty files in the way)
[10:19:03] tick — Ready=5 Building=0 QA=3 Review=1 Blocked=3 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:19:03] ⚠ block-rate alert: 3/5 (60%)
[10:19:12] dispatch lane=review issue=#307 pid=73083 claim=ToanMobile
[10:19:18] dispatch lane=qa issue=#346 pid=74831 claim=ToanMobile
[10:19:37] dispatch lane=build issue=#330 pid=77650 claim=ToanMobile
[10:20:10] tick — Ready=4 Building=1 QA=3 Review=1 Blocked=3 lanes: b_idle=0(#330) b_workers=1/5 q_idle=0(#346) q_workers=1/5 r_idle=0(#307) r_workers=1/5 waiting_on_you=0
[10:20:15] dispatch lane=qa issue=#323 pid=21538 claim=ToanMobile
[10:20:25] preflight #360: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[10:20:30] dispatch lane=build issue=#360 pid=25605 claim=ToanMobile
[10:21:01] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=106s
[10:21:01] ⚠ worker of #307 (lane review) ended 106s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":45832,"stop_reason":"end_turn","session_id":"05c108e5-6c4f-4c4a-883a-7fb9dd668f8c","total_cost_usd":0.48857180000000006,"usage":{"input_tokens":30,"cache_creation_input_tokens":8064
[10:21:04] reaped stale lock + swept assignee on #307 (pid=73083)
[10:21:09] tick — Ready=4 Building=2 QA=3 Review=0 Blocked=3 lanes: b_idle=0(#330 +25605:360) b_workers=2/5 q_idle=0(#346 +21538:323) q_workers=2/5 r_idle=1(#307) r_workers=0/5 waiting_on_you=0
[10:21:16] dispatch lane=qa issue=#320 pid=21039 claim=ToanMobile
[10:21:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:22:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:23:20] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[10:23:21] adopted live qa worker on #320 (pid=21039) from the previous run
[10:23:21] adopted live qa worker on #323 (pid=21538) from the previous run
[10:23:21] adopted live build worker on #330 (pid=77650) from the previous run
[10:23:21] adopted live qa worker on #346 (pid=74831) from the previous run
[10:23:21] adopted live build worker on #360 (pid=25605) from the previous run
[10:23:24] initial Ready count: 4
[10:23:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:23:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:24:26] 💀 zombie qa worker on #323 (pid=21538) — card moved to 'Review'; killing
[10:24:39] tick — Ready=4 Building=1 QA=3 Review=1 Blocked=3 lanes: b_idle=0(#330 +25605:360) b_workers=2/5 q_idle=0(#320 +74831:346) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:24:39] ⚠ block-rate alert: 3/4 (75%)
[10:24:48] dispatch lane=review issue=#323 pid=52867 claim=ToanMobile
[10:24:48] qa workers: 5/5 running on the machine (5 here): holding
[10:24:48] qa workers: 5/5 running on the machine (5 here): holding
[10:25:19] worker of #330 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=312s
[10:25:23] reaped stale lock + swept assignee on #330 (pid=77650)
[10:25:25] tick — Ready=4 Building=1 QA=3 Review=1 Blocked=3 lanes: b_idle=0(#330 +25605:360) b_workers=1/5 q_idle=0(#320 +74831:346) q_workers=2/5 r_idle=0(#323) r_workers=1/5 waiting_on_you=0
[10:25:32] dispatch lane=qa issue=#330 pid=15925 claim=ToanMobile
[10:32:01] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[10:32:03] worker of #323 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=222s
[10:32:05] reaped stale lock + swept assignee on #323 (pid=52867)
[10:32:07] adopted live qa worker on #320 (pid=21039) from the previous run
[10:32:07] adopted live qa worker on #330 (pid=15925) from the previous run
[10:32:07] adopted live qa worker on #346 (pid=74831) from the previous run
[10:32:07] adopted live build worker on #360 (pid=25605) from the previous run
[10:32:11] initial Ready count: 5
kept card 330: live qa lane (pid 15925) holds it
kept card 320: live qa lane (pid 21039) holds it
kept card 346: live qa lane (pid 74831) holds it
[10:32:27] tick — Ready=5 Building=1 QA=3 Review=0 Blocked=3 lanes: b_idle=0(#360) b_workers=1/5 q_idle=0(#320 +15925:330 74831:346) q_workers=3/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:32:27] ⚠ block-rate alert: 3/5 (60%)
[10:32:57] dispatch lane=build issue=#307 pid=99266 claim=ToanMobile
[10:33:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:34:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:34:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:35:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:35:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:36:08] worker of #330 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=620s
[10:36:10] reaped stale lock + swept assignee on #330 (pid=15925)
[10:36:13] tick — Ready=4 Building=2 QA=2 Review=1 Blocked=3 lanes: b_idle=0(#360 +99266:307) b_workers=2/5 q_idle=0(#320 +74831:346) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[10:36:25] dispatch lane=review issue=#330 pid=77823 claim=ToanMobile
[10:36:25] qa workers: 5/5 running on the machine (5 here): holding
[10:36:25] qa workers: 5/5 running on the machine (5 here): holding
[10:36:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:37:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:38:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:38:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:39:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:39:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:40:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:40:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:41:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:41:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:42:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live qa lane (pid 74831) holds it
kept card 307: live build lane (pid 99266) holds it
[10:42:49] worker of #330 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=371s
[10:42:52] reaped stale lock + swept assignee on #330 (pid=77823)
[10:43:03] tick — Ready=4 Building=2 QA=2 Review=0 Blocked=3 lanes: b_idle=0(#360 +99266:307) b_workers=2/5 q_idle=0(#320 +74831:346) q_workers=2/5 r_idle=1(#330) r_workers=0/5 waiting_on_you=0
[10:43:17] dispatch lane=build issue=#323 pid=75966 claim=ToanMobile
[10:43:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:44:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:44:50] worker of #320 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1390s
[10:44:52] reaped stale lock + swept assignee on #320 (pid=21039)
[10:44:56] tick — Ready=3 Building=3 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#360 +99266:307 75966:323) b_workers=3/5 q_idle=0(#320 +74831:346) q_workers=1/5 r_idle=1(#330) r_workers=0/5 waiting_on_you=0
[10:45:05] dispatch lane=review issue=#320 pid=14659 claim=ToanMobile
[10:45:05] qa workers: 5/5 running on the machine (5 here): holding
[10:45:05] qa workers: 5/5 running on the machine (5 here): holding
[10:45:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:46:07] worker of #360 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1536s
[10:46:09] reaped stale lock + swept assignee on #360 (pid=25605)
[10:46:18] reconciled closed #360 -> Done (was 'Building') — builder closed it, AC already met
[10:46:18] tick — Ready=3 Building=3 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#360 +99266:307 75966:323) b_workers=2/5 q_idle=0(#320 +74831:346) q_workers=1/5 r_idle=0(#320) r_workers=1/5 waiting_on_you=0
[10:46:34] dispatch lane=build issue=#78 pid=7871 claim=ToanMobile
[10:47:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:47:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:48:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:48:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:49:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:49:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:50:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:50:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:51:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:51:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:52:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live build lane (pid 99266) holds it
kept card 320: live review lane (pid 14659) holds it
kept card 323: live build lane (pid 75966) holds it
kept card 346: live qa lane (pid 74831) holds it
[10:53:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:53:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:54:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:54:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:55:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:55:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:56:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:56:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:57:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:57:52] worker of #320 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=753s
[10:57:56] reaped stale lock + swept assignee on #320 (pid=14659)
[10:58:09] tick — Ready=3 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#78 +99266:307 75966:323) b_workers=3/5 q_idle=0(#320 +74831:346) q_workers=1/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[10:58:24] dispatch lane=build issue=#320 pid=80408 claim=ToanMobile
[10:58:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:59:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[10:59:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:00:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:00:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:01:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:02:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:02:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live build lane (pid 99266) holds it
kept card 323: live build lane (pid 75966) holds it
kept card 78: live build lane (pid 7871) holds it
kept card 346: live qa lane (pid 74831) holds it
[11:03:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:03:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:04:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:04:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:05:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:06:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:06:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:07:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:07:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:08:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:08:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:09:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:10:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:10:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:11:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:11:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:12:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:12:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live build lane (pid 99266) holds it
kept card 320: live build lane (pid 80408) holds it
kept card 346: live qa lane (pid 74831) holds it
[11:13:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:13:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:14:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:14:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:15:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:16:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:16:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:17:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:17:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:18:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:18:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:19:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:19:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:20:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:21:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:21:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:22:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:22:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:23:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live qa lane (pid 74831) holds it
kept card 78: live build lane (pid 7871) holds it
kept card 307: live build lane (pid 99266) holds it
kept card 320: live build lane (pid 80408) holds it
[11:23:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:24:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:24:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:25:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:25:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:26:18] worker of #346 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=4013s
[11:26:20] reaped stale lock + swept assignee on #346 (pid=74831)
[11:26:26] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#78 +99266:307 75966:323 80408:320) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[11:26:39] dispatch lane=review issue=#346 pid=39425 claim=ToanMobile
[11:26:39] qa workers: 5/5 running on the machine (5 here): holding
[11:27:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:27:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:28:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:28:44] worker of #346 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=105s
[11:28:44] ⚠ worker of #346 (lane review) ended 105s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":34140,"stop_reason":"end_turn","session_id":"75de9868-30a9-4728-86f3-59d2247cf765","total_cost_usd":0.41394539999999996,"usage":{"input_tokens":24,"cache_creation_input_tokens":7335
[11:28:47] reaped stale lock + swept assignee on #346 (pid=39425)
[11:28:50] tick — Ready=3 Building=4 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#78 +99266:307 75966:323 80408:320) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[11:29:06] dispatch lane=build issue=#346 pid=62772 claim=ToanMobile
[11:29:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:30:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:30:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:31:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:31:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:32:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:32:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:33:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 320: live build lane (pid 80408) holds it
kept card 307: live build lane (pid 99266) holds it
kept card 346: live build lane (pid 62772) holds it
[11:33:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:34:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:35:00] worker of #78 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2906s
[11:35:03] reaped stale lock + swept assignee on #78 (pid=7871)
[11:35:08] tick — Ready=2 Building=4 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#78 +99266:307 75966:323 80408:320 62772:346) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[11:35:17] dispatch lane=qa issue=#78 pid=58476 claim=ToanMobile
[11:35:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:36:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:36:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:37:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:37:56] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3872s
[11:37:59] reaped stale lock + swept assignee on #307 (pid=99266)
[11:37:59] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3280s
[11:38:01] reaped stale lock + swept assignee on #323 (pid=75966)
[11:38:04] tick — Ready=2 Building=2 QA=3 Review=0 Blocked=3 lanes: b_idle=0(#78 +80408:320 62772:346) b_workers=2/5 q_idle=0(#78) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[11:38:10] dispatch lane=qa issue=#323 pid=10637 claim=ToanMobile
[11:38:24] dispatch lane=build issue=#181 pid=29836 claim=ToanMobile
[11:38:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:39:25] worker of #78 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=236s
[11:39:28] reaped stale lock + swept assignee on #78 (pid=58476)
[11:39:33] tick — Ready=1 Building=3 QA=2 Review=1 Blocked=3 lanes: b_idle=0(#181 +80408:320 62772:346) b_workers=3/5 q_idle=0(#78 +10637:323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[11:39:45] dispatch lane=review issue=#78 pid=63873 claim=ToanMobile
[11:39:45] qa workers: 5/5 running on the machine (5 here): holding
[11:39:45] qa workers: 5/5 running on the machine (5 here): holding
[11:40:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:40:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:41:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:41:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:42:37] tick — Ready=1 Building=3 QA=2 Review=0 Blocked=3 lanes: b_idle=0(#181 +80408:320 62772:346) b_workers=3/5 q_idle=0(#78 +10637:323) q_workers=1/5 r_idle=1(#78) r_workers=0/5 waiting_on_you=0
[11:42:48] dispatch lane=qa issue=#307 pid=39976 claim=ToanMobile
[11:43:20] worker of #78 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=157s
[11:43:25] reaped stale lock + swept assignee on #78 (pid=63873)
[11:43:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 181: live build lane (pid 29836) holds it
kept card 307: live qa lane (pid 39976) holds it
kept card 320: live build lane (pid 80408) holds it
kept card 323: live qa lane (pid 10637) holds it
kept card 346: live build lane (pid 62772) holds it
[11:44:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:44:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:45:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:45:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:46:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:46:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:47:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:47:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:48:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:48:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:49:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:49:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:50:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:50:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:51:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:51:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:52:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:52:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:53:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live qa lane (pid 39976) holds it
kept card 346: live build lane (pid 62772) holds it
kept card 323: live qa lane (pid 10637) holds it
[11:54:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:54:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:55:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:55:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:56:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:56:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:57:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:57:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:58:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:58:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:59:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[11:59:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:00:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:00:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:01:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:02:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:02:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:03:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:03:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 323: live qa lane (pid 10637) holds it
kept card 307: live qa lane (pid 39976) holds it
kept card 346: live build lane (pid 62772) holds it
kept card 181: live build lane (pid 29836) holds it
[12:04:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:04:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:05:08] worker of #307 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1335s
[12:05:11] reaped stale lock + swept assignee on #307 (pid=39976)
[12:05:24] tick — Ready=2 Building=3 QA=0 Review=2 Blocked=2 lanes: b_idle=0(#181 +80408:320 62772:346) b_workers=3/5 q_idle=0(#307 +10637:323) q_workers=1/5 r_idle=1(#78) r_workers=0/5 waiting_on_you=0
[12:05:38] dispatch lane=review issue=#307 pid=15099 claim=ToanMobile
[12:05:38] qa workers: 5/5 running on the machine (5 here): holding
[12:06:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:06:39] worker of #346 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2242s
[12:06:42] reaped stale lock + swept assignee on #346 (pid=62772)
[12:06:43] 💀 zombie qa worker on #323 (pid=10637) — card moved to 'Review'; killing
[12:06:49] tick — Ready=2 Building=2 QA=1 Review=2 Blocked=2 lanes: b_idle=0(#181 +80408:320) b_workers=2/5 q_idle=1(#307) q_workers=0/5 r_idle=0(#307) r_workers=1/5 waiting_on_you=0
[12:07:01] dispatch lane=review issue=#323 pid=42711 claim=ToanMobile
[12:07:07] dispatch lane=qa issue=#346 pid=62020 claim=ToanMobile
[12:07:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:08:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:08:40] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=166s
[12:08:43] reaped stale lock + swept assignee on #307 (pid=15099)
[12:08:44] worker of #320 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4216s
[12:08:46] reaped stale lock + swept assignee on #320 (pid=80408)
[12:08:58] tick — Ready=2 Building=1 QA=2 Review=1 Blocked=3 lanes: b_idle=0(#181) b_workers=1/5 q_idle=0(#346) q_workers=1/5 r_idle=0(#307 +42711:323) r_workers=1/5 waiting_on_you=0
[12:09:05] dispatch lane=qa issue=#320 pid=54355 claim=ToanMobile
[12:09:23] dispatch lane=build issue=#319 pid=75316 claim=ToanMobile
[12:09:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:10:25] worker of #346 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=190s
[12:10:27] reaped stale lock + swept assignee on #346 (pid=62020)
[12:10:33] tick — Ready=1 Building=2 QA=1 Review=2 Blocked=3 lanes: b_idle=0(#181 +75316:319) b_workers=2/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=0(#307 +42711:323) r_workers=1/5 waiting_on_you=0
[12:10:47] dispatch lane=review issue=#346 pid=78797 claim=ToanMobile
[12:10:47] qa workers: 5/5 running on the machine (5 here): holding
[12:10:47] qa workers: 5/5 running on the machine (5 here): holding
[12:11:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:11:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:12:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:12:51] worker of #323 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=324s
[12:12:54] reaped stale lock + swept assignee on #323 (pid=42711)
[12:12:58] tick — Ready=2 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#181 +75316:319) b_workers=2/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[12:13:16] dispatch lane=build issue=#323 pid=71475 claim=ToanMobile
[12:13:47] worker of #346 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=155s
[12:13:50] reaped stale lock + swept assignee on #346 (pid=78797)
[12:13:54] tick — Ready=2 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#181 +75316:319 71475:323) b_workers=3/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 323: live build lane (pid 71475) holds it
kept card 320: live qa lane (pid 54355) holds it
[12:14:11] dispatch lane=build issue=#346 pid=77875 claim=ToanMobile
[12:14:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:15:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:15:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:16:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:17:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:17:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:18:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:18:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:19:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:19:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:20:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:21:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:21:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:22:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:22:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:23:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:23:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live build lane (pid 77875) holds it
kept card 320: live qa lane (pid 54355) holds it
kept card 323: live build lane (pid 71475) holds it
[12:24:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:24:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:25:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:26:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:26:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:27:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:27:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:28:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:28:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:29:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:30:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:30:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:31:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:31:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:32:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:32:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:33:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:33:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:34:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 320: live qa lane (pid 54355) holds it
kept card 181: live build lane (pid 29836) holds it
kept card 319: live build lane (pid 75316) holds it
kept card 323: live build lane (pid 71475) holds it
kept card 346: live build lane (pid 77875) holds it
[12:34:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:35:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:35:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:36:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:37:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:37:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:38:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:38:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:39:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:39:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:40:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:40:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:41:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:41:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:42:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:42:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:43:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:44:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:44:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 75316) holds it
kept card 181: live build lane (pid 29836) holds it
kept card 346: live build lane (pid 77875) holds it
[12:45:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:45:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:46:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:46:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:47:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:48:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:48:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:49:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:49:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:50:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:50:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:51:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:52:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:52:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:53:05] worker of #181 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4455s
[12:53:09] reaped stale lock + swept assignee on #181 (pid=29836)
[12:53:26] ⏳ #226: label '⏳ chờ thẻ khác' removed
[12:53:26] tick — Ready=2 Building=2 QA=2 Review=2 Blocked=1 lanes: b_idle=0(#181 +75316:319 71475:323 77875:346) b_workers=3/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[12:53:42] review lane issue=#321: PR #342 approved at head 8f65815cd0326b6ec5c35ec5c09e16c9017c6bcf — merge-only, no fresh review
[12:53:43] dispatch lane=review issue=#321 pid=48560 claim=ToanMobile
[12:53:43] qa workers: 5/5 running on the machine (5 here): holding
[12:53:43] qa workers: 5/5 running on the machine (5 here): holding
[12:54:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:54:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live build lane (pid 77875) holds it
kept card 323: live build lane (pid 71475) holds it
kept card 319: live build lane (pid 75316) holds it
[12:55:20] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=69s
[12:55:20] ⚠ worker of #321 (lane review) ended 69s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":20111,"stop_reason":"end_turn","session_id":"ececfcbb-1eb6-4ee0-8088-45c8d762655d","total_cost_usd":0.3113683,"usage":{"input_tokens":14,"cache_creation_input_tokens":62048,"cache_r
[12:55:24] reaped stale lock + swept assignee on #321 (pid=48560)
[12:55:31] tick — Ready=3 Building=2 QA=2 Review=1 Blocked=1 lanes: b_idle=0(#181 +75316:319 71475:323 77875:346) b_workers=3/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[12:55:46] review lane issue=#307: PR #341 approved at head 78f8787efeaa154a12f5b17518b45c43c696be12 — merge-only, no fresh review
[12:55:46] dispatch lane=review issue=#307 pid=38801 claim=ToanMobile
[12:55:46] qa workers: 5/5 running on the machine (5 here): holding
[12:55:46] qa workers: 5/5 running on the machine (5 here): holding
[12:56:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:56:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:57:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:57:50] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2893s
[12:57:53] reaped stale lock + swept assignee on #319 (pid=75316)
[12:58:01] tick — Ready=3 Building=1 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#181 +71475:323 77875:346) b_workers=2/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=0(#307) r_workers=1/5 waiting_on_you=0
[12:58:17] dispatch lane=build issue=#226 pid=42230 claim=ToanMobile
[12:58:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[12:59:20] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2739s
[12:59:23] reaped stale lock + swept assignee on #323 (pid=71475)
[12:59:26] tick — Ready=2 Building=1 QA=2 Review=2 Blocked=2 lanes: b_idle=0(#226 +77875:346) b_workers=2/5 q_idle=0(#346 +54355:320) q_workers=1/5 r_idle=0(#307) r_workers=1/5 waiting_on_you=0
[12:59:34] dispatch lane=qa issue=#323 pid=58428 claim=ToanMobile
[12:59:52] dispatch lane=build issue=#321 pid=89374 claim=ToanMobile
[13:00:23] worker of #320 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=3022s
[13:00:25] reaped stale lock + swept assignee on #320 (pid=54355)
[13:00:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:01:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:01:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:02:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:02:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:03:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:03:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:04:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:04:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 346: live build lane (pid 77875) holds it
kept card 307: live review lane (pid 38801) holds it
kept card 323: live qa lane (pid 58428) holds it
[13:05:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:05:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:06:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:07:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:07:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:08:01] worker of #346 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3201s
[13:08:04] reaped stale lock + swept assignee on #346 (pid=77875)
[13:08:08] tick — Ready=1 Building=2 QA=2 Review=2 Blocked=2 lanes: b_idle=0(#226 +89374:321) b_workers=2/5 q_idle=0(#323) q_workers=1/5 r_idle=0(#307) r_workers=1/5 waiting_on_you=0
[13:08:17] dispatch lane=review issue=#320 pid=88930 claim=ToanMobile
[13:08:17] qa workers: 5/5 running on the machine (5 here): holding
[13:08:17] qa workers: 5/5 running on the machine (5 here): holding
[13:08:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:09:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:09:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:10:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:10:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:11:23] worker of #307 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=911s
[13:11:26] reaped stale lock + swept assignee on #307 (pid=38801)
[13:11:38] tick — Ready=1 Building=2 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#226 +89374:321) b_workers=2/5 q_idle=0(#323) q_workers=1/5 r_idle=0(#307 +88930:320) r_workers=1/5 waiting_on_you=0
[13:11:45] dispatch lane=qa issue=#346 pid=16346 claim=ToanMobile
[13:12:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:12:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:13:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:13:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:14:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:14:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 320: live review lane (pid 88930) holds it
kept card 226: live build lane (pid 42230) holds it
kept card 307: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 321: live build lane (pid 89374) holds it
[13:15:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:16:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:16:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:17:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:17:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:18:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:18:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:19:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:20:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:20:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:21:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:21:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:22:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:22:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:23:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:24:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:24:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:25:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 321: live build lane (pid 89374) holds it
kept card 323: live qa lane (pid 58428) holds it
[13:25:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:26:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:26:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:27:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:27:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:28:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:28:53] worker of #346 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1002s
[13:28:56] reaped stale lock + swept assignee on #346 (pid=16346)
[13:28:59] tick — Ready=1 Building=2 QA=1 Review=2 Blocked=2 lanes: b_idle=0(#226 +89374:321) b_workers=2/5 q_idle=0(#323) q_workers=1/5 r_idle=0(#307 +88930:320) r_workers=1/5 waiting_on_you=0
[13:29:10] dispatch lane=review issue=#346 pid=88225 claim=ToanMobile
[13:29:10] qa workers: 5/5 running on the machine (5 here): holding
[13:29:10] qa workers: 5/5 running on the machine (5 here): holding
[13:29:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:30:12] worker of #346 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=60s
[13:30:12] ⚠ worker of #346 (lane review) ended 60s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":36440,"stop_reason":"end_turn","session_id":"108ca265-facd-4f00-9e13-db481e81caa3","total_cost_usd":0.45332150000000004,"usage":{"input_tokens":22,"cache_creation_input_tokens":8208
[13:30:14] reaped stale lock + swept assignee on #346 (pid=88225)
[13:30:24] tick — Ready=1 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#226 +89374:321) b_workers=2/5 q_idle=0(#323) q_workers=1/5 r_idle=0(#346 +88930:320) r_workers=1/5 waiting_on_you=0
[13:30:42] dispatch lane=build issue=#291 pid=36100 claim=ToanMobile
[13:31:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:31:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:32:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:32:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:33:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:33:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:34:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:35:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:35:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 320: live review lane (pid 88930) holds it
kept card 323: live qa lane (pid 58428) holds it
kept card 291: live build lane (pid 36100) holds it
kept card 321: live build lane (pid 89374) holds it
kept card 226: live build lane (pid 42230) holds it
[13:36:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:36:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:37:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:37:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:38:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:38:47] worker of #320 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1806s
[13:38:52] reaped stale lock + swept assignee on #320 (pid=88930)
[13:39:16] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:39:55] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:40:36] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:41:15] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:41:53] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:42:30] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:43:06] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:43:41] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:44:18] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:44:54] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:45:29] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:46:02] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 323: live qa lane (pid 58428) holds it
kept card 226: live build lane (pid 42230) holds it
kept card 320: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 321: live build lane (pid 89374) holds it
kept card 291: live build lane (pid 36100) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[13:46:34] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:47:09] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:47:46] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:48:20] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:48:54] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:49:27] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:50:00] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=3/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:50:37] tick — Ready=4 Building=2 QA=2 Review=0 Blocked=0 lanes: b_idle=0(#226 +89374:321 36100:291) b_workers=2/5 q_idle=0(#323) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:50:37] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3136s
[13:50:43] dispatch lane=qa issue=#226 pid=84640 claim=ToanMobile
[13:50:58] dispatch lane=build issue=#319 pid=670 claim=ToanMobile
[13:51:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:52:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:52:35] worker of #321 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3154s
[13:52:38] reaped stale lock + swept assignee on #321 (pid=89374)
[13:52:42] tick — Ready=3 Building=2 QA=3 Review=0 Blocked=0 lanes: b_idle=0(#319 +36100:291) b_workers=2/5 q_idle=0(#323 +84640:226) q_workers=2/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[13:52:51] dispatch lane=qa issue=#321 pid=5270 claim=ToanMobile
[13:53:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:53:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:54:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:55:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:55:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:56:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
✔ prune-branch: issue-320-hooks-settings-gom (f3d7758c7c32) đã nằm trong trunk; commit chỉ nhánh giữ đã cất ở refs/devkit/discarded/branch-issue-320-hooks-settings-gom-20261024-135614-65540 (30 ngày), đã xoá
kept card 321: live qa lane (pid 5270) holds it
kept card 323: live qa lane (pid 58428) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 319: live build lane (pid 670) holds it
[13:56:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:57:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:57:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:58:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:58:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:59:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[13:59:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:00:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:01:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:01:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:02:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:02:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:03:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:03:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:04:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:04:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:05:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:06:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:06:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 226: live qa lane (pid 84640) holds it
[14:07:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 321: live qa lane (pid 5270) holds it
kept card 323: live qa lane (pid 58428) holds it
kept card 319: live build lane (pid 670) holds it
[14:07:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:08:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:08:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:09:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:09:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:10:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:11:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:11:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:12:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:12:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:13:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:13:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:14:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:14:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:15:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:15:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:16:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:16:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 323: live qa lane (pid 58428) holds it
kept card 319: live build lane (pid 670) holds it
kept card 321: live qa lane (pid 5270) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[14:17:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
[14:18:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:18:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:19:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:19:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:20:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:20:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:21:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:21:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:22:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:22:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:23:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:23:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:24:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:24:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:25:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:25:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:26:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:27:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 291: live build lane (pid 36100) holds it
kept card 226: live qa lane (pid 84640) holds it
kept card 321: live qa lane (pid 5270) holds it
kept card 319: live build lane (pid 670) holds it
[14:27:30] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=2193s
[14:27:33] reaped stale lock + swept assignee on #226 (pid=84640)
[14:27:39] tick — Ready=3 Building=1 QA=2 Review=1 Blocked=1 lanes: b_idle=0(#319 +36100:291) b_workers=2/5 q_idle=0(#323 +5270:321) q_workers=2/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[14:27:49] dispatch lane=review issue=#226 pid=79898 claim=ToanMobile
[14:27:49] qa workers: 5/5 running on the machine (5 here): holding
[14:27:49] qa workers: 5/5 running on the machine (5 here): holding
[14:28:20] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2227s
[14:28:22] reaped stale lock + swept assignee on #319 (pid=670)
[14:28:25] tick — Ready=3 Building=1 QA=2 Review=1 Blocked=1 lanes: b_idle=0(#319 +36100:291) b_workers=1/5 q_idle=0(#323 +5270:321) q_workers=2/5 r_idle=0(#226) r_workers=1/5 waiting_on_you=0
[14:28:40] dispatch lane=build issue=#346 pid=1441 claim=ToanMobile
[14:29:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:29:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:30:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:30:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:31:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:31:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:32:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:32:48] worker of #323 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=5564s
[14:32:51] reaped stale lock + swept assignee on #323 (pid=58428)
[14:32:56] tick — Ready=3 Building=2 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#346 +36100:291) b_workers=2/5 q_idle=0(#323 +5270:321) q_workers=1/5 r_idle=0(#226) r_workers=1/5 waiting_on_you=0
[14:33:09] dispatch lane=review issue=#323 pid=58067 claim=ToanMobile
[14:33:09] qa workers: 5/5 running on the machine (5 here): holding
[14:33:09] qa workers: 5/5 running on the machine (5 here): holding
[14:33:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:34:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:34:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:35:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:35:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:36:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:36:44] worker of #346 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=454s
[14:36:47] reaped stale lock + swept assignee on #346 (pid=1441)
[14:36:49] tick — Ready=3 Building=1 QA=2 Review=2 Blocked=1 lanes: b_idle=0(#346 +36100:291) b_workers=1/5 q_idle=0(#323 +5270:321) q_workers=1/5 r_idle=0(#226 +58067:323) r_workers=2/5 waiting_on_you=0
[14:36:55] dispatch lane=qa issue=#346 pid=90643 claim=ToanMobile
[14:37:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 346: live qa lane (pid 90643) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 291: live build lane (pid 36100) holds it
kept card 321: live qa lane (pid 5270) holds it
[14:37:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:38:28] worker of #346 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=67s
[14:38:28] ⚠ worker of #346 (lane qa) ended 67s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":43554,"stop_reason":"end_turn","session_id":"7bb4f4db-3c3e-4235-b617-35b8df1efcba","total_cost_usd":0.4080747999999999,"usage":{"input_tokens":22,"cache_creation_input_tokens":73152
[14:38:31] reaped stale lock + swept assignee on #346 (pid=90643)
[14:38:37] tick — Ready=3 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#346 +36100:291) b_workers=1/5 q_idle=0(#346 +5270:321) q_workers=1/5 r_idle=0(#226 +58067:323) r_workers=2/5 waiting_on_you=0
[14:38:51] dispatch lane=build issue=#363 pid=29803 claim=ToanMobile
[14:39:21] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=646s
[14:39:24] reaped stale lock + swept assignee on #226 (pid=79898)
[14:39:27] tick — Ready=2 Building=1 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#363 +36100:291) b_workers=2/5 q_idle=0(#346 +5270:321) q_workers=1/5 r_idle=0(#226 +58067:323) r_workers=1/5 waiting_on_you=0
[14:39:41] dispatch lane=build issue=#181 pid=66796 claim=ToanMobile
[14:40:12] worker of #291 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4131s
[14:40:14] reaped stale lock + swept assignee on #291 (pid=36100)
[14:40:18] tick — Ready=1 Building=2 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#363 +66796:181) b_workers=2/5 q_idle=0(#346 +5270:321) q_workers=1/5 r_idle=0(#226 +58067:323) r_workers=1/5 waiting_on_you=0
[14:40:27] dispatch lane=qa issue=#291 pid=28900 claim=ToanMobile
[14:40:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:41:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:42:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:42:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:43:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:43:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:44:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:44:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:45:22] worker of #321 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=3143s
[14:45:26] reaped stale lock + swept assignee on #321 (pid=5270)
[14:45:35] tick — Ready=1 Building=2 QA=1 Review=2 Blocked=2 lanes: b_idle=0(#363 +66796:181) b_workers=2/5 q_idle=0(#291) q_workers=1/5 r_idle=0(#226 +58067:323) r_workers=1/5 waiting_on_you=0
[14:45:52] dispatch lane=review issue=#321 pid=26999 claim=ToanMobile
[14:45:53] qa workers: 5/5 running on the machine (5 here): holding
[14:45:53] qa workers: 5/5 running on the machine (5 here): holding
[14:46:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:47:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:47:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 181: live build lane (pid 66796) holds it
kept card 226: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 363: live build lane (pid 29803) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[14:48:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 321: live review lane (pid 26999) holds it
[14:48:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:49:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:49:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:50:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:50:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:51:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:51:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:52:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:52:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:53:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:53:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:54:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:54:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:55:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:56:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:56:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:57:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:57:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[14:58:05] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=731s
[14:58:08] reaped stale lock + swept assignee on #321 (pid=26999)
[14:58:08] worker of #323 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1494s
[14:58:12] reaped stale lock + swept assignee on #323 (pid=58067)
kept card 181: live build lane (pid 66796) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[14:58:22] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181) b_workers=2/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 291: live qa lane (pid 28900) holds it
kept card 363: live build lane (pid 29803) holds it
[14:58:37] dispatch lane=build issue=#377 pid=36165 claim=ToanMobile
[14:59:09] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[14:59:42] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:00:16] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:00:49] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:01:22] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:01:55] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:02:27] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:03:00] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:03:34] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:04:07] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:04:42] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:05:15] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:05:48] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:06:21] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:06:55] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=0(#291) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:07:25] worker of #291 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1592s
[15:07:28] reaped stale lock + swept assignee on #291 (pid=28900)
[15:07:32] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=1(#291) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[15:07:41] dispatch lane=review issue=#291 pid=12126 claim=ToanMobile
[15:08:14] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=1(#291) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:08:47] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=1(#291) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 363: live build lane (pid 29803) holds it
kept card 291: live review lane (pid 12126) holds it
kept card 377: live build lane (pid 36165) holds it
kept card 181: live build lane (pid 66796) holds it
[15:09:20] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=1(#291) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:09:53] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +66796:181 36165:377) b_workers=3/5 q_idle=1(#291) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:10:23] worker of #181 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1837s
[15:10:26] reaped stale lock + swept assignee on #181 (pid=66796)
[15:10:28] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#291) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:10:34] dispatch lane=qa issue=#181 pid=87364 claim=ToanMobile
[15:11:07] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#181) q_workers=1/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:11:43] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#181) q_workers=1/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:12:21] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#181) q_workers=1/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:12:58] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#181) q_workers=1/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:13:37] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291) r_workers=1/5 waiting_on_you=0
[15:13:38] worker of #181 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=180s
[15:13:55] dispatch lane=review issue=#181 pid=95993 claim=ToanMobile
[15:14:31] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:15:05] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:15:38] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:16:11] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:16:44] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:17:18] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:17:51] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:18:24] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:18:57] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 291: live review lane (pid 12126) holds it
kept card 377: live build lane (pid 36165) holds it
kept card 181: live review lane (pid 95993) holds it
kept card 363: live build lane (pid 29803) holds it
[15:19:30] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:20:03] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:20:36] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:21:09] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:21:42] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:22:15] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=2/5 waiting_on_you=0
[15:22:46] worker of #291 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=901s
[15:22:49] reaped stale lock + swept assignee on #291 (pid=12126)
[15:22:59] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:23:32] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:24:05] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:24:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:25:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:25:44] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:26:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:26:50] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:27:23] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:27:56] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:28:28] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
[15:29:01] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=0(#291 +95993:181) r_workers=1/5 waiting_on_you=0
kept card 181: live review lane (pid 95993) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 377: live build lane (pid 36165) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
[15:29:32] worker of #181 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=916s
[15:29:34] reaped stale lock + swept assignee on #181 (pid=95993)
[15:29:46] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:30:18] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:30:51] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:31:24] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:31:56] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:32:29] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:33:02] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:33:34] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:34:07] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:34:39] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:35:12] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:35:45] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:36:18] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:36:51] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:37:23] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:37:56] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:38:29] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:39:02] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept card 377: live build lane (pid 36165) holds it
kept card 363: live build lane (pid 29803) holds it
[15:39:34] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:40:07] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:40:39] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:41:12] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:41:44] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:42:17] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:42:50] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:43:23] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#181) q_workers=0/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[15:44:05] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[15:44:06] adopted live build worker on #363 (pid=29803) from the previous run
[15:44:06] adopted live build worker on #377 (pid=36165) from the previous run
[15:44:09] initial Ready count: 0
[15:44:18] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:44:51] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:45:24] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:45:57] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:46:29] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:47:08] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:47:14] dispatch lane=qa issue=#346 pid=20290 claim=ToanMobile
[15:47:47] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:48:20] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:48:53] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:49:26] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:49:29] hold #379 in Ready: its Fix covers #363 #377, still open — not dispatched
[15:50:02] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:50:36] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:51:10] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:51:45] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:52:19] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:52:54] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:53:29] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:54:04] tick — Ready=1 Building=2 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=0(#346) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[15:54:35] worker of #346 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=415s
[15:54:38] reaped stale lock + swept assignee on #346 (pid=20290)
[15:54:41] tick — Ready=1 Building=2 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
[15:54:52] dispatch lane=review issue=#346 pid=61620 claim=ToanMobile
kept card 377: live build lane (pid 36165) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[15:55:27] tick — Ready=1 Building=2 QA=0 Review=1 Blocked=2 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[15:56:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[15:56:40] worker of #346 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=74s
[15:56:40] ⚠ worker of #346 (lane review) ended 74s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":49604,"stop_reason":"end_turn","session_id":"7e0fb7e1-f2d5-4923-aa53-73fa32dc5bd7","total_cost_usd":0.5341242999999999,"usage":{"input_tokens":26,"cache_creation_input_tokens":91400
[15:56:43] reaped stale lock + swept assignee on #346 (pid=61620)
[15:56:46] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[15:57:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[15:57:54] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[15:58:28] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[15:59:02] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[15:59:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:00:14] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:00:53] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:01:30] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:02:07] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:02:43] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:03:23] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:04:02] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:04:41] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:05:20] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 363: live build lane (pid 29803) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept card 377: live build lane (pid 36165) holds it
[16:05:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:06:38] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:07:18] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:07:56] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:08:37] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:09:17] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:09:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:10:37] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:11:14] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:11:50] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:12:24] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:13:01] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:13:37] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:14:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:14:47] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:15:22] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept card 377: live build lane (pid 36165) holds it
kept card 363: live build lane (pid 29803) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
[16:15:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:16:31] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:17:06] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:17:40] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:18:15] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:18:49] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:19:24] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:19:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:20:36] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:21:12] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:21:47] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:22:23] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:22:59] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:23:35] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:24:13] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:24:52] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:25:30] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 36165) holds it
kept card 363: live build lane (pid 29803) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[16:26:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:26:45] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +36165:377) b_workers=2/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:27:17] worker of #377 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=5316s
[16:27:20] reaped stale lock + swept assignee on #377 (pid=36165)
[16:27:23] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#346) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:27:31] dispatch lane=qa issue=#377 pid=52289 claim=ToanMobile
[16:27:35] hold #379 in Ready: its Fix covers #363, still open — not dispatched
[16:28:08] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:28:44] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:29:20] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:29:55] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:30:31] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:31:05] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:31:39] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:32:13] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:32:45] worker of #377 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=291s
[16:32:47] reaped stale lock + swept assignee on #377 (pid=52289)
[16:32:51] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[16:33:00] dispatch lane=review issue=#377 pid=78548 claim=ToanMobile
[16:33:35] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[16:34:09] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[16:34:43] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[16:35:17] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[16:35:52] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 377: live review lane (pid 78548) holds it
kept card 363: live build lane (pid 29803) holds it
[16:36:26] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[16:36:58] worker of #377 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=230s
[16:37:00] reaped stale lock + swept assignee on #377 (pid=78548)
[16:37:04] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:37:24] dispatch lane=build issue=#377 pid=17566 claim=ToanMobile
[16:37:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:38:33] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:39:08] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:39:44] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:40:21] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:40:57] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:41:33] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:42:10] tick — Ready=2 Building=2 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:42:29] dispatch lane=build issue=#380 pid=30618 claim=ToanMobile
[16:43:03] tick — Ready=1 Building=3 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377 30618:380) b_workers=3/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:43:39] tick — Ready=1 Building=3 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377 30618:380) b_workers=3/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:44:15] tick — Ready=1 Building=3 QA=0 Review=0 Blocked=3 lanes: b_idle=0(#363 +17566:377 30618:380) b_workers=3/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:44:48] worker of #380 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=117s
[16:44:48] ⚠ worker of #380 (lane build) ended 117s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":51131,"stop_reason":"end_turn","session_id":"13477f67-51d2-47ea-8e76-99b422b829b5","total_cost_usd":0.5120657,"usage":{"input_tokens":32,"cache_creation_input_tokens":83382,"cache_r
[16:44:50] reaped stale lock + swept assignee on #380 (pid=30618)
[16:45:00] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:45:35] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:46:09] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept card 377: live build lane (pid 17566) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 363: live build lane (pid 29803) holds it
[16:46:42] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:47:16] tick — Ready=1 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:47:50] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:47:53] hold #379 in Ready: its Fix covers #377, still open — not dispatched
[16:48:24] worker of #363 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=7765s
[16:48:26] reaped stale lock + swept assignee on #363 (pid=29803)
[16:48:29] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:48:34] dispatch lane=qa issue=#363 pid=73589 claim=ToanMobile
[16:49:08] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:49:44] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:50:20] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:50:56] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:51:33] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:52:10] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:52:46] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:53:22] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:53:59] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:54:34] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:55:08] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=0(#363) q_workers=1/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:55:40] 💀 zombie qa worker on #363 (pid=73589) — card moved to 'Review'; killing
[16:55:46] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[16:55:56] dispatch lane=review issue=#363 pid=47348 claim=ToanMobile
[16:56:31] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept card 363: live review lane (pid 47348) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 377: live build lane (pid 17566) holds it
[16:57:06] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[16:57:41] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[16:58:15] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[16:58:49] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[16:59:23] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[16:59:58] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[17:00:32] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[17:00:43] preflight sequence/overlap for #379: open PRs touch the same files — build after them — not dispatched, card to Blocked
[17:01:30] ⏳ #379: label '⏳ chờ thẻ khác' (waits on other cards)
[17:01:30] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[17:02:10] ⏳ #379: label '⏳ chờ thẻ khác' removed
[17:02:15] ↩ unblocked #379: Blocked → Ready (cleared by #363)
[17:02:16] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#363 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#363) r_workers=1/5 waiting_on_you=0
[17:02:26] preflight #379: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[17:02:32] dispatch lane=build issue=#379 pid=87636 claim=ToanMobile
[17:03:03] 💀 zombie review worker on #363 (pid=47348) — card moved to 'Done'; killing
[17:03:17] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:03:51] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:04:25] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:05:00] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:05:39] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:06:14] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:06:49] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 379: live build lane (pid 87636) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
[17:07:22] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:07:55] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:08:28] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:09:01] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:09:33] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:10:08] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:10:42] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:11:16] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:11:51] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:12:30] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:13:07] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:13:43] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:14:22] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:14:57] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:15:31] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:16:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:16:40] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:17:14] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 379: live build lane (pid 87636) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
[17:17:47] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:18:21] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:18:55] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:19:29] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:20:03] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:20:37] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:21:11] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:21:45] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:22:20] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:22:55] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:23:29] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:24:03] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:24:37] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:25:12] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:25:45] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:26:17] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:26:18] worker of #379 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1425s
[17:26:23] dispatch lane=qa issue=#379 pid=71193 claim=ToanMobile
[17:26:56] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:27:29] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 17566) holds it
[17:28:03] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:28:38] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:29:12] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:29:46] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:30:20] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=0(#379) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:30:52] 💀 zombie qa worker on #379 (pid=71193) — card moved to 'Review'; killing
[17:30:59] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[17:31:11] dispatch lane=review issue=#379 pid=66135 claim=ToanMobile
[17:31:44] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:32:16] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:32:49] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:33:23] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:33:57] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:34:30] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:35:03] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:35:36] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:36:08] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:36:41] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#379 +17566:377) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=0(#379) r_workers=1/5 waiting_on_you=0
[17:37:12] worker of #377 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3573s
[17:37:16] reaped stale lock + swept assignee on #377 (pid=17566)
[17:37:19] ⚠ self-reload: origin/main has a newer super-board-run.sh but this runner keeps the old code — git merge --ff-only origin/main failed (uncommitted edits in the way?)
[17:37:29] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#379) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:37:35] dispatch lane=qa issue=#377 pid=97961 claim=ToanMobile
[17:38:05] worker of #379 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=365s
[17:38:10] reaped stale lock + swept assignee on #379 (pid=66135)
[17:38:13] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#379) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
kept card 377: live qa lane (pid 97961) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
[17:38:46] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#379) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:39:19] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=4 lanes: b_idle=1(#379) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:39:58] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=3 lanes: b_idle=1(#379) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:40:14] dispatch lane=build issue=#380 pid=15640 claim=ToanMobile
[17:40:47] tick — Ready=1 Building=1 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#380) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:41:02] dispatch lane=build issue=#385 pid=25331 claim=ToanMobile
[17:41:35] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#380) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:42:05] worker of #385 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=31s
[17:42:05] ⚠ worker of #385 (lane build) ended 31s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":14990,"stop_reason":"end_turn","session_id":"a6f10349-002d-4f1d-8efb-87c230d27707","total_cost_usd":0.37358460000000004,"usage":{"input_tokens":8,"cache_creation_input_tokens":83651
[17:42:08] reaped stale lock + swept assignee on #385 (pid=25331)
[17:42:16] reconciled closed #385 -> Done (was 'Building') — builder closed it, AC already met
[17:42:16] tick — Ready=0 Building=2 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#380) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:42:57] ⏳ #319: label '⏳ chờ thẻ khác' (waits on other cards)
[17:42:57] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#380) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:43:36] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#380) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#379) r_workers=0/5 waiting_on_you=0
[17:43:44] review lane issue=#321: PR #342 approved at head 1f191e604679289df2c1b74458b6d582104f5302 — merge-only, no fresh review
[17:43:44] dispatch lane=review issue=#321 pid=47321 claim=ToanMobile
[17:44:15] 💀 zombie build worker on #380 (pid=15640) — card moved to 'Done'; killing
[17:44:22] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=2 lanes: b_idle=1(#_) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:44:39] dispatch lane=build issue=#386 pid=31023 claim=ToanMobile
[17:45:17] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:45:55] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:46:32] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:47:09] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:47:44] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:48:19] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
kept card 321: live review lane (pid 47321) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept branch issue-226-runner-merge-train-reload: still checked out at /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-226-qa
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 377: live qa lane (pid 97961) holds it
[17:48:56] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:49:38] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:49:39] skip #346 in Review: its worker ended within 120s twice in 600s — not claimed again until that window passes
[17:50:15] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:50:58] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:51:36] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:52:13] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:52:49] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:53:25] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:54:00] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:54:35] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=0(#377) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:55:07] worker of #377 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1022s
[17:55:10] reaped stale lock + swept assignee on #377 (pid=97961)
[17:55:15] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[17:55:29] dispatch lane=review issue=#377 pid=34383 claim=ToanMobile
[17:56:02] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[17:56:35] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[17:57:06] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=788s
[17:57:08] reaped stale lock + swept assignee on #321 (pid=47321)
[17:57:11] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=1/5 waiting_on_you=0
[17:57:18] dispatch lane=review issue=#321 pid=12432 claim=ToanMobile
[17:57:51] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[17:58:24] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
kept card 321: live review lane (pid 12432) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-320-review: uncommitted edits outside the salvage list (1 path(s)): .claude/settings.json
kept card 386: live build lane (pid 31023) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: agent-kit worktree remove refused: ✖ worktree: /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-307-review: UNREACHABLE — 1 commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): d6a0450d Merge remote-tracking branch 'origin/main' into HEAD. Gỡ worktree xoá reflog đó và commit mất sau lần git gc. Giữ chún
[17:58:58] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[17:59:31] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[18:00:04] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[18:00:38] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321 +34383:377) r_workers=2/5 waiting_on_you=0
[18:01:10] worker of #377 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=335s
[18:01:12] reaped stale lock + swept assignee on #377 (pid=34383)
[18:01:17] tick — Ready=1 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:01:34] dispatch lane=build issue=#377 pid=46906 claim=ToanMobile
[18:02:08] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:02:44] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:03:20] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:03:58] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:04:37] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:05:13] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:05:49] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:06:24] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:06:59] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:07:33] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:08:09] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
kept card 386: live build lane (pid 31023) holds it
kept card 377: live build lane (pid 46906) holds it
[18:08:43] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
kept card 321: live review lane (pid 12432) holds it
[18:09:17] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:09:52] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:10:29] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:11:04] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:11:39] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:12:13] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:12:47] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:12:48] worker of #386 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1687s
[18:12:54] dispatch lane=qa issue=#386 pid=76971 claim=ToanMobile
[18:13:28] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:14:02] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:14:33] worker of #386 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=84s
[18:14:34] ⚠ worker of #386 (lane qa) ended 84s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"duration_api_ms":35957,"stop_reason":"end_turn","session_id":"b67b6245-e3f1-4c75-9fb3-6bd9c7c2cf77","total_cost_usd":0.42211170000000003,"usage":{"input_tokens":22,"cache_creation_input_tokens":7687
[18:14:36] reaped stale lock + swept assignee on #386 (pid=76971)
[18:14:40] tick — Ready=1 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:14:57] dispatch lane=build issue=#386 pid=72315 claim=ToanMobile
[18:15:31] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:16:06] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:16:41] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:17:16] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:17:51] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:18:27] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
kept card 386: live build lane (pid 72315) holds it
[18:19:02] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
kept card 321: live review lane (pid 12432) holds it
kept card 377: live build lane (pid 46906) holds it
[18:19:36] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:20:09] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:20:43] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[18:21:14] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1419s
[18:21:16] reaped stale lock + swept assignee on #321 (pid=12432)
[18:21:22] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:21:55] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:22:29] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:23:03] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:23:37] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:24:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:24:45] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:25:19] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:25:53] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:26:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:27:01] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:27:35] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:28:08] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:28:42] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 386: live build lane (pid 72315) holds it
[18:29:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[18:29:50] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:30:23] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:30:57] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:31:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:32:04] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:32:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:33:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:33:45] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:34:18] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:34:51] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:35:25] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:35:58] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:36:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:37:05] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:37:39] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:38:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:38:46] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[18:39:21] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 386: live build lane (pid 72315) holds it
[18:39:56] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:40:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:41:07] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:41:43] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:42:19] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:42:54] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:43:28] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:44:02] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:44:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:45:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:45:46] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:46:20] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:46:54] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:47:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:48:01] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:48:34] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:49:08] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
kept card 386: live build lane (pid 72315) holds it
[18:49:42] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:50:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:50:49] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:51:23] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:51:57] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:52:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:53:05] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:53:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:54:12] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:54:46] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:55:20] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:55:54] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:56:28] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:57:02] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:57:36] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:58:09] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:58:43] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[18:59:19] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
kept card 386: live build lane (pid 72315) holds it
[18:59:53] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:00:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:01:01] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:01:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:02:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:02:47] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:03:24] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:03:59] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:04:34] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:05:08] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:05:42] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:06:17] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:06:51] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:07:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:08:00] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:08:34] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:09:09] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:09:43] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:10:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
kept card 386: live build lane (pid 72315) holds it
[19:10:50] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:11:24] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:11:58] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:12:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:13:05] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:13:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:14:12] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:14:45] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:15:20] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:15:53] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:16:24] worker of #386 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3660s
[19:16:27] reaped stale lock + swept assignee on #386 (pid=72315)
[19:16:29] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:16:36] dispatch lane=qa issue=#386 pid=32248 claim=ToanMobile
[19:17:09] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:17:43] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:18:18] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:18:52] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:19:26] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:20:00] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
kept card 386: live qa lane (pid 32248) holds it
[19:20:34] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:21:09] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=2/5 q_idle=0(#386) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:21:40] worker of #386 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=281s
[19:21:43] reaped stale lock + swept assignee on #386 (pid=32248)
[19:21:49] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[19:22:04] dispatch lane=review issue=#386 pid=45055 claim=ToanMobile
[19:22:38] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:23:14] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:23:49] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:24:25] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:25:01] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:25:36] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:26:11] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:26:46] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:27:22] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:27:58] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:28:33] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:29:08] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:29:43] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:30:18] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:30:53] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
kept card 386: live review lane (pid 45055) holds it
kept card 377: live build lane (pid 46906) holds it
[19:31:27] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:32:02] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:32:37] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:33:11] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:33:46] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:34:20] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:34:55] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:35:29] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:36:03] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:36:38] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#386) r_workers=1/5 waiting_on_you=0
[19:37:09] worker of #386 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=876s
[19:37:12] reaped stale lock + swept assignee on #386 (pid=45055)
[19:37:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:37:49] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:38:22] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:38:56] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:39:29] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:40:03] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:40:36] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[19:41:10] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:41:43] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:42:17] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:42:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:43:25] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:43:59] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:44:33] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:45:06] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:45:40] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:46:13] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:46:47] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:47:20] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:47:54] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:48:27] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:49:01] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:49:35] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:50:08] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:50:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:51:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[19:51:49] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:52:22] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:52:56] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:53:30] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:54:03] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:54:37] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:55:10] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:55:44] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:56:17] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:56:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:57:24] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:57:59] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:58:34] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:59:08] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[19:59:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:00:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:00:50] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[20:01:25] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:01:59] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:02:33] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:03:06] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#386) r_workers=0/5 waiting_on_you=0
[20:03:22] dispatch lane=review issue=#346 pid=75751 claim=ToanMobile
[20:03:56] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:04:29] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:05:03] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:05:37] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:06:11] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:06:44] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:07:18] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:07:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:08:25] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:08:58] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:09:32] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:10:06] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:10:39] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:11:13] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
kept card 346: live review lane (pid 75751) holds it
[20:11:47] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:12:20] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:12:54] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:13:27] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:14:00] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:14:34] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:15:08] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:15:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:16:15] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:16:49] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:17:23] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:17:56] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:18:30] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:19:06] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:19:41] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:20:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:20:50] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:21:24] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
kept card 346: live review lane (pid 75751) holds it
kept card 377: live build lane (pid 46906) holds it
[20:21:58] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:22:32] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:23:09] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:23:47] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:24:25] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:25:01] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:25:36] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:26:12] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:26:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:27:26] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:28:02] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:28:36] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:29:11] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:29:45] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:30:19] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:30:53] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=0(#346) r_workers=1/5 waiting_on_you=0
[20:31:24] worker of #346 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1679s
[20:31:27] reaped stale lock + swept assignee on #346 (pid=75751)
[20:31:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[20:32:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:32:39] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:33:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:33:47] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:34:20] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:34:53] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:35:27] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:36:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:36:34] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:37:08] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:37:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:38:14] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:38:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:39:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:39:54] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:40:28] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:41:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:41:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[20:42:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:42:42] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:43:15] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:43:49] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:44:23] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:44:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:45:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:46:03] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:46:37] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:47:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:47:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:48:17] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:48:51] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:49:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:49:58] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:50:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:51:04] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:51:37] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[20:52:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:52:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:53:17] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:53:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:54:23] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:54:57] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:55:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:56:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:56:39] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:57:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:57:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:58:20] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:58:54] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[20:59:28] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:00:02] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:00:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:01:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:01:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[21:02:18] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:02:51] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:03:24] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:03:58] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:04:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:05:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:05:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:06:12] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:06:47] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:07:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:07:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:08:29] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:09:02] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:09:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:10:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:10:43] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:11:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:11:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:12:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[21:12:58] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:13:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:14:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:14:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:15:12] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:15:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:16:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:16:53] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:17:27] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:17:59] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:18:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:19:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:19:37] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:20:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:20:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:21:18] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:21:52] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:22:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[21:23:00] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:23:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:24:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:24:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:25:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:25:43] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:26:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:26:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:27:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:27:53] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:28:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:29:00] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:29:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:30:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:30:37] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:31:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:31:43] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:32:15] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live build lane (pid 46906) holds it
[21:32:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=1 lanes: b_idle=0(#386 +46906:377) b_workers=1/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:33:18] worker of #377 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=12702s
[21:33:22] reaped stale lock + swept assignee on #377 (pid=46906)
[21:33:25] ⚠ self-reload: origin/main has a newer super-board-run.sh but this runner keeps the old code — git merge --ff-only origin/main failed (uncommitted edits in the way?)
[21:33:28] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#386) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:33:34] dispatch lane=qa issue=#377 pid=86010 claim=ToanMobile
[21:34:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:34:40] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:35:14] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:35:47] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:36:20] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:36:53] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:37:27] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:38:00] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:38:34] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:39:07] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:39:39] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:40:12] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:40:45] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:41:17] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:41:50] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:42:23] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
kept card 377: live qa lane (pid 86010) holds it
[21:42:56] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:43:30] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:44:02] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:44:35] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=0(#377) q_workers=1/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:45:05] worker of #377 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=673s
[21:45:08] reaped stale lock + swept assignee on #377 (pid=86010)
[21:45:15] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#346) r_workers=0/5 waiting_on_you=0
[21:45:24] dispatch lane=review issue=#377 pid=26678 claim=ToanMobile
[21:45:56] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:46:29] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:47:02] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:47:36] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:48:10] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:48:44] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:49:17] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:49:50] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:50:24] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:50:57] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:51:31] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:52:05] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[21:52:36] worker of #377 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=416s
[21:52:38] reaped stale lock + swept assignee on #377 (pid=26678)
[21:52:49] ⏳ #319: label '⏳ chờ thẻ khác' removed
[21:52:54] ↩ unblocked #319: Blocked → Ready (cleared by #377)
[21:52:55] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#386) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:53:11] dispatch lane=build issue=#319 pid=24288 claim=ToanMobile
kept card 319: live build lane (pid 24288) holds it
[21:53:45] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:54:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:54:54] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:55:27] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:56:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:56:34] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:57:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:57:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:58:14] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:58:48] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:59:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[21:59:55] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:00:28] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:01:02] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:01:35] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:02:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:02:42] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:03:15] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:03:49] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:04:23] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:04:57] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:05:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:06:03] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:06:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:07:08] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:08:00] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:08:47] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:09:33] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:10:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:11:14] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:11:59] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:12:49] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=0(#377) r_workers=1/5 waiting_on_you=0
[22:13:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:14:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:15:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:16:03] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:16:51] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:17:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:18:40] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:19:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:19:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:20:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:21:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:22:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:23:02] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:23:35] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:24:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:24:42] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:25:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:25:49] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:26:24] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:26:58] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:27:34] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:28:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:28:45] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:29:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:29:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:30:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:31:13] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:31:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:32:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:33:00] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:33:37] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:34:15] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:34:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:35:27] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:36:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:36:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:37:14] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:37:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:38:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:39:00] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:39:36] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:40:11] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:40:47] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:41:21] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:41:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:42:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:43:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:43:39] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:44:18] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:44:55] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:45:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:46:10] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:46:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:47:22] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:47:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:48:30] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:49:04] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:49:39] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:50:15] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:50:51] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:51:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:52:01] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:52:34] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:53:12] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:53:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:54:26] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[22:55:03] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:55:40] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:56:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:56:52] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:57:28] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:58:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:58:41] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:59:17] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[22:59:53] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:00:29] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:01:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:01:42] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:02:20] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:02:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:03:33] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:04:09] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:04:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[23:05:20] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:05:56] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:06:31] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:07:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:07:43] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:08:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:08:54] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:09:29] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:10:04] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:10:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:11:12] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:11:46] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:12:19] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:12:52] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:13:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:13:59] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:14:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:15:05] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
kept card 319: live build lane (pid 24288) holds it
[23:15:38] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:16:11] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:16:44] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#319) b_workers=1/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:17:14] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=5037s
[23:17:17] reaped stale lock + swept assignee on #319 (pid=24288)
[23:17:20] ⚠ self-reload: cannot create worktree .claude/worktrees/self-reload-50323-1792858640: trees/dropped-card-sweep, /Volumes/Data/Toan/agent-workbench/.claude/worktrees/push-agent-workload — chỉ gộp và gỡ worktree do CHÍNH phiên này tạo mà đã xong (`agent-kit worktree finish <path>`); worktree của phiên khác, kể cả đang sạch, thì để yên và chờ nó xong
[23:17:23] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#319) b_workers=0/5 q_idle=1(#377) q_workers=0/5 r_idle=1(#377) r_workers=0/5 waiting_on_you=0
[23:17:23] ✅ all active-pipeline columns empty and all lanes idle — exiting cleanly
[23:17:23] super-board run finished. manifest: docs/super-board/runs/2026-10-24-agent-workbench.md
