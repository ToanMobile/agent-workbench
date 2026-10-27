[00:01:48] ▶ explicit start: cleared the stop marker (STOPPED_AT=2026-10-22T15:18:06Z BY=alex via super-board-stop.sh PID=59151 )
[00:01:48] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[00:01:53] initial Ready count: 10
[00:02:01] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept card 256: a PR of it merged under 900s ago (Reviewer's post-merge steps)
[00:02:43] tick — Ready=10 Building=2 QA=2 Review=3 Blocked=9 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[00:02:43] ⚠ block-rate alert: 9/10 (90%)
[00:02:52] dispatch lane=review issue=#223 pid=3084 claim=ToanMobile
[00:03:02] dispatch lane=qa issue=#221 pid=18213 claim=ToanMobile
[00:03:21] dispatch lane=build issue=#253 pid=43261 claim=ToanMobile
[00:04:02] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:04:02] qa workers 1/3: load 25.46240234375 >= 24: holding
[00:05:18] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[00:05:19] adopted live qa worker on #221 (pid=18213) from the previous run
[00:05:19] adopted live review worker on #223 (pid=3084) from the previous run
[00:05:19] adopted live build worker on #253 (pid=43261) from the previous run
[00:05:28] ℹ stranded #251: keeping existing worktree .claude/worktrees/issue-251-build (branch issue-251-qa-merge-gate-same-suites) for Builder to resume
[00:05:39] ↩ stranded #251: Building → Ready (branch none)
[00:05:51] ↩ stranded #252: Building → Ready (branch none)
[00:05:54] initial Ready count: 11
[00:06:04] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:06:04] ⚠ block-rate alert: 9/11 (81%)
[00:06:04] review workers 1/3: load 28.87939453125 >= 24: holding
[00:06:04] qa workers 1/3: load 28.87939453125 >= 24: holding
[00:06:05] qa workers 1/3: load 28.87939453125 >= 24: holding
[00:06:05] build workers 1/10: load 28.87939453125 >= 24: holding
[00:06:40] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:06:40] review workers 1/3: load 33.67041015625 >= 24: holding
[00:06:40] qa workers 1/3: load 33.67041015625 >= 24: holding
[00:06:40] qa workers 1/3: load 33.67041015625 >= 24: holding
[00:06:40] build workers 1/10: load 33.67041015625 >= 24: holding
[00:07:15] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:07:15] review workers 1/3: load 54.427734375 >= 24: holding
[00:07:15] qa workers 1/3: load 54.427734375 >= 24: holding
[00:07:16] qa workers 1/3: load 54.427734375 >= 24: holding
[00:07:16] build workers 1/10: load 54.427734375 >= 24: holding
[00:07:51] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:07:51] review workers 1/3: load 74.26611328125 >= 24: holding
[00:07:51] qa workers 1/3: load 74.26611328125 >= 24: holding
[00:07:51] qa workers 1/3: load 74.26611328125 >= 24: holding
[00:07:51] build workers 1/10: load 74.26611328125 >= 24: holding
[00:08:26] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:08:26] review workers 1/3: load 67.51025390625 >= 24: holding
[00:08:26] qa workers 1/3: load 67.51025390625 >= 24: holding
[00:08:26] qa workers 1/3: load 67.51025390625 >= 24: holding
[00:08:26] build workers 1/10: load 67.51025390625 >= 24: holding
[00:09:01] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:09:01] review workers 1/3: load 46.8330078125 >= 24: holding
[00:09:01] qa workers 1/3: load 46.8330078125 >= 24: holding
[00:09:01] qa workers 1/3: load 46.8330078125 >= 24: holding
[00:09:01] build workers 1/10: load 46.8330078125 >= 24: holding
[00:10:34] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[00:10:35] adopted live qa worker on #221 (pid=18213) from the previous run
[00:10:35] adopted live review worker on #223 (pid=3084) from the previous run
[00:10:35] adopted live build worker on #253 (pid=43261) from the previous run
[00:12:44] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[00:12:45] adopted live qa worker on #221 (pid=18213) from the previous run
[00:12:46] adopted live review worker on #223 (pid=3084) from the previous run
[00:12:46] adopted live build worker on #253 (pid=43261) from the previous run
[00:12:53] initial Ready count: 11
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 221: live qa lane (pid 18213) holds it
kept card 253: live build lane (pid 43261) holds it
[00:13:02] tick — Ready=11 Building=1 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253) b_workers=1/10 q_idle=0(#221) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:13:02] ⚠ block-rate alert: 9/11 (81%)
[00:13:08] dispatch lane=review issue=#202 pid=85585 claim=ToanMobile
kept card 256: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 202: live review lane (pid 85585) holds it
[00:13:13] dispatch lane=qa issue=#227 pid=88568 claim=ToanMobile
[00:13:13] build workers 1/10, load 14.26806640625 < 24: starting #2
[00:13:26] dispatch lane=build issue=#251 pid=98420 claim=ToanMobile
[00:14:00] tick — Ready=10 Building=2 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251) b_workers=2/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202) r_workers=2/3 waiting_on_you=0
[00:14:07] dispatch lane=review issue=#229 pid=74772 claim=ToanMobile
[00:14:07] build workers 2/10, load 18.015625 < 24: starting #3
[00:14:16] dispatch lane=build issue=#252 pid=85265 claim=ToanMobile
[00:14:53] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:14:53] review workers 3/3: at the cap, not starting
[00:14:53] qa workers 2/3: load 36.69970703125 >= 24: holding
[00:14:53] qa workers 2/3: load 36.69970703125 >= 24: holding
[00:14:53] build workers 3/10: load 36.69970703125 >= 24: holding
[00:15:31] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:15:31] review workers 3/3: at the cap, not starting
[00:15:31] qa workers 2/3: load 54.8271484375 >= 24: holding
[00:15:32] qa workers 2/3: load 54.8271484375 >= 24: holding
[00:15:32] build workers 3/10: load 54.8271484375 >= 24: holding
[00:16:08] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:16:08] review workers 3/3: at the cap, not starting
[00:16:08] qa workers 2/3: load 65.22802734375 >= 24: holding
[00:16:08] qa workers 2/3: load 65.22802734375 >= 24: holding
[00:16:09] build workers 3/10: load 65.22802734375 >= 24: holding
[00:16:45] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:16:45] review workers 3/3: at the cap, not starting
[00:16:45] qa workers 2/3: load 54.46240234375 >= 24: holding
[00:16:45] qa workers 2/3: load 54.46240234375 >= 24: holding
[00:16:45] build workers 3/10: load 54.46240234375 >= 24: holding
[00:17:21] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:17:22] review workers 3/3: at the cap, not starting
[00:17:22] qa workers 2/3: load 41.8642578125 >= 24: holding
[00:17:22] qa workers 2/3: load 41.8642578125 >= 24: holding
[00:17:22] build workers 3/10: load 41.8642578125 >= 24: holding
[00:17:58] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:17:58] review workers 3/3: at the cap, not starting
[00:17:58] qa workers 2/3: load 39.50927734375 >= 24: holding
[00:17:58] qa workers 2/3: load 39.50927734375 >= 24: holding
[00:17:58] build workers 3/10: load 39.50927734375 >= 24: holding
[00:18:33] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:18:33] review workers 3/3: at the cap, not starting
[00:18:33] qa workers 2/3: load 32.4580078125 >= 24: holding
[00:18:33] qa workers 2/3: load 31.7001953125 >= 24: holding
[00:18:33] build workers 3/10: load 31.7001953125 >= 24: holding
[00:19:08] tick — Ready=9 Building=3 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252) b_workers=3/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:19:08] review workers 3/3: at the cap, not starting
[00:19:08] build workers 3/10, load 22.048828125 < 24: starting #4
[00:19:16] dispatch lane=build issue=#254 pid=92769 claim=ToanMobile
[00:19:51] tick — Ready=8 Building=4 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254) b_workers=4/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:19:51] review workers 3/3: at the cap, not starting
[00:19:52] qa workers 2/3: load 27.689453125 >= 24: holding
[00:19:52] qa workers 2/3: load 27.689453125 >= 24: holding
[00:19:52] build workers 4/10: load 27.689453125 >= 24: holding
[00:20:28] tick — Ready=8 Building=4 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254) b_workers=4/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:20:28] review workers 3/3: at the cap, not starting
[00:20:28] qa workers 2/3: load 27.60107421875 >= 24: holding
[00:20:28] qa workers 2/3: load 27.60107421875 >= 24: holding
[00:20:29] build workers 4/10: load 27.60107421875 >= 24: holding
[00:21:05] tick — Ready=8 Building=4 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254) b_workers=4/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:21:05] review workers 3/3: at the cap, not starting
[00:21:06] build workers 4/10, load 20.67529296875 < 24: starting #5
[00:21:15] dispatch lane=build issue=#255 pid=31031 claim=ToanMobile
[00:21:49] tick — Ready=7 Building=5 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255) b_workers=5/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:21:49] review workers 3/3: at the cap, not starting
[00:21:50] build workers 5/10, load 21.36669921875 < 24: starting #6
[00:21:50] reconciled closed #256 -> Done (was 'Ready') — dispatching 0 workers for it
[00:22:07] dispatch lane=build issue=#248 pid=63273 claim=ToanMobile
[00:22:49] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:22:49] review workers 3/3: at the cap, not starting
[00:22:49] qa workers 2/3: load 25.04736328125 >= 24: holding
[00:22:49] qa workers 2/3: load 25.04736328125 >= 24: holding
[00:22:50] build workers 6/10: load 25.04736328125 >= 24: holding
[00:23:26] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:23:26] review workers 3/3: at the cap, not starting
[00:23:26] qa workers 2/3: load 24.576171875 >= 24: holding
[00:23:26] qa workers 2/3: load 24.576171875 >= 24: holding
[00:23:26] build workers 6/10: load 24.576171875 >= 24: holding
kept card 255: live build lane (pid 31031) holds it
kept card 251: live build lane (pid 98420) holds it
kept card 227: live qa lane (pid 88568) holds it
kept card 252: live build lane (pid 85265) holds it
kept card 248: live build lane (pid 63273) holds it
kept card 254: live build lane (pid 92769) holds it
kept card 221: live qa lane (pid 18213) holds it
[00:24:03] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +85585:202 74772:229) r_workers=3/3 waiting_on_you=0
[00:24:03] review workers 3/3: at the cap, not starting
[00:24:03] qa workers 2/3: load 24.720703125 >= 24: holding
[00:24:03] qa workers 2/3: load 24.720703125 >= 24: holding
[00:24:03] build workers 6/10: load 24.720703125 >= 24: holding
[00:24:36] reaped stale lock + swept assignee on #202 (pid=85585)
[00:24:43] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:24:51] dispatch lane=review issue=#202 pid=28048 claim=ToanMobile
[00:24:51] qa workers 2/3: load 26.9775390625 >= 24: holding
[00:24:51] qa workers 2/3: load 26.9775390625 >= 24: holding
[00:24:51] build workers 6/10: load 26.9775390625 >= 24: holding
[00:25:30] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229 28048:202) r_workers=3/3 waiting_on_you=0
[00:25:30] review workers 3/3: at the cap, not starting
[00:25:30] qa workers 2/3: load 51.41845703125 >= 24: holding
[00:25:30] qa workers 2/3: load 51.41845703125 >= 24: holding
[00:25:30] build workers 6/10: load 51.41845703125 >= 24: holding
[00:26:06] tick — Ready=5 Building=6 QA=2 Review=3 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229 28048:202) r_workers=3/3 waiting_on_you=0
[00:26:06] review workers 3/3: at the cap, not starting
[00:26:06] qa workers 2/3: load 59.9072265625 >= 24: holding
[00:26:06] qa workers 2/3: load 59.9072265625 >= 24: holding
[00:26:06] build workers 6/10: load 59.9072265625 >= 24: holding
[00:26:37] ⚠ worker of #202 (lane review) ended 102s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: Việc tiếp theo thuộc builder: gộp main, chạy lại test và gate, rồi push. Chỉ sau đó mới có thể nói #202 đã fix.
[00:26:40] reaped stale lock + swept assignee on #202 (pid=28048)
[00:26:45] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:26:45] review workers 2/3: load 44.89453125 >= 24: holding
[00:26:45] qa workers 2/3: load 44.89453125 >= 24: holding
[00:26:45] qa workers 2/3: load 44.89453125 >= 24: holding
[00:26:45] build workers 6/10: load 44.89453125 >= 24: holding
[00:27:21] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:27:21] review workers 2/3: load 36.34326171875 >= 24: holding
[00:27:21] qa workers 2/3: load 36.34326171875 >= 24: holding
[00:27:21] qa workers 2/3: load 36.34326171875 >= 24: holding
[00:27:21] build workers 6/10: load 36.34326171875 >= 24: holding
[00:27:58] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:27:58] review workers 2/3: load 42.88720703125 >= 24: holding
[00:27:58] qa workers 2/3: load 42.88720703125 >= 24: holding
[00:27:59] qa workers 2/3: load 42.88720703125 >= 24: holding
[00:27:59] build workers 6/10: load 42.88720703125 >= 24: holding
[00:28:34] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:28:34] review workers 2/3: load 36.8173828125 >= 24: holding
[00:28:34] qa workers 2/3: load 36.8173828125 >= 24: holding
[00:28:34] qa workers 2/3: load 36.8173828125 >= 24: holding
[00:28:34] build workers 6/10: load 36.8173828125 >= 24: holding
[00:29:12] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:29:12] review workers 2/3: load 50.49609375 >= 24: holding
[00:29:13] qa workers 2/3: load 50.49609375 >= 24: holding
[00:29:13] qa workers 2/3: load 50.49609375 >= 24: holding
[00:29:13] build workers 6/10: load 50.49609375 >= 24: holding
[00:29:50] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#253 +98420:251 85265:252 92769:254 31031:255 63273:248) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:29:50] review workers 2/3: load 67.5859375 >= 24: holding
[00:29:50] qa workers 2/3: load 67.5859375 >= 24: holding
[00:29:50] qa workers 2/3: load 67.5859375 >= 24: holding
[00:29:50] build workers 6/10: load 67.5859375 >= 24: holding
[00:30:19] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[00:30:24] adopted live qa worker on #221 (pid=18213) from the previous run
[00:30:24] adopted live review worker on #223 (pid=3084) from the previous run
[00:30:24] adopted live qa worker on #227 (pid=88568) from the previous run
[00:30:24] adopted live review worker on #229 (pid=74772) from the previous run
[00:30:24] adopted live build worker on #248 (pid=63273) from the previous run
[00:30:24] adopted live build worker on #251 (pid=98420) from the previous run
[00:30:24] adopted live build worker on #252 (pid=85265) from the previous run
[00:30:24] adopted live build worker on #253 (pid=43261) from the previous run
[00:30:24] adopted live build worker on #254 (pid=92769) from the previous run
[00:30:24] adopted live build worker on #255 (pid=31031) from the previous run
[00:30:32] initial Ready count: 6
kept card 252: live build lane (pid 85265) holds it
kept card 227: live qa lane (pid 88568) holds it
kept card 253: live build lane (pid 43261) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[00:30:47] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:30:47] ⚠ block-rate alert: 9/6 (150%)
[00:30:47] review workers 2/3: load 78.62646484375 >= 24: holding
[00:30:47] qa workers 2/3: load 78.62646484375 >= 24: holding
[00:30:47] qa workers 2/3: load 78.62646484375 >= 24: holding
[00:30:47] build workers 6/10: load 78.62646484375 >= 24: holding
kept card 229: live review lane (pid 74772) holds it
[00:31:24] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:31:24] review workers 2/3: load 80.025390625 >= 24: holding
[00:31:24] qa workers 2/3: load 80.025390625 >= 24: holding
[00:31:24] qa workers 2/3: load 80.025390625 >= 24: holding
[00:31:24] build workers 6/10: load 80.025390625 >= 24: holding
[00:32:00] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:32:00] review workers 2/3: load 96.00927734375 >= 24: holding
[00:32:01] qa workers 2/3: load 96.00927734375 >= 24: holding
[00:32:01] qa workers 2/3: load 96.00927734375 >= 24: holding
[00:32:01] build workers 6/10: load 96.00927734375 >= 24: holding
[00:32:38] tick — Ready=6 Building=6 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#221 +88568:227) q_workers=2/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:32:38] review workers 2/3: load 80.04931640625 >= 24: holding
[00:32:38] qa workers 2/3: load 80.04931640625 >= 24: holding
[00:32:38] qa workers 2/3: load 80.04931640625 >= 24: holding
[00:32:38] build workers 6/10: load 80.04931640625 >= 24: holding
[00:33:15] 💀 zombie qa worker on #221 (pid=18213) — card moved to 'Review'; killing
[00:33:20] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:33:20] review workers 2/3: load 70.208984375 >= 24: holding
[00:33:20] qa workers 1/3: load 70.208984375 >= 24: holding
[00:33:20] qa workers 1/3: load 70.208984375 >= 24: holding
[00:33:20] build workers 6/10: load 70.208984375 >= 24: holding
[00:33:56] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:33:56] review workers 2/3: load 58.2626953125 >= 24: holding
[00:33:56] qa workers 1/3: load 58.2626953125 >= 24: holding
[00:33:56] qa workers 1/3: load 58.2626953125 >= 24: holding
[00:33:56] build workers 6/10: load 58.2626953125 >= 24: holding
[00:34:32] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:34:32] review workers 2/3: load 40.12353515625 >= 24: holding
[00:34:32] qa workers 1/3: load 40.12353515625 >= 24: holding
[00:34:32] qa workers 1/3: load 40.12353515625 >= 24: holding
[00:34:32] build workers 6/10: load 40.12353515625 >= 24: holding
[00:35:06] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:35:06] review workers 2/3: load 26.55419921875 >= 24: holding
[00:35:06] qa workers 1/3: load 26.55419921875 >= 24: holding
[00:35:06] qa workers 1/3: load 26.55419921875 >= 24: holding
[00:35:06] build workers 6/10: load 26.55419921875 >= 24: holding
[00:35:46] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:35:46] review workers 2/3: load 49.11376953125 >= 24: holding
[00:35:46] qa workers 1/3: load 49.11376953125 >= 24: holding
[00:35:46] qa workers 1/3: load 49.11376953125 >= 24: holding
[00:35:46] build workers 6/10: load 49.11376953125 >= 24: holding
[00:36:25] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:36:25] review workers 2/3: load 67.90673828125 >= 24: holding
[00:36:26] qa workers 1/3: load 67.90673828125 >= 24: holding
[00:36:26] qa workers 1/3: load 67.90673828125 >= 24: holding
[00:36:26] build workers 6/10: load 67.90673828125 >= 24: holding
[00:37:05] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:37:05] review workers 2/3: load 78.171875 >= 24: holding
[00:37:05] qa workers 1/3: load 78.171875 >= 24: holding
[00:37:05] qa workers 1/3: load 78.171875 >= 24: holding
[00:37:06] build workers 6/10: load 78.171875 >= 24: holding
[00:37:41] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:37:41] review workers 2/3: load 65.4287109375 >= 24: holding
[00:37:41] qa workers 1/3: load 65.4287109375 >= 24: holding
[00:37:41] qa workers 1/3: load 65.4287109375 >= 24: holding
[00:37:41] build workers 6/10: load 65.4287109375 >= 24: holding
[00:38:19] tick — Ready=6 Building=6 QA=1 Review=3 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223 +74772:229) r_workers=2/3 waiting_on_you=0
[00:38:19] review workers 2/3: load 53.9765625 >= 24: holding
[00:38:19] qa workers 1/3: load 53.9765625 >= 24: holding
[00:38:19] qa workers 1/3: load 53.9765625 >= 24: holding
[00:38:19] build workers 6/10: load 53.9765625 >= 24: holding
[00:38:56] 💀 zombie review worker on #229 (pid=74772) — card moved to 'Ready'; killing
[00:39:00] tick — Ready=7 Building=6 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:39:00] review workers 1/3: load 44.6591796875 >= 24: holding
[00:39:00] qa workers 1/3: load 44.6591796875 >= 24: holding
[00:39:00] qa workers 1/3: load 44.6591796875 >= 24: holding
[00:39:00] build workers 6/10: load 44.6591796875 >= 24: holding
[00:39:37] tick — Ready=7 Building=6 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:39:37] review workers 1/3: load 46.14208984375 >= 24: holding
[00:39:37] qa workers 1/3: load 46.14208984375 >= 24: holding
[00:39:37] qa workers 1/3: load 46.14208984375 >= 24: holding
[00:39:37] build workers 6/10: load 46.14208984375 >= 24: holding
[00:40:12] tick — Ready=7 Building=6 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:40:12] review workers 1/3: load 30.8095703125 >= 24: holding
[00:40:12] qa workers 1/3: load 30.8095703125 >= 24: holding
[00:40:12] qa workers 1/3: load 30.8095703125 >= 24: holding
[00:40:12] build workers 6/10: load 30.8095703125 >= 24: holding
kept card 255: live build lane (pid 31031) holds it
[00:40:47] tick — Ready=7 Building=6 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:40:47] review workers 1/3: load 29.9716796875 >= 24: holding
[00:40:47] qa workers 1/3: load 29.9716796875 >= 24: holding
[00:40:47] qa workers 1/3: load 29.9716796875 >= 24: holding
[00:40:47] build workers 6/10: load 29.9716796875 >= 24: holding
kept card 253: live build lane (pid 43261) holds it
kept card 251: live build lane (pid 98420) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 252: live build lane (pid 85265) holds it
kept card 248: live build lane (pid 63273) holds it
[00:41:22] tick — Ready=7 Building=6 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255) b_workers=6/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[00:41:28] dispatch lane=review issue=#221 pid=48826 claim=ToanMobile
[00:41:28] build workers 6/10, load 21.3466796875 < 24: starting #7
[00:41:41] dispatch lane=build issue=#249 pid=76741 claim=ToanMobile
[00:42:15] 💀 zombie review worker on #223 (pid=3084) — card moved to 'Ready'; killing
[00:42:19] tick — Ready=7 Building=7 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249) b_workers=7/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:42:19] build workers 7/10, load 19.705078125 < 24: starting #8
[00:42:28] dispatch lane=build issue=#250 pid=16953 claim=ToanMobile
[00:43:04] tick — Ready=6 Building=8 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:43:05] build workers 8/10, load 22.49755859375 < 24: starting #9
[00:43:13] dispatch lane=build issue=#240 pid=83742 claim=ToanMobile
[00:43:51] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:43:51] review workers 1/3: load 27.84765625 >= 24: holding
[00:43:51] qa workers 1/3: load 27.84765625 >= 24: holding
[00:43:51] qa workers 1/3: load 27.84765625 >= 24: holding
[00:43:51] build workers 9/10: load 27.84765625 >= 24: holding
[00:44:29] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:44:29] review workers 1/3: load 33.23291015625 >= 24: holding
[00:44:29] qa workers 1/3: load 33.23291015625 >= 24: holding
[00:44:29] qa workers 1/3: load 33.23291015625 >= 24: holding
[00:44:29] build workers 9/10: load 33.23291015625 >= 24: holding
[00:45:07] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:45:07] review workers 1/3: load 40.8544921875 >= 24: holding
[00:45:08] qa workers 1/3: load 40.8544921875 >= 24: holding
[00:45:08] qa workers 1/3: load 40.8544921875 >= 24: holding
[00:45:08] build workers 9/10: load 40.8544921875 >= 24: holding
[00:45:44] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:45:44] review workers 1/3: load 43.98583984375 >= 24: holding
[00:45:44] qa workers 1/3: load 43.98583984375 >= 24: holding
[00:45:44] qa workers 1/3: load 43.98583984375 >= 24: holding
[00:45:44] build workers 9/10: load 43.98583984375 >= 24: holding
[00:46:25] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:46:25] review workers 1/3: load 60.89208984375 >= 24: holding
[00:46:25] qa workers 1/3: load 60.89208984375 >= 24: holding
[00:46:25] qa workers 1/3: load 60.89208984375 >= 24: holding
[00:46:26] build workers 9/10: load 60.89208984375 >= 24: holding
[00:47:10] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:47:10] review workers 1/3: load 99.61474609375 >= 24: holding
[00:47:10] qa workers 1/3: load 99.61474609375 >= 24: holding
[00:47:11] qa workers 1/3: load 99.61474609375 >= 24: holding
[00:47:11] build workers 9/10: load 99.61474609375 >= 24: holding
[00:47:48] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:47:48] review workers 1/3: load 111.17578125 >= 24: holding
[00:47:48] qa workers 1/3: load 111.17578125 >= 24: holding
[00:47:49] qa workers 1/3: load 111.17578125 >= 24: holding
[00:47:49] build workers 9/10: load 111.17578125 >= 24: holding
[00:48:25] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:48:25] review workers 1/3: load 103.4345703125 >= 24: holding
[00:48:25] qa workers 1/3: load 103.4345703125 >= 24: holding
[00:48:25] qa workers 1/3: load 103.4345703125 >= 24: holding
[00:48:25] build workers 9/10: load 103.4345703125 >= 24: holding
[00:49:01] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:49:02] review workers 1/3: load 98.5859375 >= 24: holding
[00:49:02] qa workers 1/3: load 98.5859375 >= 24: holding
[00:49:02] qa workers 1/3: load 98.5859375 >= 24: holding
[00:49:02] build workers 9/10: load 98.5859375 >= 24: holding
[00:49:38] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:49:38] review workers 1/3: load 87.35009765625 >= 24: holding
[00:49:38] qa workers 1/3: load 87.35009765625 >= 24: holding
[00:49:38] qa workers 1/3: load 87.35009765625 >= 24: holding
[00:49:38] build workers 9/10: load 87.35009765625 >= 24: holding
[00:50:17] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:50:17] review workers 1/3: load 75.10791015625 >= 24: holding
[00:50:17] qa workers 1/3: load 75.10791015625 >= 24: holding
[00:50:17] qa workers 1/3: load 75.10791015625 >= 24: holding
[00:50:17] build workers 9/10: load 75.10791015625 >= 24: holding
[00:50:53] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:50:53] review workers 1/3: load 55.14990234375 >= 24: holding
[00:50:53] qa workers 1/3: load 55.14990234375 >= 24: holding
[00:50:53] qa workers 1/3: load 55.14990234375 >= 24: holding
[00:50:53] build workers 9/10: load 55.14990234375 >= 24: holding
kept card 252: live build lane (pid 85265) holds it
kept card 250: live build lane (pid 16953) holds it
kept card 221: live review lane (pid 48826) holds it
kept card 251: live build lane (pid 98420) holds it
kept card 254: live build lane (pid 92769) holds it
[00:51:30] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:51:30] review workers 1/3: load 48.8349609375 >= 24: holding
[00:51:30] qa workers 1/3: load 48.8349609375 >= 24: holding
[00:51:30] qa workers 1/3: load 48.8349609375 >= 24: holding
[00:51:30] build workers 9/10: load 48.8349609375 >= 24: holding
[00:52:08] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:52:08] review workers 1/3: load 62.51123046875 >= 24: holding
[00:52:08] qa workers 1/3: load 62.51123046875 >= 24: holding
[00:52:08] qa workers 1/3: load 62.51123046875 >= 24: holding
[00:52:08] build workers 9/10: load 62.51123046875 >= 24: holding
[00:52:44] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:52:44] review workers 1/3: load 56.7109375 >= 24: holding
[00:52:44] qa workers 1/3: load 56.7109375 >= 24: holding
[00:52:44] qa workers 1/3: load 56.7109375 >= 24: holding
[00:52:44] build workers 9/10: load 56.7109375 >= 24: holding
[00:53:19] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:53:19] review workers 1/3: load 41.41064453125 >= 24: holding
[00:53:20] qa workers 1/3: load 41.41064453125 >= 24: holding
[00:53:20] qa workers 1/3: load 41.41064453125 >= 24: holding
[00:53:20] build workers 9/10: load 41.41064453125 >= 24: holding
[00:53:55] tick — Ready=5 Building=9 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:53:55] review workers 1/3: load 31.3857421875 >= 24: holding
[00:53:55] qa workers 1/3: load 31.3857421875 >= 24: holding
[00:53:55] qa workers 1/3: load 31.3857421875 >= 24: holding
[00:53:55] build workers 9/10: load 31.3857421875 >= 24: holding
[00:54:30] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 43261:253 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=9/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:54:30] review workers 1/3: load 40.19677734375 >= 24: holding
[00:54:30] qa workers 1/3: load 40.19677734375 >= 24: holding
[00:54:30] qa workers 1/3: load 40.19677734375 >= 24: holding
[00:54:30] build workers 9/10: load 40.19677734375 >= 24: holding
[00:55:06] reaped stale lock + swept assignee on #253 (pid=43261)
[00:55:13] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:55:13] review workers 1/3: load 47.4267578125 >= 24: holding
[00:55:13] qa workers 1/3: load 47.4267578125 >= 24: holding
[00:55:13] qa workers 1/3: load 47.4267578125 >= 24: holding
[00:55:13] build workers 8/10: load 47.4267578125 >= 24: holding
[00:55:48] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:55:48] review workers 1/3: load 56.0732421875 >= 24: holding
[00:55:48] qa workers 1/3: load 56.0732421875 >= 24: holding
[00:55:48] qa workers 1/3: load 56.0732421875 >= 24: holding
[00:55:48] build workers 8/10: load 56.0732421875 >= 24: holding
[00:56:25] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:56:25] review workers 1/3: load 53.470703125 >= 24: holding
[00:56:25] qa workers 1/3: load 53.470703125 >= 24: holding
[00:56:25] qa workers 1/3: load 53.470703125 >= 24: holding
[00:56:26] build workers 8/10: load 53.470703125 >= 24: holding
[00:57:01] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:57:01] review workers 1/3: load 48.138671875 >= 24: holding
[00:57:01] qa workers 1/3: load 48.138671875 >= 24: holding
[00:57:01] qa workers 1/3: load 48.138671875 >= 24: holding
[00:57:01] build workers 8/10: load 48.138671875 >= 24: holding
[00:57:37] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:57:37] review workers 1/3: load 43.94921875 >= 24: holding
[00:57:37] qa workers 1/3: load 43.94921875 >= 24: holding
[00:57:37] qa workers 1/3: load 43.94921875 >= 24: holding
[00:57:37] build workers 8/10: load 43.94921875 >= 24: holding
[00:58:13] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:58:13] review workers 1/3: load 45.1904296875 >= 24: holding
[00:58:13] qa workers 1/3: load 45.1904296875 >= 24: holding
[00:58:13] qa workers 1/3: load 45.1904296875 >= 24: holding
[00:58:13] build workers 8/10: load 45.1904296875 >= 24: holding
[00:58:48] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:58:48] review workers 1/3: load 42.404296875 >= 24: holding
[00:58:48] qa workers 1/3: load 42.404296875 >= 24: holding
[00:58:48] qa workers 1/3: load 42.404296875 >= 24: holding
[00:58:48] build workers 8/10: load 42.404296875 >= 24: holding
[00:59:22] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[00:59:22] review workers 1/3: load 32.197265625 >= 24: holding
[00:59:23] qa workers 1/3: load 32.197265625 >= 24: holding
[00:59:23] qa workers 1/3: load 32.197265625 >= 24: holding
[00:59:23] build workers 8/10: load 32.197265625 >= 24: holding
[00:59:57] tick — Ready=5 Building=8 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240) b_workers=8/10 q_idle=0(#_ +88568:227) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[01:00:03] dispatch lane=qa issue=#253 pid=59679 claim=ToanMobile
[01:00:03] build workers 8/10, load 21.47314453125 < 24: starting #9
[01:00:12] dispatch lane=build issue=#237 pid=68515 claim=ToanMobile
[01:00:45] reaped stale lock + swept assignee on #227 (pid=88568)
[01:00:50] tick — Ready=4 Building=8 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237) b_workers=9/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#_ +48826:221) r_workers=1/3 waiting_on_you=0
[01:00:56] dispatch lane=review issue=#227 pid=25245 claim=ToanMobile
[01:00:56] build workers 9/10, load 20.46142578125 < 24: starting #10
[01:01:05] dispatch lane=build issue=#223 pid=57280 claim=ToanMobile
kept card 252: live build lane (pid 85265) holds it
kept card 251: live build lane (pid 98420) holds it
[01:01:42] tick — Ready=3 Building=9 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:01:42] review workers 2/3: load 39.58740234375 >= 24: holding
[01:01:42] qa workers 1/3: load 39.58740234375 >= 24: holding
[01:01:43] qa workers 1/3: load 39.58740234375 >= 24: holding
[01:01:43] build workers 10/10: at the cap, not starting
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 248: live build lane (pid 63273) holds it
kept card 249: live build lane (pid 76741) holds it
kept card 237: live build lane (pid 68515) holds it
kept card 255: live build lane (pid 31031) holds it
[01:02:20] tick — Ready=3 Building=9 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:02:20] review workers 2/3: load 52.0263671875 >= 24: holding
[01:02:20] qa workers 1/3: load 52.0263671875 >= 24: holding
[01:02:20] qa workers 1/3: load 52.0263671875 >= 24: holding
[01:02:20] build workers 10/10: at the cap, not starting
[01:02:56] tick — Ready=3 Building=9 QA=2 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:02:56] review workers 2/3: load 57.4677734375 >= 24: holding
[01:02:56] qa workers 1/3: load 57.4677734375 >= 24: holding
[01:02:57] qa workers 1/3: load 57.4677734375 >= 24: holding
[01:02:57] build workers 10/10: at the cap, not starting
[01:03:33] tick — Ready=3 Building=8 QA=3 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:03:34] review workers 2/3: load 47.1650390625 >= 24: holding
[01:03:34] qa workers 1/3: load 47.1650390625 >= 24: holding
[01:03:34] qa workers 1/3: load 47.1650390625 >= 24: holding
[01:03:34] build workers 10/10: at the cap, not starting
[01:04:09] tick — Ready=3 Building=8 QA=3 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:04:10] review workers 2/3: load 31.17431640625 >= 24: holding
[01:04:10] qa workers 1/3: load 31.17431640625 >= 24: holding
[01:04:10] qa workers 1/3: load 31.17431640625 >= 24: holding
[01:04:10] build workers 10/10: at the cap, not starting
[01:04:47] tick — Ready=3 Building=8 QA=3 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:04:47] review workers 2/3: load 40.7685546875 >= 24: holding
[01:04:47] qa workers 1/3: load 40.7685546875 >= 24: holding
[01:04:47] qa workers 1/3: load 40.7685546875 >= 24: holding
[01:04:47] build workers 10/10: at the cap, not starting
[01:05:23] tick — Ready=3 Building=7 QA=4 Review=2 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 31031:255 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=10/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227 +48826:221) r_workers=2/3 waiting_on_you=0
[01:05:23] review workers 2/3: load 39.3369140625 >= 24: holding
[01:05:24] qa workers 1/3: load 39.3369140625 >= 24: holding
[01:05:24] qa workers 1/3: load 39.3369140625 >= 24: holding
[01:05:24] build workers 10/10: at the cap, not starting
[01:05:57] reaped stale lock + swept assignee on #221 (pid=48826)
[01:06:11] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 92769:254 76741:249 16953:250 83742:240 68515:237 57280:223) b_workers=9/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:06:12] review workers 1/3: load 38.00244140625 >= 24: holding
[01:06:12] qa workers 1/3: load 38.00244140625 >= 24: holding
[01:06:12] qa workers 1/3: load 38.00244140625 >= 24: holding
[01:06:12] build workers 7/10: load 38.00244140625 >= 24: holding
[01:06:47] reaped stale lock + swept assignee on #250 (pid=16953)
[01:06:52] reaped stale lock + swept assignee on #254 (pid=92769)
[01:06:55] reaped stale lock + swept assignee on #255 (pid=31031)
[01:07:01] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:07:01] review workers 1/3: load 68.8037109375 >= 24: holding
[01:07:01] qa workers 1/3: load 68.8037109375 >= 24: holding
[01:07:01] qa workers 1/3: load 68.8037109375 >= 24: holding
[01:07:02] build workers 7/10: load 68.8037109375 >= 24: holding
[01:07:38] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:07:38] review workers 1/3: load 76.86669921875 >= 24: holding
[01:07:38] qa workers 1/3: load 76.86669921875 >= 24: holding
[01:07:38] qa workers 1/3: load 76.86669921875 >= 24: holding
[01:07:38] build workers 7/10: load 76.86669921875 >= 24: holding
[01:08:14] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:08:14] review workers 1/3: load 66.1630859375 >= 24: holding
[01:08:14] qa workers 1/3: load 66.1630859375 >= 24: holding
[01:08:14] qa workers 1/3: load 66.1630859375 >= 24: holding
[01:08:14] build workers 7/10: load 66.1630859375 >= 24: holding
[01:08:49] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:08:49] review workers 1/3: load 49.32470703125 >= 24: holding
[01:08:49] qa workers 1/3: load 49.32470703125 >= 24: holding
[01:08:49] qa workers 1/3: load 49.32470703125 >= 24: holding
[01:08:49] build workers 7/10: load 49.32470703125 >= 24: holding
[01:09:24] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:09:24] review workers 1/3: load 33.34619140625 >= 24: holding
[01:09:24] qa workers 1/3: load 33.34619140625 >= 24: holding
[01:09:24] qa workers 1/3: load 33.34619140625 >= 24: holding
[01:09:24] build workers 7/10: load 33.34619140625 >= 24: holding
[01:10:00] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:10:00] review workers 1/3: load 25.21044921875 >= 24: holding
[01:10:00] qa workers 1/3: load 25.21044921875 >= 24: holding
[01:10:00] qa workers 1/3: load 25.21044921875 >= 24: holding
[01:10:00] build workers 7/10: load 25.21044921875 >= 24: holding
[01:10:36] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:10:36] review workers 1/3: load 32.244140625 >= 24: holding
[01:10:36] qa workers 1/3: load 32.244140625 >= 24: holding
[01:10:36] qa workers 1/3: load 32.244140625 >= 24: holding
[01:10:36] build workers 7/10: load 32.244140625 >= 24: holding
[01:11:11] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:11:12] review workers 1/3: load 30.7373046875 >= 24: holding
[01:11:12] qa workers 1/3: load 30.7373046875 >= 24: holding
[01:11:12] qa workers 1/3: load 30.7373046875 >= 24: holding
[01:11:12] build workers 7/10: load 30.7373046875 >= 24: holding
kept card 221: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 249: live build lane (pid 76741) holds it
[01:11:48] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:11:48] review workers 1/3: load 39.4453125 >= 24: holding
[01:11:48] qa workers 1/3: load 39.4453125 >= 24: holding
[01:11:48] qa workers 1/3: load 39.4453125 >= 24: holding
[01:11:48] build workers 7/10: load 39.4453125 >= 24: holding
kept card 223: live build lane (pid 57280) holds it
kept card 252: live build lane (pid 85265) holds it
kept card 227: live review lane (pid 25245) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 237: live build lane (pid 68515) holds it
[01:12:23] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:12:23] review workers 1/3: load 34.10205078125 >= 24: holding
[01:12:23] qa workers 1/3: load 34.10205078125 >= 24: holding
[01:12:23] qa workers 1/3: load 34.10205078125 >= 24: holding
[01:12:24] build workers 7/10: load 34.10205078125 >= 24: holding
[01:13:00] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:13:00] review workers 1/3: load 49.453125 >= 24: holding
[01:13:00] qa workers 1/3: load 49.453125 >= 24: holding
[01:13:00] qa workers 1/3: load 49.453125 >= 24: holding
[01:13:00] build workers 7/10: load 49.453125 >= 24: holding
[01:13:36] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:13:36] review workers 1/3: load 53.4677734375 >= 24: holding
[01:13:36] qa workers 1/3: load 53.4677734375 >= 24: holding
[01:13:36] qa workers 1/3: load 53.4677734375 >= 24: holding
[01:13:36] build workers 7/10: load 53.4677734375 >= 24: holding
[01:14:12] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:14:12] review workers 1/3: load 53.94580078125 >= 24: holding
[01:14:12] qa workers 1/3: load 53.94580078125 >= 24: holding
[01:14:12] qa workers 1/3: load 53.94580078125 >= 24: holding
[01:14:12] build workers 7/10: load 53.94580078125 >= 24: holding
[01:14:48] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:14:48] review workers 1/3: load 59.837890625 >= 24: holding
[01:14:48] qa workers 1/3: load 59.837890625 >= 24: holding
[01:14:48] qa workers 1/3: load 59.837890625 >= 24: holding
[01:14:48] build workers 7/10: load 59.837890625 >= 24: holding
[01:15:24] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:15:24] review workers 1/3: load 51.201171875 >= 24: holding
[01:15:24] qa workers 1/3: load 51.201171875 >= 24: holding
[01:15:24] qa workers 1/3: load 51.201171875 >= 24: holding
[01:15:24] build workers 7/10: load 51.201171875 >= 24: holding
[01:16:00] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:16:00] review workers 1/3: load 52.974609375 >= 24: holding
[01:16:00] qa workers 1/3: load 52.974609375 >= 24: holding
[01:16:00] qa workers 1/3: load 52.974609375 >= 24: holding
[01:16:00] build workers 7/10: load 52.974609375 >= 24: holding
[01:16:35] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:16:35] review workers 1/3: load 46.76953125 >= 24: holding
[01:16:35] qa workers 1/3: load 46.76953125 >= 24: holding
[01:16:35] qa workers 1/3: load 46.76953125 >= 24: holding
[01:16:35] build workers 7/10: load 46.76953125 >= 24: holding
[01:17:11] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:17:11] review workers 1/3: load 48.20458984375 >= 24: holding
[01:17:11] qa workers 1/3: load 48.20458984375 >= 24: holding
[01:17:12] qa workers 1/3: load 48.20458984375 >= 24: holding
[01:17:12] build workers 7/10: load 48.20458984375 >= 24: holding
[01:17:47] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:17:47] review workers 1/3: load 46.89453125 >= 24: holding
[01:17:47] qa workers 1/3: load 46.89453125 >= 24: holding
[01:17:47] qa workers 1/3: load 46.89453125 >= 24: holding
[01:17:47] build workers 7/10: load 46.89453125 >= 24: holding
[01:18:23] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:18:23] review workers 1/3: load 45.32177734375 >= 24: holding
[01:18:23] qa workers 1/3: load 45.32177734375 >= 24: holding
[01:18:23] qa workers 1/3: load 45.32177734375 >= 24: holding
[01:18:23] build workers 7/10: load 45.32177734375 >= 24: holding
[01:18:58] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:18:58] review workers 1/3: load 46.22998046875 >= 24: holding
[01:18:58] qa workers 1/3: load 46.22998046875 >= 24: holding
[01:18:58] qa workers 1/3: load 46.22998046875 >= 24: holding
[01:18:58] build workers 7/10: load 46.22998046875 >= 24: holding
[01:19:32] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:19:32] review workers 1/3: load 30.3505859375 >= 24: holding
[01:19:32] qa workers 1/3: load 30.3505859375 >= 24: holding
[01:19:32] qa workers 1/3: load 30.3505859375 >= 24: holding
[01:19:32] build workers 7/10: load 30.3505859375 >= 24: holding
[01:20:07] tick — Ready=3 Building=5 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223) b_workers=7/10 q_idle=0(#253) q_workers=1/3 r_idle=0(#227) r_workers=1/3 waiting_on_you=0
[01:20:12] dispatch lane=qa issue=#254 pid=10204 claim=ToanMobile
[01:20:12] build workers 7/10, load 20.220703125 < 24: starting #8
[01:20:20] dispatch lane=build issue=#202 pid=19149 claim=ToanMobile
[01:20:55] 💀 zombie review worker on #227 (pid=25245) — card moved to 'Ready'; killing
[01:20:59] tick — Ready=3 Building=6 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223 19149:202) b_workers=8/10 q_idle=0(#253 +10204:254) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:21:05] dispatch lane=qa issue=#255 pid=78016 claim=ToanMobile
[01:21:05] build workers 8/10, load 14.44140625 < 24: starting #9
[01:21:13] dispatch lane=build issue=#247 pid=85239 claim=ToanMobile
[01:21:49] tick — Ready=2 Building=7 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223 19149:202 85239:247) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:21:49] qa workers 3/3: at the cap, not starting
[01:21:49] qa workers 3/3: at the cap, not starting
[01:21:49] build workers 9/10, load 22.0224609375 < 24: starting #10
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 254: live qa lane (pid 10204) holds it
kept card 223: live build lane (pid 57280) holds it
kept card 249: live build lane (pid 76741) holds it
kept card 237: live build lane (pid 68515) holds it
kept card 251: live build lane (pid 98420) holds it
[01:21:59] dispatch lane=build issue=#227 pid=44852 claim=ToanMobile
kept card 247: live build lane (pid 85239) holds it
kept card 252: live build lane (pid 85265) holds it
[01:22:36] tick — Ready=1 Building=8 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:22:36] qa workers 3/3: at the cap, not starting
[01:22:36] qa workers 3/3: at the cap, not starting
[01:22:36] build workers 10/10: at the cap, not starting
[01:23:12] tick — Ready=1 Building=8 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 76741:249 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:23:12] qa workers 3/3: at the cap, not starting
[01:23:12] qa workers 3/3: at the cap, not starting
[01:23:12] build workers 10/10: at the cap, not starting
[01:23:45] reaped stale lock + swept assignee on #249 (pid=76741)
[01:23:49] tick — Ready=1 Building=8 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:23:49] qa workers 3/3: at the cap, not starting
[01:23:49] qa workers 3/3: at the cap, not starting
[01:23:49] build workers 9/10, load 17.71240234375 < 24: starting #10
[01:23:58] dispatch lane=build issue=#229 pid=55806 claim=ToanMobile
[01:24:38] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:24:38] qa workers 3/3: at the cap, not starting
[01:24:38] qa workers 3/3: at the cap, not starting
[01:25:17] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:25:17] qa workers 3/3: at the cap, not starting
[01:25:17] qa workers 3/3: at the cap, not starting
[01:25:53] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:25:53] qa workers 3/3: at the cap, not starting
[01:25:53] qa workers 3/3: at the cap, not starting
[01:26:28] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +98420:251 85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=10/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:26:28] qa workers 3/3: at the cap, not starting
[01:26:28] qa workers 3/3: at the cap, not starting
[01:27:02] reaped stale lock + swept assignee on #251 (pid=98420)
[01:27:06] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:27:06] qa workers 3/3: at the cap, not starting
[01:27:06] qa workers 3/3: at the cap, not starting
[01:27:41] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:27:41] qa workers 3/3: at the cap, not starting
[01:27:41] qa workers 3/3: at the cap, not starting
[01:28:18] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:28:18] qa workers 3/3: at the cap, not starting
[01:28:18] qa workers 3/3: at the cap, not starting
[01:28:56] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:28:56] qa workers 3/3: at the cap, not starting
[01:28:56] qa workers 3/3: at the cap, not starting
[01:29:33] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:29:33] qa workers 3/3: at the cap, not starting
[01:29:34] qa workers 3/3: at the cap, not starting
[01:30:10] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:30:10] qa workers 3/3: at the cap, not starting
[01:30:10] qa workers 3/3: at the cap, not starting
[01:30:46] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:30:46] qa workers 3/3: at the cap, not starting
[01:30:46] qa workers 3/3: at the cap, not starting
[01:31:21] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:31:21] qa workers 3/3: at the cap, not starting
[01:31:21] qa workers 3/3: at the cap, not starting
kept card 255: live qa lane (pid 78016) holds it
kept card 223: live build lane (pid 57280) holds it
kept card 227: live build lane (pid 44852) holds it
[01:31:58] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:31:58] qa workers 3/3: at the cap, not starting
[01:31:58] qa workers 3/3: at the cap, not starting
kept card 248: live build lane (pid 63273) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live build lane (pid 83742) holds it
kept card 202: live build lane (pid 19149) holds it
[01:32:33] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:32:33] qa workers 3/3: at the cap, not starting
[01:32:33] qa workers 3/3: at the cap, not starting
[01:33:08] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:33:08] qa workers 3/3: at the cap, not starting
[01:33:08] qa workers 3/3: at the cap, not starting
[01:33:43] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:33:43] qa workers 3/3: at the cap, not starting
[01:33:43] qa workers 3/3: at the cap, not starting
[01:34:19] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:34:19] qa workers 3/3: at the cap, not starting
[01:34:19] qa workers 3/3: at the cap, not starting
[01:34:54] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:34:54] qa workers 3/3: at the cap, not starting
[01:34:54] qa workers 3/3: at the cap, not starting
[01:35:30] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:35:30] qa workers 3/3: at the cap, not starting
[01:35:30] qa workers 3/3: at the cap, not starting
[01:36:05] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:36:05] qa workers 3/3: at the cap, not starting
[01:36:06] qa workers 3/3: at the cap, not starting
[01:36:41] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:36:41] qa workers 3/3: at the cap, not starting
[01:36:41] qa workers 3/3: at the cap, not starting
[01:37:17] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:37:17] qa workers 3/3: at the cap, not starting
[01:37:17] qa workers 3/3: at the cap, not starting
[01:37:55] tick — Ready=0 Building=9 QA=6 Review=0 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#253 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:37:55] qa workers 3/3: at the cap, not starting
[01:37:55] qa workers 3/3: at the cap, not starting
[01:38:33] 💀 zombie qa worker on #253 (pid=59679) — card moved to 'Review'; killing
[01:38:37] tick — Ready=0 Building=9 QA=5 Review=1 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[01:38:45] dispatch lane=review issue=#253 pid=37273 claim=ToanMobile
[01:38:45] qa workers 2/3: load 69.8564453125 >= 24: holding
[01:38:45] qa workers 2/3: load 69.8564453125 >= 24: holding
[01:39:23] tick — Ready=0 Building=8 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 44852:227 55806:229) b_workers=9/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:39:23] review workers 1/3: load 66.84814453125 >= 24: holding
[01:39:23] qa workers 2/3: load 66.84814453125 >= 24: holding
[01:39:23] qa workers 2/3: load 66.84814453125 >= 24: holding
[01:39:56] reaped stale lock + swept assignee on #227 (pid=44852)
[01:40:02] tick — Ready=0 Building=8 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=8/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:40:02] review workers 1/3: load 54.01953125 >= 24: holding
[01:40:02] qa workers 2/3: load 54.01953125 >= 24: holding
[01:40:02] qa workers 2/3: load 54.01953125 >= 24: holding
[01:40:39] tick — Ready=0 Building=8 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=8/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:40:39] review workers 1/3: load 44.78857421875 >= 24: holding
[01:40:39] qa workers 2/3: load 44.78857421875 >= 24: holding
[01:40:39] qa workers 2/3: load 44.78857421875 >= 24: holding
[01:41:14] tick — Ready=0 Building=8 QA=6 Review=1 Blocked=9 lanes: b_idle=0(#248 +85265:252 83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=8/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:41:14] review workers 1/3: load 43.53564453125 >= 24: holding
[01:41:14] qa workers 2/3: load 43.53564453125 >= 24: holding
[01:41:15] qa workers 2/3: load 43.53564453125 >= 24: holding
[01:41:54] reaped stale lock + swept assignee on #252 (pid=85265)
kept card 240: live build lane (pid 83742) holds it
kept card 248: live build lane (pid 63273) holds it
[01:41:59] tick — Ready=0 Building=7 QA=7 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:41:59] review workers 1/3: load 51.95263671875 >= 24: holding
[01:41:59] qa workers 2/3: load 51.95263671875 >= 24: holding
[01:41:59] qa workers 2/3: load 51.95263671875 >= 24: holding
kept card 254: live qa lane (pid 10204) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 237: live build lane (pid 68515) holds it
kept card 253: live review lane (pid 37273) holds it
[01:42:35] tick — Ready=0 Building=7 QA=7 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:42:35] review workers 1/3: load 49.68115234375 >= 24: holding
[01:42:35] qa workers 2/3: load 50.98779296875 >= 24: holding
[01:42:35] qa workers 2/3: load 50.98779296875 >= 24: holding
[01:43:10] tick — Ready=0 Building=7 QA=7 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:43:10] review workers 1/3: load 46.5830078125 >= 24: holding
[01:43:10] qa workers 2/3: load 46.5830078125 >= 24: holding
[01:43:10] qa workers 2/3: load 46.5830078125 >= 24: holding
[01:43:47] tick — Ready=0 Building=6 QA=8 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:43:47] review workers 1/3: load 40.16357421875 >= 24: holding
[01:43:47] qa workers 2/3: load 40.16357421875 >= 24: holding
[01:43:47] qa workers 2/3: load 40.16357421875 >= 24: holding
[01:44:24] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:44:24] review workers 1/3: load 38.1689453125 >= 24: holding
[01:44:24] qa workers 2/3: load 38.1689453125 >= 24: holding
[01:44:24] qa workers 2/3: load 38.1689453125 >= 24: holding
[01:45:00] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:45:00] review workers 1/3: load 53.87841796875 >= 24: holding
[01:45:00] qa workers 2/3: load 53.87841796875 >= 24: holding
[01:45:00] qa workers 2/3: load 53.87841796875 >= 24: holding
[01:45:35] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:45:35] review workers 1/3: load 47.40771484375 >= 24: holding
[01:45:36] qa workers 2/3: load 47.40771484375 >= 24: holding
[01:45:36] qa workers 2/3: load 47.40771484375 >= 24: holding
[01:46:16] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:46:16] review workers 1/3: load 53.6181640625 >= 24: holding
[01:46:16] qa workers 2/3: load 53.6181640625 >= 24: holding
[01:46:16] qa workers 2/3: load 53.6181640625 >= 24: holding
[01:46:55] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:46:55] review workers 1/3: load 79.3076171875 >= 24: holding
[01:46:55] qa workers 2/3: load 79.3076171875 >= 24: holding
[01:46:55] qa workers 2/3: load 79.3076171875 >= 24: holding
[01:47:35] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:47:35] review workers 1/3: load 93.10546875 >= 24: holding
[01:47:35] qa workers 2/3: load 93.10546875 >= 24: holding
[01:47:35] qa workers 2/3: load 93.10546875 >= 24: holding
[01:48:15] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:48:15] review workers 1/3: load 109.75830078125 >= 24: holding
[01:48:16] qa workers 2/3: load 109.75830078125 >= 24: holding
[01:48:16] qa workers 2/3: load 109.75830078125 >= 24: holding
[01:48:55] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:48:56] review workers 1/3: load 113.90966796875 >= 24: holding
[01:48:56] qa workers 2/3: load 113.90966796875 >= 24: holding
[01:48:56] qa workers 2/3: load 113.90966796875 >= 24: holding
[01:49:35] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:49:35] review workers 1/3: load 113.3076171875 >= 24: holding
[01:49:35] qa workers 2/3: load 113.3076171875 >= 24: holding
[01:49:35] qa workers 2/3: load 113.3076171875 >= 24: holding
[01:50:14] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:50:15] review workers 1/3: load 120.9990234375 >= 24: holding
[01:50:15] qa workers 2/3: load 120.9990234375 >= 24: holding
[01:50:15] qa workers 2/3: load 123.3212890625 >= 24: holding
[01:50:55] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:50:55] review workers 1/3: load 131.642578125 >= 24: holding
[01:50:55] qa workers 2/3: load 131.642578125 >= 24: holding
[01:50:55] qa workers 2/3: load 131.642578125 >= 24: holding
[01:51:35] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:51:35] review workers 1/3: load 135.46826171875 >= 24: holding
[01:51:35] qa workers 2/3: load 133.5888671875 >= 24: holding
[01:51:35] qa workers 2/3: load 133.5888671875 >= 24: holding
[01:52:11] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 19149:202 85239:247 55806:229) b_workers=7/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:52:11] review workers 1/3: load 103.0 >= 24: holding
[01:52:11] qa workers 2/3: load 103.0 >= 24: holding
[01:52:11] qa workers 2/3: load 103.0 >= 24: holding
kept card 229: live build lane (pid 55806) holds it
kept card 254: live qa lane (pid 10204) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[01:52:44] reaped stale lock + swept assignee on #202 (pid=19149)
[01:52:51] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 85239:247 55806:229) b_workers=6/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:52:51] review workers 1/3: load 94.75634765625 >= 24: holding
[01:52:51] qa workers 2/3: load 94.75634765625 >= 24: holding
[01:52:51] qa workers 2/3: load 94.75634765625 >= 24: holding
[01:53:27] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 85239:247 55806:229) b_workers=6/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:53:27] review workers 1/3: load 82.45166015625 >= 24: holding
[01:53:27] qa workers 2/3: load 82.45166015625 >= 24: holding
[01:53:27] qa workers 2/3: load 82.45166015625 >= 24: holding
[01:54:04] tick — Ready=0 Building=5 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 57280:223 85239:247 55806:229) b_workers=6/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:54:04] review workers 1/3: load 87.05419921875 >= 24: holding
[01:54:04] qa workers 2/3: load 87.05419921875 >= 24: holding
[01:54:04] qa workers 2/3: load 87.05419921875 >= 24: holding
[01:54:37] reaped stale lock + swept assignee on #223 (pid=57280)
[01:54:56] ↩ stranded #223: Building → Ready (branch issue-223-precommit-test-durations)
[01:54:59] tick — Ready=1 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 55806:229) b_workers=5/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:54:59] review workers 1/3: load 89.5869140625 >= 24: holding
[01:54:59] qa workers 2/3: load 89.5869140625 >= 24: holding
[01:54:59] qa workers 2/3: load 89.5869140625 >= 24: holding
[01:54:59] build workers 5/10: load 89.5869140625 >= 24: holding
[01:55:34] tick — Ready=1 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 55806:229) b_workers=5/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:55:34] review workers 1/3: load 78.89794921875 >= 24: holding
[01:55:35] qa workers 2/3: load 78.89794921875 >= 24: holding
[01:55:35] qa workers 2/3: load 78.89794921875 >= 24: holding
[01:55:35] build workers 5/10: load 78.89794921875 >= 24: holding
[01:56:10] tick — Ready=1 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 55806:229) b_workers=5/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:56:10] review workers 1/3: load 70.86279296875 >= 24: holding
[01:56:10] qa workers 2/3: load 70.86279296875 >= 24: holding
[01:56:10] qa workers 2/3: load 69.11181640625 >= 24: holding
[01:56:10] build workers 5/10: load 69.11181640625 >= 24: holding
[01:56:45] tick — Ready=1 Building=3 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247) b_workers=4/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:56:45] review workers 1/3: load 57.89013671875 >= 24: holding
[01:56:45] qa workers 2/3: load 57.89013671875 >= 24: holding
[01:56:45] qa workers 2/3: load 57.89013671875 >= 24: holding
[01:56:45] build workers 4/10: load 57.89013671875 >= 24: holding
[01:57:18] reaped stale lock + swept assignee on #229 (pid=55806)
[01:57:22] tick — Ready=1 Building=3 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247) b_workers=4/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:57:22] review workers 1/3: load 37.7099609375 >= 24: holding
[01:57:22] qa workers 2/3: load 37.7099609375 >= 24: holding
[01:57:22] qa workers 2/3: load 37.7099609375 >= 24: holding
[01:57:22] build workers 4/10: load 37.7099609375 >= 24: holding
[01:57:57] tick — Ready=1 Building=3 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247) b_workers=4/10 q_idle=0(#_ +10204:254 78016:255) q_workers=2/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:58:03] dispatch lane=qa issue=#251 pid=19886 claim=ToanMobile
[01:58:03] build workers 4/10, load 21.2216796875 < 24: starting #5
[01:58:12] dispatch lane=build issue=#223 pid=25181 claim=ToanMobile
[01:58:47] tick — Ready=0 Building=4 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +10204:254 78016:255) q_workers=3/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:58:48] qa workers 3/3: at the cap, not starting
[01:58:48] qa workers 3/3: at the cap, not starting
[01:59:23] tick — Ready=0 Building=4 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +10204:254 78016:255) q_workers=3/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:59:23] qa workers 3/3: at the cap, not starting
[01:59:23] qa workers 3/3: at the cap, not starting
[01:59:57] tick — Ready=0 Building=4 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +10204:254 78016:255) q_workers=3/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[01:59:58] qa workers 3/3: at the cap, not starting
[01:59:58] qa workers 3/3: at the cap, not starting
[02:00:34] tick — Ready=0 Building=4 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +10204:254 78016:255) q_workers=3/3 r_idle=0(#253) r_workers=1/3 waiting_on_you=0
[02:00:34] qa workers 3/3: at the cap, not starting
[02:00:34] qa workers 3/3: at the cap, not starting
[02:01:10] 💀 zombie review worker on #253 (pid=37273) — card moved to 'Done'; killing
[02:01:19] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +10204:254 78016:255) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:01:19] qa workers 3/3: at the cap, not starting
[02:01:19] qa workers 3/3: at the cap, not starting
[02:01:54] reaped stale lock + swept assignee on #254 (pid=10204)
[02:01:59] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:02:07] dispatch lane=review issue=#254 pid=97734 claim=ToanMobile
[02:02:07] qa workers 2/3: load 35.5087890625 >= 24: holding
[02:02:08] qa workers 2/3: load 35.5087890625 >= 24: holding
kept card 248: live build lane (pid 63273) holds it
kept card 240: live build lane (pid 83742) holds it
[02:02:44] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=5/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=0(#254) r_workers=1/3 waiting_on_you=0
[02:02:44] review workers 1/3: load 48.79052734375 >= 24: holding
[02:02:45] qa workers 2/3: load 48.79052734375 >= 24: holding
[02:02:45] qa workers 2/3: load 48.79052734375 >= 24: holding
kept card 251: live qa lane (pid 19886) holds it
kept card 255: live qa lane (pid 78016) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 247: live build lane (pid 85239) holds it
[02:03:19] reaped stale lock + swept assignee on #248 (pid=63273)
[02:03:24] tick — Ready=0 Building=3 QA=10 Review=1 Blocked=9 lanes: b_idle=0(#248 +83742:240 68515:237 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=0(#254) r_workers=1/3 waiting_on_you=0
[02:03:24] review workers 1/3: load 72.87353515625 >= 24: holding
[02:03:24] qa workers 2/3: load 72.87353515625 >= 24: holding
[02:03:24] qa workers 2/3: load 72.87353515625 >= 24: holding
[02:03:58] reaped stale lock + swept assignee on #237 (pid=68515)
[02:04:04] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:04:04] qa workers 2/3: load 67.62255859375 >= 24: holding
[02:04:04] qa workers 2/3: load 67.62255859375 >= 24: holding
[02:04:04] build workers 3/10: load 67.62255859375 >= 24: holding
[02:04:35] ⚠ worker of #254 (lane review) ended 111s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: - **Bước tiếp theo:** builder rebase, rồi review lại ở round 2.
[02:04:38] reaped stale lock + swept assignee on #254 (pid=97734)
[02:04:44] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:04:44] qa workers 2/3: load 58.0380859375 >= 24: holding
[02:04:44] qa workers 2/3: load 58.0380859375 >= 24: holding
[02:04:44] build workers 3/10: load 58.0380859375 >= 24: holding
[02:05:20] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:05:20] qa workers 2/3: load 50.5712890625 >= 24: holding
[02:05:20] qa workers 2/3: load 50.5712890625 >= 24: holding
[02:05:20] build workers 3/10: load 50.5712890625 >= 24: holding
[02:05:56] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:05:56] qa workers 2/3: load 49.74365234375 >= 24: holding
[02:05:56] qa workers 2/3: load 49.74365234375 >= 24: holding
[02:05:56] build workers 3/10: load 49.74365234375 >= 24: holding
[02:06:32] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:06:32] qa workers 2/3: load 45.373046875 >= 24: holding
[02:06:32] qa workers 2/3: load 45.373046875 >= 24: holding
[02:06:32] build workers 3/10: load 45.373046875 >= 24: holding
[02:07:07] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:07:07] qa workers 2/3: load 33.60107421875 >= 24: holding
[02:07:07] qa workers 2/3: load 33.60107421875 >= 24: holding
[02:07:07] build workers 3/10: load 33.60107421875 >= 24: holding
[02:07:42] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:07:42] qa workers 2/3: load 26.40283203125 >= 24: holding
[02:07:42] qa workers 2/3: load 26.40283203125 >= 24: holding
[02:07:42] build workers 3/10: load 26.40283203125 >= 24: holding
[02:08:17] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:08:17] qa workers 2/3: load 24.0791015625 >= 24: holding
[02:08:17] qa workers 2/3: load 24.0791015625 >= 24: holding
[02:08:17] build workers 3/10: load 24.0791015625 >= 24: holding
[02:08:53] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#248 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#251 +78016:255) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:08:59] dispatch lane=qa issue=#252 pid=90927 claim=ToanMobile
[02:08:59] build workers 3/10, load 23.0244140625 < 24: starting #4
[02:09:09] dispatch lane=build issue=#254 pid=11263 claim=ToanMobile
[02:09:44] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:09:44] qa workers 3/3: at the cap, not starting
[02:09:44] qa workers 3/3: at the cap, not starting
[02:10:19] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:10:19] qa workers 3/3: at the cap, not starting
[02:10:19] qa workers 3/3: at the cap, not starting
[02:10:54] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:10:54] qa workers 3/3: at the cap, not starting
[02:10:54] qa workers 3/3: at the cap, not starting
[02:11:28] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:11:28] qa workers 3/3: at the cap, not starting
[02:11:28] qa workers 3/3: at the cap, not starting
[02:12:04] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:12:04] qa workers 3/3: at the cap, not starting
[02:12:04] qa workers 3/3: at the cap, not starting
[02:12:39] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:12:39] qa workers 3/3: at the cap, not starting
[02:12:39] qa workers 3/3: at the cap, not starting
kept card 252: live qa lane (pid 90927) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live build lane (pid 83742) holds it
[02:13:14] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:13:14] qa workers 3/3: at the cap, not starting
[02:13:14] qa workers 3/3: at the cap, not starting
kept card 254: live build lane (pid 11263) holds it
kept card 255: live qa lane (pid 78016) holds it
kept card 223: live build lane (pid 25181) holds it
[02:13:48] tick — Ready=0 Building=4 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=3/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:13:48] qa workers 3/3: at the cap, not starting
[02:13:48] qa workers 3/3: at the cap, not starting
[02:14:21] reaped stale lock + swept assignee on #251 (pid=19886)
[02:14:26] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#251 +78016:255 90927:252) q_workers=2/3 r_idle=1(#254) r_workers=0/3 waiting_on_you=0
[02:14:31] dispatch lane=review issue=#251 pid=97941 claim=ToanMobile
[02:14:37] dispatch lane=qa issue=#248 pid=3668 claim=ToanMobile
[02:15:12] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:15:13] qa workers 3/3: at the cap, not starting
[02:15:13] qa workers 3/3: at the cap, not starting
[02:15:48] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:15:48] qa workers 3/3: at the cap, not starting
[02:15:48] qa workers 3/3: at the cap, not starting
[02:16:24] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:16:24] qa workers 3/3: at the cap, not starting
[02:16:24] qa workers 3/3: at the cap, not starting
[02:17:00] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:17:00] qa workers 3/3: at the cap, not starting
[02:17:00] qa workers 3/3: at the cap, not starting
[02:17:38] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:17:38] review workers 1/3: load 38.47802734375 >= 24: holding
[02:17:38] qa workers 3/3: at the cap, not starting
[02:17:38] qa workers 3/3: at the cap, not starting
[02:18:16] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:18:16] review workers 1/3: load 67.7373046875 >= 24: holding
[02:18:16] qa workers 3/3: at the cap, not starting
[02:18:16] qa workers 3/3: at the cap, not starting
[02:18:54] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:18:54] review workers 1/3: load 82.7431640625 >= 24: holding
[02:18:54] qa workers 3/3: at the cap, not starting
[02:18:54] qa workers 3/3: at the cap, not starting
[02:19:32] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=0(#251) r_workers=1/3 waiting_on_you=0
[02:19:32] review workers 1/3: load 109.67578125 >= 24: holding
[02:19:32] qa workers 3/3: at the cap, not starting
[02:19:32] qa workers 3/3: at the cap, not starting
[02:20:09] 💀 zombie review worker on #251 (pid=97941) — card moved to 'Ready'; killing
[02:20:13] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:20:13] qa workers 3/3: at the cap, not starting
[02:20:13] qa workers 3/3: at the cap, not starting
[02:20:14] build workers 4/10: load 115.03759765625 >= 24: holding
[02:20:49] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:20:49] qa workers 3/3: at the cap, not starting
[02:20:49] qa workers 3/3: at the cap, not starting
[02:20:49] build workers 4/10: load 92.93310546875 >= 24: holding
[02:21:25] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:21:25] qa workers 3/3: at the cap, not starting
[02:21:25] qa workers 3/3: at the cap, not starting
[02:21:25] build workers 4/10: load 70.12744140625 >= 24: holding
[02:22:00] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:22:00] qa workers 3/3: at the cap, not starting
[02:22:00] qa workers 3/3: at the cap, not starting
[02:22:00] build workers 4/10: load 55.7763671875 >= 24: holding
[02:22:36] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:22:36] qa workers 3/3: at the cap, not starting
[02:22:36] qa workers 3/3: at the cap, not starting
[02:22:36] build workers 4/10: load 45.9794921875 >= 24: holding
[02:23:12] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:23:12] qa workers 3/3: at the cap, not starting
[02:23:12] qa workers 3/3: at the cap, not starting
[02:23:12] build workers 4/10: load 38.5185546875 >= 24: holding
kept card 252: live qa lane (pid 90927) holds it
kept card 240: live build lane (pid 83742) holds it
kept card 223: live build lane (pid 25181) holds it
[02:23:47] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:23:47] qa workers 3/3: at the cap, not starting
[02:23:47] qa workers 3/3: at the cap, not starting
[02:23:47] build workers 4/10: load 31.599609375 >= 24: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 247: live build lane (pid 85239) holds it
[02:24:22] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:24:22] qa workers 3/3: at the cap, not starting
[02:24:22] qa workers 3/3: at the cap, not starting
[02:24:22] build workers 4/10: load 26.91357421875 >= 24: holding
[02:24:59] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:24:59] qa workers 3/3: at the cap, not starting
[02:24:59] qa workers 3/3: at the cap, not starting
[02:24:59] build workers 4/10: load 34.45703125 >= 24: holding
[02:25:36] tick — Ready=1 Building=4 QA=9 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:25:36] qa workers 3/3: at the cap, not starting
[02:25:36] qa workers 3/3: at the cap, not starting
[02:25:36] build workers 4/10: load 52.20654296875 >= 24: holding
[02:26:13] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:26:13] qa workers 3/3: at the cap, not starting
[02:26:13] qa workers 3/3: at the cap, not starting
[02:26:13] build workers 4/10: load 58.177734375 >= 24: holding
[02:26:47] reaped stale lock + swept assignee on #254 (pid=11263)
[02:26:52] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:26:52] qa workers 3/3: at the cap, not starting
[02:26:52] qa workers 3/3: at the cap, not starting
[02:26:52] build workers 3/10: load 47.89306640625 >= 24: holding
[02:27:27] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:27:27] qa workers 3/3: at the cap, not starting
[02:27:27] qa workers 3/3: at the cap, not starting
[02:27:27] build workers 3/10: load 46.330078125 >= 24: holding
[02:28:02] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:28:02] qa workers 3/3: at the cap, not starting
[02:28:03] qa workers 3/3: at the cap, not starting
[02:28:03] build workers 3/10: load 38.2333984375 >= 24: holding
[02:28:38] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:28:38] qa workers 3/3: at the cap, not starting
[02:28:38] qa workers 3/3: at the cap, not starting
[02:28:38] build workers 3/10: load 34.32666015625 >= 24: holding
[02:29:13] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:29:13] qa workers 3/3: at the cap, not starting
[02:29:13] qa workers 3/3: at the cap, not starting
[02:29:13] build workers 3/10: load 29.39990234375 >= 24: holding
[02:29:49] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:29:49] qa workers 3/3: at the cap, not starting
[02:29:49] qa workers 3/3: at the cap, not starting
[02:29:49] build workers 3/10: load 34.46923828125 >= 24: holding
[02:30:26] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:30:26] qa workers 3/3: at the cap, not starting
[02:30:26] qa workers 3/3: at the cap, not starting
[02:30:26] build workers 3/10: load 56.4755859375 >= 24: holding
[02:31:01] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:31:01] qa workers 3/3: at the cap, not starting
[02:31:01] qa workers 3/3: at the cap, not starting
[02:31:01] build workers 3/10: load 67.00146484375 >= 24: holding
[02:31:36] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:31:36] qa workers 3/3: at the cap, not starting
[02:31:36] qa workers 3/3: at the cap, not starting
[02:31:36] build workers 3/10: load 51.59521484375 >= 24: holding
[02:32:11] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:32:11] qa workers 3/3: at the cap, not starting
[02:32:11] qa workers 3/3: at the cap, not starting
[02:32:11] build workers 3/10: load 38.42041015625 >= 24: holding
[02:32:46] tick — Ready=1 Building=3 QA=10 Review=0 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 90927:252) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:32:46] qa workers 3/3: at the cap, not starting
[02:32:46] qa workers 3/3: at the cap, not starting
[02:32:46] build workers 3/10: load 28.53515625 >= 24: holding
[02:33:20] 💀 zombie qa worker on #252 (pid=90927) — card moved to 'Review'; killing
[02:33:24] tick — Ready=1 Building=3 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#254 +83742:240 85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[02:33:30] dispatch lane=review issue=#252 pid=28483 claim=ToanMobile
[02:33:36] dispatch lane=qa issue=#254 pid=36748 claim=ToanMobile
[02:33:36] build workers 3/10, load 23.6748046875 < 24: starting #4
[02:33:45] dispatch lane=build issue=#251 pid=48868 claim=ToanMobile
[02:34:20] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:34:20] qa workers 3/3: at the cap, not starting
[02:34:20] qa workers 3/3: at the cap, not starting
kept card 252: live review lane (pid 28483) holds it
kept card 223: live build lane (pid 25181) holds it
kept card 251: live build lane (pid 48868) holds it
kept card 247: live build lane (pid 85239) holds it
kept card 240: live build lane (pid 83742) holds it
kept card 254: live qa lane (pid 36748) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[02:34:55] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:34:55] qa workers 3/3: at the cap, not starting
[02:34:55] qa workers 3/3: at the cap, not starting
[02:35:30] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:35:30] qa workers 3/3: at the cap, not starting
[02:35:30] qa workers 3/3: at the cap, not starting
[02:36:05] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:36:05] qa workers 3/3: at the cap, not starting
[02:36:05] qa workers 3/3: at the cap, not starting
[02:36:39] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:36:40] qa workers 3/3: at the cap, not starting
[02:36:40] qa workers 3/3: at the cap, not starting
[02:37:15] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:37:15] qa workers 3/3: at the cap, not starting
[02:37:15] qa workers 3/3: at the cap, not starting
[02:37:49] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:37:49] qa workers 3/3: at the cap, not starting
[02:37:49] qa workers 3/3: at the cap, not starting
[02:38:24] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:38:24] qa workers 3/3: at the cap, not starting
[02:38:24] qa workers 3/3: at the cap, not starting
[02:38:59] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:38:59] qa workers 3/3: at the cap, not starting
[02:38:59] qa workers 3/3: at the cap, not starting
[02:39:35] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:39:35] qa workers 3/3: at the cap, not starting
[02:39:35] qa workers 3/3: at the cap, not starting
[02:40:11] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:40:11] qa workers 3/3: at the cap, not starting
[02:40:11] qa workers 3/3: at the cap, not starting
[02:40:47] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:40:47] review workers 1/3: load 25.28369140625 >= 24: holding
[02:40:47] qa workers 3/3: at the cap, not starting
[02:40:47] qa workers 3/3: at the cap, not starting
[02:41:23] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:41:23] review workers 1/3: load 46.1884765625 >= 24: holding
[02:41:23] qa workers 3/3: at the cap, not starting
[02:41:23] qa workers 3/3: at the cap, not starting
[02:41:59] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:41:59] review workers 1/3: load 33.658203125 >= 24: holding
[02:41:59] qa workers 3/3: at the cap, not starting
[02:41:59] qa workers 3/3: at the cap, not starting
[02:42:33] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:42:33] review workers 1/3: load 27.89404296875 >= 24: holding
[02:42:33] qa workers 3/3: at the cap, not starting
[02:42:33] qa workers 3/3: at the cap, not starting
[02:43:07] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:43:08] qa workers 3/3: at the cap, not starting
[02:43:08] qa workers 3/3: at the cap, not starting
[02:43:42] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:43:43] qa workers 3/3: at the cap, not starting
[02:43:43] qa workers 3/3: at the cap, not starting
[02:44:18] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:44:18] qa workers 3/3: at the cap, not starting
[02:44:18] qa workers 3/3: at the cap, not starting
[02:44:53] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:44:53] qa workers 3/3: at the cap, not starting
[02:44:53] qa workers 3/3: at the cap, not starting
kept card 248: live qa lane (pid 3668) holds it
kept card 240: live build lane (pid 83742) holds it
kept card 251: live build lane (pid 48868) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 255: live qa lane (pid 78016) holds it
kept card 254: live qa lane (pid 36748) holds it
[02:45:29] tick — Ready=0 Building=4 QA=9 Review=1 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255 36748:254) q_workers=3/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:45:29] review workers 1/3: load 25.5791015625 >= 24: holding
[02:45:29] qa workers 3/3: at the cap, not starting
[02:45:29] qa workers 3/3: at the cap, not starting
[02:46:04] 💀 zombie qa worker on #254 (pid=36748) — card moved to 'Review'; killing
[02:46:08] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:46:08] review workers 1/3: load 29.5390625 >= 24: holding
[02:46:08] qa workers 2/3: load 29.5390625 >= 24: holding
[02:46:08] qa workers 2/3: load 29.5390625 >= 24: holding
[02:46:45] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:46:45] review workers 1/3: load 31.51025390625 >= 24: holding
[02:46:45] qa workers 2/3: load 31.51025390625 >= 24: holding
[02:46:45] qa workers 2/3: load 31.51025390625 >= 24: holding
[02:47:22] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:47:22] review workers 1/3: load 40.19580078125 >= 24: holding
[02:47:22] qa workers 2/3: load 40.19580078125 >= 24: holding
[02:47:22] qa workers 2/3: load 40.19580078125 >= 24: holding
[02:47:58] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:47:59] review workers 1/3: load 48.05615234375 >= 24: holding
[02:47:59] qa workers 2/3: load 48.05615234375 >= 24: holding
[02:47:59] qa workers 2/3: load 48.05615234375 >= 24: holding
[02:48:36] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:48:36] review workers 1/3: load 53.404296875 >= 24: holding
[02:48:36] qa workers 2/3: load 53.404296875 >= 24: holding
[02:48:36] qa workers 2/3: load 53.404296875 >= 24: holding
[02:49:13] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:49:13] review workers 1/3: load 67.86865234375 >= 24: holding
[02:49:13] qa workers 2/3: load 67.86865234375 >= 24: holding
[02:49:13] qa workers 2/3: load 67.86865234375 >= 24: holding
[02:49:51] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:49:52] review workers 1/3: load 90.12158203125 >= 24: holding
[02:49:52] qa workers 2/3: load 90.12158203125 >= 24: holding
[02:49:52] qa workers 2/3: load 90.12158203125 >= 24: holding
[02:50:30] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:50:30] review workers 1/3: load 103.34912109375 >= 24: holding
[02:50:30] qa workers 2/3: load 103.34912109375 >= 24: holding
[02:50:30] qa workers 2/3: load 103.34912109375 >= 24: holding
[02:51:06] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:51:06] review workers 1/3: load 95.962890625 >= 24: holding
[02:51:06] qa workers 2/3: load 95.962890625 >= 24: holding
[02:51:06] qa workers 2/3: load 95.962890625 >= 24: holding
[02:51:43] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:51:43] review workers 1/3: load 75.197265625 >= 24: holding
[02:51:43] qa workers 2/3: load 75.197265625 >= 24: holding
[02:51:43] qa workers 2/3: load 75.197265625 >= 24: holding
[02:52:19] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:52:19] review workers 1/3: load 62.4130859375 >= 24: holding
[02:52:19] qa workers 2/3: load 62.4130859375 >= 24: holding
[02:52:19] qa workers 2/3: load 62.4130859375 >= 24: holding
[02:52:55] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:52:55] review workers 1/3: load 53.890625 >= 24: holding
[02:52:55] qa workers 2/3: load 53.890625 >= 24: holding
[02:52:55] qa workers 2/3: load 53.890625 >= 24: holding
[02:53:32] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:53:32] review workers 1/3: load 54.67919921875 >= 24: holding
[02:53:32] qa workers 2/3: load 54.67919921875 >= 24: holding
[02:53:32] qa workers 2/3: load 54.67919921875 >= 24: holding
[02:54:07] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:54:07] review workers 1/3: load 48.27001953125 >= 24: holding
[02:54:07] qa workers 2/3: load 48.27001953125 >= 24: holding
[02:54:07] qa workers 2/3: load 48.27001953125 >= 24: holding
[02:54:42] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:54:42] review workers 1/3: load 33.85205078125 >= 24: holding
[02:54:42] qa workers 2/3: load 33.85205078125 >= 24: holding
[02:54:42] qa workers 2/3: load 33.85205078125 >= 24: holding
kept card 240: live build lane (pid 83742) holds it
kept card 252: live review lane (pid 28483) holds it
[02:55:17] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:55:17] review workers 1/3: load 26.541015625 >= 24: holding
[02:55:17] qa workers 2/3: load 26.541015625 >= 24: holding
[02:55:17] qa workers 2/3: load 26.541015625 >= 24: holding
kept card 223: live build lane (pid 25181) holds it
kept card 255: live qa lane (pid 78016) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 247: live build lane (pid 85239) holds it
[02:55:53] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:55:53] review workers 1/3: load 27.98779296875 >= 24: holding
[02:55:53] qa workers 2/3: load 27.98779296875 >= 24: holding
[02:55:53] qa workers 2/3: load 27.98779296875 >= 24: holding
[02:56:30] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:56:30] review workers 1/3: load 39.29052734375 >= 24: holding
[02:56:30] qa workers 2/3: load 39.29052734375 >= 24: holding
[02:56:30] qa workers 2/3: load 39.29052734375 >= 24: holding
[02:57:07] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:57:07] review workers 1/3: load 56.806640625 >= 24: holding
[02:57:07] qa workers 2/3: load 56.806640625 >= 24: holding
[02:57:07] qa workers 2/3: load 56.806640625 >= 24: holding
[02:57:42] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:57:42] review workers 1/3: load 54.9697265625 >= 24: holding
[02:57:42] qa workers 2/3: load 54.9697265625 >= 24: holding
[02:57:43] qa workers 2/3: load 54.9697265625 >= 24: holding
[02:58:18] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:58:18] review workers 1/3: load 51.21484375 >= 24: holding
[02:58:18] qa workers 2/3: load 51.21484375 >= 24: holding
[02:58:18] qa workers 2/3: load 51.21484375 >= 24: holding
[02:58:54] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:58:54] review workers 1/3: load 45.341796875 >= 24: holding
[02:58:54] qa workers 2/3: load 45.341796875 >= 24: holding
[02:58:54] qa workers 2/3: load 45.341796875 >= 24: holding
[02:59:29] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[02:59:29] review workers 1/3: load 39.85693359375 >= 24: holding
[02:59:29] qa workers 2/3: load 39.85693359375 >= 24: holding
[02:59:30] qa workers 2/3: load 39.85693359375 >= 24: holding
[03:00:06] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:00:06] review workers 1/3: load 36.9619140625 >= 24: holding
[03:00:06] qa workers 2/3: load 36.9619140625 >= 24: holding
[03:00:06] qa workers 2/3: load 36.9619140625 >= 24: holding
[03:00:42] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:00:42] review workers 1/3: load 35.96435546875 >= 24: holding
[03:00:42] qa workers 2/3: load 35.96435546875 >= 24: holding
[03:00:42] qa workers 2/3: load 35.96435546875 >= 24: holding
[03:01:17] tick — Ready=0 Building=4 QA=8 Review=2 Blocked=9 lanes: b_idle=0(#251 +83742:240 85239:247 25181:223) b_workers=4/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:01:17] review workers 1/3: load 35.06640625 >= 24: holding
[03:01:17] qa workers 2/3: load 35.06640625 >= 24: holding
[03:01:18] qa workers 2/3: load 35.06640625 >= 24: holding
[03:01:53] 💀 zombie build worker on #240 (pid=83742) — card moved to 'Blocked'; killing
[03:01:58] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:01:58] review workers 1/3: load 29.3720703125 >= 24: holding
[03:01:58] qa workers 2/3: load 29.3720703125 >= 24: holding
[03:01:58] qa workers 2/3: load 29.3720703125 >= 24: holding
[03:02:35] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:02:35] review workers 1/3: load 25.21875 >= 24: holding
[03:02:35] qa workers 2/3: load 25.21875 >= 24: holding
[03:02:35] qa workers 2/3: load 25.21875 >= 24: holding
[03:03:10] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:03:10] review workers 1/3: load 27.03173828125 >= 24: holding
[03:03:10] qa workers 2/3: load 27.03173828125 >= 24: holding
[03:03:10] qa workers 2/3: load 27.03173828125 >= 24: holding
[03:03:46] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:03:46] review workers 1/3: load 24.3486328125 >= 24: holding
[03:03:46] qa workers 2/3: load 24.3486328125 >= 24: holding
[03:03:46] qa workers 2/3: load 24.3486328125 >= 24: holding
[03:04:22] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:04:22] review workers 1/3: load 46.828125 >= 24: holding
[03:04:22] qa workers 2/3: load 46.828125 >= 24: holding
[03:04:22] qa workers 2/3: load 46.828125 >= 24: holding
[03:04:58] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:04:58] review workers 1/3: load 49.67919921875 >= 24: holding
[03:04:58] qa workers 2/3: load 49.67919921875 >= 24: holding
[03:04:58] qa workers 2/3: load 49.67919921875 >= 24: holding
[03:05:32] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:05:32] review workers 1/3: load 36.5927734375 >= 24: holding
[03:05:32] qa workers 2/3: load 36.5927734375 >= 24: holding
[03:05:32] qa workers 2/3: load 36.5927734375 >= 24: holding
kept card 248: live qa lane (pid 3668) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 223: live build lane (pid 25181) holds it
[03:06:06] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:06:06] review workers 1/3: load 24.9794921875 >= 24: holding
[03:06:07] qa workers 2/3: load 24.9794921875 >= 24: holding
[03:06:07] qa workers 2/3: load 24.9794921875 >= 24: holding
[03:06:41] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255) q_workers=2/3 r_idle=0(#252) r_workers=1/3 waiting_on_you=0
[03:06:46] dispatch lane=review issue=#254 pid=40085 claim=ToanMobile
[03:06:51] dispatch lane=qa issue=#249 pid=44331 claim=ToanMobile
[03:07:27] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=0(#252 +40085:254) r_workers=2/3 waiting_on_you=0
[03:07:27] qa workers 3/3: at the cap, not starting
[03:07:27] qa workers 3/3: at the cap, not starting
[03:08:01] tick — Ready=0 Building=3 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=0(#252 +40085:254) r_workers=2/3 waiting_on_you=0
[03:08:02] qa workers 3/3: at the cap, not starting
[03:08:02] qa workers 3/3: at the cap, not starting
[03:08:36] reaped stale lock + swept assignee on #252 (pid=28483)
[03:08:47] tick — Ready=0 Building=3 QA=8 Review=1 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=0(#252 +40085:254) r_workers=1/3 waiting_on_you=0
[03:08:47] review workers 1/3: load 25.84521484375 >= 24: holding
[03:08:47] qa workers 3/3: at the cap, not starting
[03:08:47] qa workers 3/3: at the cap, not starting
[03:09:23] 💀 zombie review worker on #254 (pid=40085) — card moved to 'Ready'; killing
[03:09:28] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:09:28] qa workers 3/3: at the cap, not starting
[03:09:28] qa workers 3/3: at the cap, not starting
[03:09:28] build workers 3/10: load 31.0224609375 >= 24: holding
[03:10:05] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:10:05] qa workers 3/3: at the cap, not starting
[03:10:06] qa workers 3/3: at the cap, not starting
[03:10:06] build workers 3/10: load 42.35009765625 >= 24: holding
[03:10:43] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:10:43] qa workers 3/3: at the cap, not starting
[03:10:43] qa workers 3/3: at the cap, not starting
[03:10:43] build workers 3/10: load 54.361328125 >= 24: holding
[03:11:19] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:11:19] qa workers 3/3: at the cap, not starting
[03:11:19] qa workers 3/3: at the cap, not starting
[03:11:19] build workers 3/10: load 59.017578125 >= 24: holding
[03:11:55] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:11:55] qa workers 3/3: at the cap, not starting
[03:11:55] qa workers 3/3: at the cap, not starting
[03:11:55] build workers 3/10: load 65.85693359375 >= 24: holding
[03:12:33] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:12:33] qa workers 3/3: at the cap, not starting
[03:12:33] qa workers 3/3: at the cap, not starting
[03:12:33] build workers 3/10: load 81.64599609375 >= 24: holding
[03:13:11] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:13:11] qa workers 3/3: at the cap, not starting
[03:13:11] qa workers 3/3: at the cap, not starting
[03:13:12] build workers 3/10: load 109.66357421875 >= 24: holding
[03:13:51] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:13:51] qa workers 3/3: at the cap, not starting
[03:13:51] qa workers 3/3: at the cap, not starting
[03:13:51] build workers 3/10: load 116.6318359375 >= 24: holding
[03:14:28] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:14:28] qa workers 3/3: at the cap, not starting
[03:14:28] qa workers 3/3: at the cap, not starting
[03:14:28] build workers 3/10: load 119.958984375 >= 24: holding
[03:15:04] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:15:04] qa workers 3/3: at the cap, not starting
[03:15:04] qa workers 3/3: at the cap, not starting
[03:15:04] build workers 3/10: load 96.34619140625 >= 24: holding
kept card 251: live build lane (pid 48868) holds it
[03:15:39] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:15:39] qa workers 3/3: at the cap, not starting
[03:15:39] qa workers 3/3: at the cap, not starting
[03:15:39] build workers 3/10: load 74.8330078125 >= 24: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 223: live build lane (pid 25181) holds it
kept card 249: live qa lane (pid 44331) holds it
kept card 248: live qa lane (pid 3668) holds it
kept card 247: live build lane (pid 85239) holds it
[03:16:15] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:16:15] qa workers 3/3: at the cap, not starting
[03:16:15] qa workers 3/3: at the cap, not starting
[03:16:15] build workers 3/10: load 56.69140625 >= 24: holding
[03:16:50] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:16:50] qa workers 3/3: at the cap, not starting
[03:16:50] qa workers 3/3: at the cap, not starting
[03:16:50] build workers 3/10: load 44.3974609375 >= 24: holding
[03:17:25] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:17:25] qa workers 3/3: at the cap, not starting
[03:17:25] qa workers 3/3: at the cap, not starting
[03:17:25] build workers 3/10: load 36.32763671875 >= 24: holding
[03:18:00] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:18:00] qa workers 3/3: at the cap, not starting
[03:18:00] qa workers 3/3: at the cap, not starting
[03:18:01] build workers 3/10: load 32.45654296875 >= 24: holding
[03:18:36] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:18:36] qa workers 3/3: at the cap, not starting
[03:18:36] qa workers 3/3: at the cap, not starting
[03:18:36] build workers 3/10: load 26.23388671875 >= 24: holding
[03:19:11] tick — Ready=1 Building=3 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:19:11] qa workers 3/3: at the cap, not starting
[03:19:11] qa workers 3/3: at the cap, not starting
[03:19:11] build workers 3/10, load 21.365234375 < 24: starting #4
[03:19:20] dispatch lane=build issue=#254 pid=67338 claim=ToanMobile
[03:19:53] reaped stale lock + swept assignee on #248 (pid=3668)
[03:19:57] tick — Ready=0 Building=4 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223 67338:254) b_workers=4/10 q_idle=0(#248 +78016:255 44331:249) q_workers=2/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:20:03] dispatch lane=qa issue=#248 pid=33289 claim=ToanMobile
[03:20:37] tick — Ready=0 Building=4 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223 67338:254) b_workers=4/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:20:37] qa workers 3/3: at the cap, not starting
[03:20:37] qa workers 3/3: at the cap, not starting
[03:21:12] tick — Ready=0 Building=4 QA=8 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223 67338:254) b_workers=4/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:21:12] qa workers 3/3: at the cap, not starting
[03:21:12] qa workers 3/3: at the cap, not starting
[03:21:49] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 25181:223 67338:254) b_workers=4/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:21:49] qa workers 3/3: at the cap, not starting
[03:21:49] qa workers 3/3: at the cap, not starting
[03:22:22] reaped stale lock + swept assignee on #223 (pid=25181)
[03:22:28] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:22:28] qa workers 3/3: at the cap, not starting
[03:22:28] qa workers 3/3: at the cap, not starting
[03:23:03] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:23:03] qa workers 3/3: at the cap, not starting
[03:23:03] qa workers 3/3: at the cap, not starting
[03:23:38] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:23:38] qa workers 3/3: at the cap, not starting
[03:23:38] qa workers 3/3: at the cap, not starting
[03:24:14] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:24:14] qa workers 3/3: at the cap, not starting
[03:24:14] qa workers 3/3: at the cap, not starting
[03:24:50] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:24:50] qa workers 3/3: at the cap, not starting
[03:24:50] qa workers 3/3: at the cap, not starting
[03:25:25] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:25:25] qa workers 3/3: at the cap, not starting
[03:25:25] qa workers 3/3: at the cap, not starting
[03:26:00] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:26:00] qa workers 3/3: at the cap, not starting
[03:26:00] qa workers 3/3: at the cap, not starting
kept card 255: live qa lane (pid 78016) holds it
kept card 254: live build lane (pid 67338) holds it
kept card 247: live build lane (pid 85239) holds it
kept card 249: live qa lane (pid 44331) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[03:26:36] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:26:36] qa workers 3/3: at the cap, not starting
[03:26:36] qa workers 3/3: at the cap, not starting
[03:27:12] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:27:12] qa workers 3/3: at the cap, not starting
[03:27:12] qa workers 3/3: at the cap, not starting
[03:27:47] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:27:47] qa workers 3/3: at the cap, not starting
[03:27:47] qa workers 3/3: at the cap, not starting
[03:28:21] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:28:21] qa workers 3/3: at the cap, not starting
[03:28:21] qa workers 3/3: at the cap, not starting
[03:28:55] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:28:55] qa workers 3/3: at the cap, not starting
[03:28:55] qa workers 3/3: at the cap, not starting
[03:29:31] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:29:31] qa workers 3/3: at the cap, not starting
[03:29:31] qa workers 3/3: at the cap, not starting
[03:30:07] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:30:07] qa workers 3/3: at the cap, not starting
[03:30:07] qa workers 3/3: at the cap, not starting
[03:30:42] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:30:42] qa workers 3/3: at the cap, not starting
[03:30:42] qa workers 3/3: at the cap, not starting
[03:31:17] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:31:17] qa workers 3/3: at the cap, not starting
[03:31:18] qa workers 3/3: at the cap, not starting
[03:31:54] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:31:54] qa workers 3/3: at the cap, not starting
[03:31:54] qa workers 3/3: at the cap, not starting
[03:32:30] tick — Ready=0 Building=3 QA=9 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:32:30] qa workers 3/3: at the cap, not starting
[03:32:30] qa workers 3/3: at the cap, not starting
[03:33:04] tick — Ready=0 Building=2 QA=10 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=3/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:33:04] qa workers 3/3: at the cap, not starting
[03:33:04] qa workers 3/3: at the cap, not starting
[03:33:38] reaped stale lock + swept assignee on #251 (pid=48868)
[03:33:42] tick — Ready=0 Building=2 QA=10 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:33:42] qa workers 3/3: at the cap, not starting
[03:33:42] qa workers 3/3: at the cap, not starting
[03:34:17] tick — Ready=0 Building=2 QA=10 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:34:17] qa workers 3/3: at the cap, not starting
[03:34:17] qa workers 3/3: at the cap, not starting
[03:34:52] tick — Ready=0 Building=2 QA=10 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:34:52] qa workers 3/3: at the cap, not starting
[03:34:52] qa workers 3/3: at the cap, not starting
[03:35:27] tick — Ready=0 Building=2 QA=10 Review=0 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +78016:255 44331:249) q_workers=3/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
[03:35:27] qa workers 3/3: at the cap, not starting
[03:35:27] qa workers 3/3: at the cap, not starting
kept card 255: live qa lane (pid 78016) holds it
kept card 247: live build lane (pid 85239) holds it
[03:36:01] 💀 zombie qa worker on #255 (pid=78016) — card moved to 'Review'; killing
kept card 249: live qa lane (pid 44331) holds it
[03:36:05] tick — Ready=0 Building=2 QA=9 Review=1 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +44331:249) q_workers=2/3 r_idle=1(#252) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 254: live build lane (pid 67338) holds it
[03:36:11] dispatch lane=review issue=#255 pid=92971 claim=ToanMobile
[03:36:16] dispatch lane=qa issue=#251 pid=95314 claim=ToanMobile
[03:36:50] tick — Ready=0 Building=2 QA=9 Review=1 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +44331:249 95314:251) q_workers=3/3 r_idle=0(#255) r_workers=1/3 waiting_on_you=0
[03:36:51] qa workers 3/3: at the cap, not starting
[03:36:51] qa workers 3/3: at the cap, not starting
[03:37:25] 💀 zombie qa worker on #249 (pid=44331) — card moved to 'Review'; killing
[03:37:29] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251) q_workers=2/3 r_idle=0(#255) r_workers=1/3 waiting_on_you=0
[03:37:35] dispatch lane=review issue=#249 pid=59108 claim=ToanMobile
[03:37:41] dispatch lane=qa issue=#250 pid=61139 claim=ToanMobile
[03:38:19] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:38:19] review workers 2/3: load 42.55810546875 >= 24: holding
[03:38:19] qa workers 3/3: at the cap, not starting
[03:38:19] qa workers 3/3: at the cap, not starting
[03:38:57] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:38:57] review workers 2/3: load 68.6552734375 >= 24: holding
[03:38:57] qa workers 3/3: at the cap, not starting
[03:38:57] qa workers 3/3: at the cap, not starting
[03:39:35] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:39:35] review workers 2/3: load 57.455078125 >= 24: holding
[03:39:35] qa workers 3/3: at the cap, not starting
[03:39:35] qa workers 3/3: at the cap, not starting
[03:40:15] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:40:15] review workers 2/3: load 56.2548828125 >= 24: holding
[03:40:15] qa workers 3/3: at the cap, not starting
[03:40:15] qa workers 3/3: at the cap, not starting
[03:40:53] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:40:53] review workers 2/3: load 77.5888671875 >= 24: holding
[03:40:54] qa workers 3/3: at the cap, not starting
[03:40:54] qa workers 3/3: at the cap, not starting
[03:41:31] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:41:31] review workers 2/3: load 79.763671875 >= 24: holding
[03:41:31] qa workers 3/3: at the cap, not starting
[03:41:31] qa workers 3/3: at the cap, not starting
[03:42:06] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:42:06] review workers 2/3: load 61.685546875 >= 24: holding
[03:42:06] qa workers 3/3: at the cap, not starting
[03:42:06] qa workers 3/3: at the cap, not starting
[03:42:42] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:42:42] review workers 2/3: load 48.3037109375 >= 24: holding
[03:42:42] qa workers 3/3: at the cap, not starting
[03:42:42] qa workers 3/3: at the cap, not starting
[03:43:16] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:43:16] review workers 2/3: load 36.95068359375 >= 24: holding
[03:43:16] qa workers 3/3: at the cap, not starting
[03:43:16] qa workers 3/3: at the cap, not starting
[03:43:52] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#251 +85239:247 67338:254) b_workers=2/10 q_idle=0(#248 +95314:251 61139:250) q_workers=3/3 r_idle=0(#255 +59108:249) r_workers=2/3 waiting_on_you=0
[03:43:52] review workers 2/3: load 31.576171875 >= 24: holding
[03:43:52] qa workers 3/3: at the cap, not starting
[03:43:52] qa workers 3/3: at the cap, not starting
[03:44:09] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[03:44:10] adopted live build worker on #247 (pid=85239) from the previous run
[03:44:10] adopted live qa worker on #248 (pid=33289) from the previous run
[03:44:10] adopted live review worker on #249 (pid=59108) from the previous run
[03:44:10] adopted live qa worker on #250 (pid=61139) from the previous run
[03:44:10] adopted live qa worker on #251 (pid=95314) from the previous run
[03:44:10] adopted live build worker on #254 (pid=67338) from the previous run
[03:44:10] adopted live review worker on #255 (pid=92971) from the previous run
[03:44:10] 🛑 refusing to start: runner pid 52223 of board agent-workbench is still running
[03:44:17] initial Ready count: 0
kept card 254: live build lane (pid 67338) holds it
kept card 248: live qa lane (pid 33289) holds it
[03:44:28] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:44:28] review workers: gates 18 >= 6: holding
[03:44:28] qa workers 3/3: at the cap, not starting
[03:44:28] qa workers 3/3: at the cap, not starting
kept card 250: live qa lane (pid 61139) holds it
[03:45:04] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:45:04] review workers: gates 8 >= 6: holding
[03:45:04] qa workers 3/3: at the cap, not starting
[03:45:04] qa workers 3/3: at the cap, not starting
[03:45:39] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:45:39] review workers: gates 11 >= 6: holding
[03:45:39] qa workers 3/3: at the cap, not starting
[03:45:39] qa workers 3/3: at the cap, not starting
[03:46:14] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:46:14] review workers: gates 7 >= 6: holding
[03:46:14] qa workers 3/3: at the cap, not starting
[03:46:14] qa workers 3/3: at the cap, not starting
[03:46:49] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:46:49] review workers: gates 13 >= 6: holding
[03:46:49] qa workers 3/3: at the cap, not starting
[03:46:49] qa workers 3/3: at the cap, not starting
[03:47:24] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:47:24] qa workers 3/3: at the cap, not starting
[03:47:24] qa workers 3/3: at the cap, not starting
[03:47:58] tick — Ready=0 Building=2 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=2/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:48:04] dispatch lane=qa issue=#248 pid=54851 claim=ToanMobile
[03:48:39] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:48:39] review workers: gates 6 >= 6: holding
[03:48:39] qa workers 3/3: at the cap, not starting
[03:48:39] qa workers 3/3: at the cap, not starting
[03:49:14] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:49:14] review workers: gates 13 >= 6: holding
[03:49:14] qa workers 3/3: at the cap, not starting
[03:49:14] qa workers 3/3: at the cap, not starting
[03:49:50] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:49:50] review workers: gates 15 >= 6: holding
[03:49:50] qa workers 3/3: at the cap, not starting
[03:49:50] qa workers 3/3: at the cap, not starting
[03:50:24] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:50:24] review workers: gates 13 >= 6: holding
[03:50:24] qa workers 3/3: at the cap, not starting
[03:50:24] qa workers 3/3: at the cap, not starting
[03:50:59] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:50:59] review workers: gates 9 >= 6: holding
[03:50:59] qa workers 3/3: at the cap, not starting
[03:50:59] qa workers 3/3: at the cap, not starting
[03:51:34] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:51:34] review workers: gates 10 >= 6: holding
[03:51:34] qa workers 3/3: at the cap, not starting
[03:51:34] qa workers 3/3: at the cap, not starting
[03:52:09] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:52:09] review workers: gates 9 >= 6: holding
[03:52:09] qa workers 3/3: at the cap, not starting
[03:52:09] qa workers 3/3: at the cap, not starting
[03:52:43] tick — Ready=0 Building=1 QA=9 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250 95314:251) q_workers=3/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:52:44] review workers: gates 6 >= 6: holding
[03:52:44] qa workers 3/3: at the cap, not starting
[03:52:44] qa workers 3/3: at the cap, not starting
[03:53:17] 💀 zombie qa worker on #251 (pid=95314) — card moved to 'Review'; killing
[03:53:21] tick — Ready=0 Building=1 QA=8 Review=3 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=2/10 q_idle=0(#248 +61139:250) q_workers=2/3 r_idle=0(#249 +92971:255) r_workers=2/3 waiting_on_you=0
[03:53:22] review workers: gates 7 >= 6: holding
[03:53:22] qa workers: gates 7 >= 6: holding
[03:53:22] qa workers: gates 7 >= 6: holding
[03:53:54] reaped stale lock + swept assignee on #247 (pid=85239)
[03:53:58] 💀 zombie review worker on #255 (pid=92971) — card moved to 'Done'; killing
[03:54:08] tick — Ready=0 Building=1 QA=8 Review=2 Blocked=10 lanes: b_idle=0(#247 +67338:254) b_workers=1/10 q_idle=0(#248 +61139:250) q_workers=2/3 r_idle=0(#249) r_workers=1/3 waiting_on_you=0
[03:54:13] dispatch lane=review issue=#251 pid=99308 claim=ToanMobile
[03:54:18] dispatch lane=qa issue=#237 pid=2848 claim=ToanMobile
[03:54:51] reaped stale lock + swept assignee on #248 (pid=54851)
kept card 250: live qa lane (pid 61139) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[03:54:56] tick — Ready=1 Building=1 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#247 +67338:254) b_workers=1/10 q_idle=0(#248 +61139:250 2848:237) q_workers=2/3 r_idle=0(#249 +99308:251) r_workers=2/3 waiting_on_you=0
[03:55:01] dispatch lane=review issue=#248 pid=84468 claim=ToanMobile
kept card 248: live review lane (pid 84468) holds it
kept card 249: live review lane (pid 59108) holds it
[03:55:07] dispatch lane=qa issue=#223 pid=89657 claim=ToanMobile
[03:55:07] build workers 1/10, load 8.705078125 < 24: starting #2
[03:55:27] dispatch lane=build issue=#240 pid=4665 claim=ToanMobile
[03:56:03] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:56:03] review workers 3/3: at the cap, not starting
[03:56:03] qa workers 3/3: at the cap, not starting
[03:56:03] qa workers 3/3: at the cap, not starting
[03:56:38] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:56:38] review workers 3/3: at the cap, not starting
[03:56:38] qa workers 3/3: at the cap, not starting
[03:56:38] qa workers 3/3: at the cap, not starting
[03:57:13] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:57:13] review workers 3/3: at the cap, not starting
[03:57:13] qa workers 3/3: at the cap, not starting
[03:57:13] qa workers 3/3: at the cap, not starting
[03:57:47] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:57:47] review workers 3/3: at the cap, not starting
[03:57:47] qa workers 3/3: at the cap, not starting
[03:57:47] qa workers 3/3: at the cap, not starting
[03:58:24] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:58:24] review workers 3/3: at the cap, not starting
[03:58:24] qa workers 3/3: at the cap, not starting
[03:58:24] qa workers 3/3: at the cap, not starting
[03:58:59] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:58:59] review workers 3/3: at the cap, not starting
[03:58:59] qa workers 3/3: at the cap, not starting
[03:58:59] qa workers 3/3: at the cap, not starting
[03:59:34] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[03:59:34] review workers 3/3: at the cap, not starting
[03:59:34] qa workers 3/3: at the cap, not starting
[03:59:34] qa workers 3/3: at the cap, not starting
[04:00:09] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:00:09] review workers 3/3: at the cap, not starting
[04:00:09] qa workers 3/3: at the cap, not starting
[04:00:09] qa workers 3/3: at the cap, not starting
[04:00:43] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:00:43] review workers 3/3: at the cap, not starting
[04:00:43] qa workers 3/3: at the cap, not starting
[04:00:43] qa workers 3/3: at the cap, not starting
[04:01:18] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:01:18] review workers 3/3: at the cap, not starting
[04:01:18] qa workers 3/3: at the cap, not starting
[04:01:18] qa workers 3/3: at the cap, not starting
[04:01:53] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:01:53] review workers 3/3: at the cap, not starting
[04:01:53] qa workers 3/3: at the cap, not starting
[04:01:53] qa workers 3/3: at the cap, not starting
[04:02:28] tick — Ready=0 Building=2 QA=7 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +61139:250 2848:237) q_workers=3/3 r_idle=0(#249 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:02:28] review workers 3/3: at the cap, not starting
[04:02:28] qa workers 3/3: at the cap, not starting
[04:02:28] qa workers 3/3: at the cap, not starting
[04:03:03] 💀 zombie qa worker on #250 (pid=61139) — card moved to 'Review'; killing
[04:03:06] 💀 zombie review worker on #249 (pid=59108) — card moved to 'Done'; killing
[04:03:14] tick — Ready=0 Building=2 QA=6 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +2848:237) q_workers=2/3 r_idle=0(#_ +99308:251 84468:248) r_workers=2/3 waiting_on_you=0
[04:03:19] dispatch lane=review issue=#250 pid=38583 claim=ToanMobile
[04:03:20] qa workers: gates 6 >= 6: holding
[04:03:20] qa workers: gates 6 >= 6: holding
[04:03:54] tick — Ready=0 Building=2 QA=6 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +2848:237) q_workers=2/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:03:54] review workers 3/3: at the cap, not starting
[04:03:54] qa workers: gates 6 >= 6: holding
[04:03:54] qa workers: gates 6 >= 6: holding
[04:04:29] tick — Ready=0 Building=2 QA=6 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +2848:237) q_workers=2/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:04:29] review workers 3/3: at the cap, not starting
[04:04:29] qa workers: gates 11 >= 6: holding
[04:04:29] qa workers: gates 12 >= 6: holding
[04:05:04] tick — Ready=0 Building=2 QA=6 Review=3 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +2848:237) q_workers=2/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:05:04] review workers 3/3: at the cap, not starting
[04:05:04] qa workers: gates 14 >= 6: holding
[04:05:04] qa workers: gates 14 >= 6: holding
kept card 251: live review lane (pid 99308) holds it
kept card 254: live build lane (pid 67338) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live build lane (pid 4665) holds it
kept card 250: live review lane (pid 38583) holds it
kept card 237: live qa lane (pid 2848) holds it
[04:05:38] reaped stale lock + swept assignee on #223 (pid=89657)
[04:05:42] tick — Ready=0 Building=2 QA=5 Review=4 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#223 +2848:237) q_workers=1/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:05:42] review workers 3/3: at the cap, not starting
[04:05:48] dispatch lane=qa issue=#202 pid=78777 claim=ToanMobile
[04:06:23] tick — Ready=0 Building=2 QA=5 Review=4 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=2/10 q_idle=0(#202 +2848:237) q_workers=2/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:06:23] review workers 3/3: at the cap, not starting
[04:06:28] dispatch lane=qa issue=#247 pid=95485 claim=ToanMobile
[04:07:01] reaped stale lock + swept assignee on #240 (pid=4665)
[04:07:06] tick — Ready=0 Building=1 QA=6 Review=4 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=1/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:07:06] review workers 3/3: at the cap, not starting
[04:07:06] qa workers 3/3: at the cap, not starting
[04:07:06] qa workers 3/3: at the cap, not starting
[04:07:41] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=1/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:07:41] review workers 3/3: at the cap, not starting
[04:07:41] qa workers 3/3: at the cap, not starting
[04:07:41] qa workers 3/3: at the cap, not starting
[04:08:16] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=0(#240 +67338:254) b_workers=1/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:08:16] review workers 3/3: at the cap, not starting
[04:08:16] qa workers 3/3: at the cap, not starting
[04:08:16] qa workers 3/3: at the cap, not starting
[04:08:49] reaped stale lock + swept assignee on #254 (pid=67338)
[04:08:53] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:08:53] review workers 3/3: at the cap, not starting
[04:08:53] qa workers 3/3: at the cap, not starting
[04:08:53] qa workers 3/3: at the cap, not starting
[04:09:27] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:09:27] review workers 3/3: at the cap, not starting
[04:09:27] qa workers 3/3: at the cap, not starting
[04:09:27] qa workers 3/3: at the cap, not starting
[04:10:02] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:10:02] review workers 3/3: at the cap, not starting
[04:10:02] qa workers 3/3: at the cap, not starting
[04:10:02] qa workers 3/3: at the cap, not starting
[04:10:37] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:10:37] review workers 3/3: at the cap, not starting
[04:10:37] qa workers 3/3: at the cap, not starting
[04:10:37] qa workers 3/3: at the cap, not starting
[04:11:11] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:11:11] review workers 3/3: at the cap, not starting
[04:11:11] qa workers 3/3: at the cap, not starting
[04:11:11] qa workers 3/3: at the cap, not starting
[04:11:46] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:11:46] review workers 3/3: at the cap, not starting
[04:11:46] qa workers 3/3: at the cap, not starting
[04:11:46] qa workers 3/3: at the cap, not starting
[04:12:20] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:12:20] review workers 3/3: at the cap, not starting
[04:12:20] qa workers 3/3: at the cap, not starting
[04:12:20] qa workers 3/3: at the cap, not starting
[04:12:55] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:12:55] review workers 3/3: at the cap, not starting
[04:12:55] qa workers 3/3: at the cap, not starting
[04:12:55] qa workers 3/3: at the cap, not starting
[04:13:30] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:13:30] review workers 3/3: at the cap, not starting
[04:13:30] qa workers 3/3: at the cap, not starting
[04:13:30] qa workers 3/3: at the cap, not starting
[04:14:04] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:14:04] review workers 3/3: at the cap, not starting
[04:14:04] qa workers 3/3: at the cap, not starting
[04:14:04] qa workers 3/3: at the cap, not starting
[04:14:38] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:14:38] review workers 3/3: at the cap, not starting
[04:14:38] qa workers 3/3: at the cap, not starting
[04:14:38] qa workers 3/3: at the cap, not starting
[04:15:13] tick — Ready=0 Building=0 QA=7 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#202 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:15:13] review workers 3/3: at the cap, not starting
[04:15:13] qa workers 3/3: at the cap, not starting
[04:15:13] qa workers 3/3: at the cap, not starting
kept card 251: live review lane (pid 99308) holds it
kept card 202: live qa lane (pid 78777) holds it
[04:15:49] 💀 zombie qa worker on #202 (pid=78777) — card moved to 'Review'; killing
[04:15:53] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#_ +2848:237 95485:247) q_workers=2/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:15:53] review workers 3/3: at the cap, not starting
[04:15:58] dispatch lane=qa issue=#254 pid=90003 claim=ToanMobile
[04:16:32] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:16:32] review workers 3/3: at the cap, not starting
[04:16:32] qa workers 3/3: at the cap, not starting
[04:16:32] qa workers 3/3: at the cap, not starting
[04:17:07] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:17:07] review workers 3/3: at the cap, not starting
[04:17:07] qa workers 3/3: at the cap, not starting
[04:17:07] qa workers 3/3: at the cap, not starting
[04:17:41] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:17:41] review workers 3/3: at the cap, not starting
[04:17:41] qa workers 3/3: at the cap, not starting
[04:17:41] qa workers 3/3: at the cap, not starting
[04:18:16] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:18:16] review workers 3/3: at the cap, not starting
[04:18:16] qa workers 3/3: at the cap, not starting
[04:18:16] qa workers 3/3: at the cap, not starting
[04:18:52] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:18:52] review workers 3/3: at the cap, not starting
[04:18:52] qa workers 3/3: at the cap, not starting
[04:18:52] qa workers 3/3: at the cap, not starting
[04:19:27] tick — Ready=0 Building=0 QA=6 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:19:27] review workers 3/3: at the cap, not starting
[04:19:27] qa workers 3/3: at the cap, not starting
[04:19:27] qa workers 3/3: at the cap, not starting
[04:20:02] reaped stale lock + swept assignee on #250 (pid=38583)
[04:20:13] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=2/3 waiting_on_you=0
[04:20:13] review workers: gates 12 >= 6: holding
[04:20:13] qa workers 3/3: at the cap, not starting
[04:20:13] qa workers 3/3: at the cap, not starting
[04:20:48] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=2/3 waiting_on_you=0
[04:20:48] review workers: gates 9 >= 6: holding
[04:20:48] qa workers 3/3: at the cap, not starting
[04:20:48] qa workers 3/3: at the cap, not starting
[04:21:23] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=2/3 waiting_on_you=0
[04:21:23] review workers: gates 9 >= 6: holding
[04:21:23] qa workers 3/3: at the cap, not starting
[04:21:23] qa workers 3/3: at the cap, not starting
[04:21:57] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#250 +99308:251 84468:248) r_workers=2/3 waiting_on_you=0
[04:22:02] dispatch lane=review issue=#223 pid=65579 claim=ToanMobile
[04:22:02] qa workers 3/3: at the cap, not starting
[04:22:02] qa workers 3/3: at the cap, not starting
[04:22:37] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:22:37] review workers 3/3: at the cap, not starting
[04:22:37] qa workers 3/3: at the cap, not starting
[04:22:37] qa workers 3/3: at the cap, not starting
[04:23:11] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:23:11] review workers 3/3: at the cap, not starting
[04:23:11] qa workers 3/3: at the cap, not starting
[04:23:11] qa workers 3/3: at the cap, not starting
[04:23:46] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:23:46] review workers 3/3: at the cap, not starting
[04:23:46] qa workers 3/3: at the cap, not starting
[04:23:46] qa workers 3/3: at the cap, not starting
[04:24:21] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:24:21] review workers 3/3: at the cap, not starting
[04:24:21] qa workers 3/3: at the cap, not starting
[04:24:21] qa workers 3/3: at the cap, not starting
[04:24:55] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:24:55] review workers 3/3: at the cap, not starting
[04:24:55] qa workers 3/3: at the cap, not starting
[04:24:55] qa workers 3/3: at the cap, not starting
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[04:25:29] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:25:29] review workers 3/3: at the cap, not starting
[04:25:29] qa workers 3/3: at the cap, not starting
[04:25:29] qa workers 3/3: at the cap, not starting
kept card 223: live review lane (pid 65579) holds it
kept card 248: live review lane (pid 84468) holds it
kept card 254: live qa lane (pid 90003) holds it
kept card 237: live qa lane (pid 2848) holds it
[04:26:05] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:26:05] review workers 3/3: at the cap, not starting
[04:26:05] qa workers 3/3: at the cap, not starting
[04:26:05] qa workers 3/3: at the cap, not starting
[04:26:39] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:26:39] review workers 3/3: at the cap, not starting
[04:26:39] qa workers 3/3: at the cap, not starting
[04:26:39] qa workers 3/3: at the cap, not starting
[04:27:13] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:27:13] review workers 3/3: at the cap, not starting
[04:27:13] qa workers 3/3: at the cap, not starting
[04:27:13] qa workers 3/3: at the cap, not starting
[04:27:48] tick — Ready=0 Building=0 QA=6 Review=4 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 95485:247) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:27:48] review workers 3/3: at the cap, not starting
[04:27:48] qa workers 3/3: at the cap, not starting
[04:27:48] qa workers 3/3: at the cap, not starting
[04:28:21] reaped stale lock + swept assignee on #247 (pid=95485)
[04:28:25] tick — Ready=0 Building=0 QA=5 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237) q_workers=2/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:28:25] review workers 3/3: at the cap, not starting
[04:28:31] dispatch lane=qa issue=#240 pid=26077 claim=ToanMobile
[04:29:06] tick — Ready=0 Building=0 QA=5 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:29:06] review workers 3/3: at the cap, not starting
[04:29:06] qa workers 3/3: at the cap, not starting
[04:29:06] qa workers 3/3: at the cap, not starting
[04:29:40] tick — Ready=0 Building=0 QA=5 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:29:40] review workers 3/3: at the cap, not starting
[04:29:40] qa workers 3/3: at the cap, not starting
[04:29:40] qa workers 3/3: at the cap, not starting
[04:30:14] tick — Ready=0 Building=0 QA=5 Review=5 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223 +99308:251 84468:248) r_workers=3/3 waiting_on_you=0
[04:30:14] review workers 3/3: at the cap, not starting
[04:30:14] qa workers 3/3: at the cap, not starting
[04:30:14] qa workers 3/3: at the cap, not starting
[04:30:47] reaped stale lock + swept assignee on #248 (pid=84468)
[04:30:51] 💀 zombie review worker on #251 (pid=99308) — card moved to 'Done'; killing
[04:31:01] tick — Ready=0 Building=0 QA=5 Review=3 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[04:31:01] review workers: gates 21 >= 6: holding
[04:31:01] qa workers 3/3: at the cap, not starting
[04:31:01] qa workers 3/3: at the cap, not starting
[04:31:38] tick — Ready=0 Building=0 QA=5 Review=3 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[04:31:38] review workers: gates 12 >= 6: holding
[04:31:38] qa workers 3/3: at the cap, not starting
[04:31:38] qa workers 3/3: at the cap, not starting
[04:32:12] tick — Ready=0 Building=0 QA=5 Review=3 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#223) r_workers=1/3 waiting_on_you=0
[04:32:17] dispatch lane=review issue=#202 pid=86693 claim=ToanMobile
[04:32:17] qa workers 3/3: at the cap, not starting
[04:32:17] qa workers 3/3: at the cap, not starting
[04:32:52] 💀 zombie review worker on #223 (pid=65579) — card moved to 'Done'; killing
[04:33:01] tick — Ready=0 Building=0 QA=5 Review=2 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#_ +86693:202) r_workers=1/3 waiting_on_you=0
[04:33:07] dispatch lane=review issue=#247 pid=12009 claim=ToanMobile
[04:33:07] qa workers 3/3: at the cap, not starting
[04:33:07] qa workers 3/3: at the cap, not starting
[04:33:41] tick — Ready=0 Building=0 QA=5 Review=2 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247 +86693:202) r_workers=2/3 waiting_on_you=0
[04:33:41] qa workers 3/3: at the cap, not starting
[04:33:41] qa workers 3/3: at the cap, not starting
[04:34:15] 💀 zombie review worker on #202 (pid=86693) — card moved to 'Ready'; killing
[04:34:19] tick — Ready=1 Building=0 QA=5 Review=1 Blocked=9 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:34:19] qa workers 3/3: at the cap, not starting
[04:34:19] qa workers 3/3: at the cap, not starting
[04:34:29] preflight hold/unclear for #202: no `## Acceptance Criteria` bullets — not dispatched, card to Blocked
[04:35:08] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:35:08] review workers: gates 17 >= 6: holding
[04:35:08] qa workers 3/3: at the cap, not starting
[04:35:08] qa workers 3/3: at the cap, not starting
[04:35:44] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:35:44] review workers: gates 16 >= 6: holding
[04:35:45] qa workers 3/3: at the cap, not starting
[04:35:45] qa workers 3/3: at the cap, not starting
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 247: live review lane (pid 12009) holds it
kept card 237: live qa lane (pid 2848) holds it
✔ đã gỡ /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-251-review
[04:36:19] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:36:19] review workers: gates 6 >= 6: holding
[04:36:19] qa workers 3/3: at the cap, not starting
[04:36:19] qa workers 3/3: at the cap, not starting
[04:36:53] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:36:53] qa workers 3/3: at the cap, not starting
[04:36:53] qa workers 3/3: at the cap, not starting
[04:37:27] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:37:27] qa workers 3/3: at the cap, not starting
[04:37:27] qa workers 3/3: at the cap, not starting
[04:38:02] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:38:02] qa workers 3/3: at the cap, not starting
[04:38:02] qa workers 3/3: at the cap, not starting
[04:38:38] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:38:38] review workers: gates 20 >= 6: holding
[04:38:38] qa workers 3/3: at the cap, not starting
[04:38:38] qa workers 3/3: at the cap, not starting
[04:39:13] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:39:13] review workers: gates 12 >= 6: holding
[04:39:13] qa workers 3/3: at the cap, not starting
[04:39:13] qa workers 3/3: at the cap, not starting
[04:39:47] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:39:47] review workers: gates 9 >= 6: holding
[04:39:47] qa workers 3/3: at the cap, not starting
[04:39:47] qa workers 3/3: at the cap, not starting
[04:40:22] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:40:22] review workers: gates 8 >= 6: holding
[04:40:22] qa workers 3/3: at the cap, not starting
[04:40:22] qa workers 3/3: at the cap, not starting
[04:40:57] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:40:57] review workers: gates 8 >= 6: holding
[04:40:57] qa workers 3/3: at the cap, not starting
[04:40:57] qa workers 3/3: at the cap, not starting
[04:41:34] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:41:34] review workers: gates 17 >= 6: holding
[04:41:34] qa workers 3/3: at the cap, not starting
[04:41:34] qa workers 3/3: at the cap, not starting
[04:42:10] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:42:10] review workers: gates 9 >= 6: holding
[04:42:10] qa workers 3/3: at the cap, not starting
[04:42:10] qa workers 3/3: at the cap, not starting
[04:42:44] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:42:44] review workers: gates 10 >= 6: holding
[04:42:44] qa workers 3/3: at the cap, not starting
[04:42:44] qa workers 3/3: at the cap, not starting
[04:43:18] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:43:18] qa workers 3/3: at the cap, not starting
[04:43:18] qa workers 3/3: at the cap, not starting
[04:43:52] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:43:52] review workers: gates 6 >= 6: holding
[04:43:52] qa workers 3/3: at the cap, not starting
[04:43:52] qa workers 3/3: at the cap, not starting
[04:44:26] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:44:26] qa workers 3/3: at the cap, not starting
[04:44:26] qa workers 3/3: at the cap, not starting
[04:45:01] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:45:01] qa workers 3/3: at the cap, not starting
[04:45:01] qa workers 3/3: at the cap, not starting
[04:45:35] tick — Ready=0 Building=0 QA=5 Review=1 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +2848:237 26077:240) q_workers=3/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:45:35] qa workers 3/3: at the cap, not starting
[04:45:35] qa workers 3/3: at the cap, not starting
[04:46:11] tick — Ready=0 Building=0 QA=4 Review=2 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +26077:240) q_workers=2/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:46:11] review workers: gates 19 >= 6: holding
[04:46:11] qa workers: gates 16 >= 6: holding
[04:46:12] qa workers: gates 17 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[04:46:45] reaped stale lock + swept assignee on #237 (pid=2848)
[04:46:49] tick — Ready=0 Building=0 QA=4 Review=2 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +26077:240) q_workers=2/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:46:49] review workers: gates 10 >= 6: holding
[04:46:49] qa workers: gates 10 >= 6: holding
[04:46:49] qa workers: gates 10 >= 6: holding
[04:47:25] tick — Ready=0 Building=0 QA=4 Review=2 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#254 +26077:240) q_workers=2/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:47:25] review workers: gates 17 >= 6: holding
[04:47:25] qa workers: gates 18 >= 6: holding
[04:47:25] qa workers: gates 18 >= 6: holding
[04:47:59] 💀 zombie qa worker on #254 (pid=90003) — card moved to 'Review'; killing
[04:48:03] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#_ +26077:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[04:48:08] dispatch lane=review issue=#254 pid=11269 claim=ToanMobile
[04:48:13] dispatch lane=qa issue=#227 pid=13636 claim=ToanMobile
[04:48:47] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=2/3 waiting_on_you=0
[04:48:53] dispatch lane=review issue=#237 pid=58887 claim=ToanMobile
[04:48:59] dispatch lane=qa issue=#229 pid=61925 claim=ToanMobile
[04:49:35] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254 58887:237) r_workers=3/3 waiting_on_you=0
[04:49:35] review workers 3/3: at the cap, not starting
[04:49:35] qa workers 3/3: at the cap, not starting
[04:49:35] qa workers 3/3: at the cap, not starting
[04:50:09] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254 58887:237) r_workers=3/3 waiting_on_you=0
[04:50:09] review workers 3/3: at the cap, not starting
[04:50:09] qa workers 3/3: at the cap, not starting
[04:50:09] qa workers 3/3: at the cap, not starting
[04:50:43] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254 58887:237) r_workers=3/3 waiting_on_you=0
[04:50:43] review workers 3/3: at the cap, not starting
[04:50:43] qa workers 3/3: at the cap, not starting
[04:50:43] qa workers 3/3: at the cap, not starting
[04:51:17] tick — Ready=0 Building=0 QA=3 Review=3 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254 58887:237) r_workers=3/3 waiting_on_you=0
[04:51:17] review workers 3/3: at the cap, not starting
[04:51:17] qa workers 3/3: at the cap, not starting
[04:51:17] qa workers 3/3: at the cap, not starting
[04:51:52] tick — Ready=1 Building=0 QA=3 Review=2 Blocked=10 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=2/3 waiting_on_you=0
[04:51:52] qa workers 3/3: at the cap, not starting
[04:51:52] qa workers 3/3: at the cap, not starting
[04:52:06] preflight sequence/overlap for #237: open PRs touch the same files — build after them — not dispatched, card to Blocked
[04:52:44] reaped stale lock + swept assignee on #247 (pid=12009)
[04:52:48] tick — Ready=1 Building=0 QA=3 Review=1 Blocked=11 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:52:48] review workers: gates 15 >= 6: holding
[04:52:49] qa workers 3/3: at the cap, not starting
[04:52:49] qa workers 3/3: at the cap, not starting
[04:52:49] build workers: gates 15 >= 6: holding
[04:53:23] tick — Ready=1 Building=0 QA=3 Review=1 Blocked=11 lanes: b_idle=1(#240) b_workers=0/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:53:23] qa workers 3/3: at the cap, not starting
[04:53:24] qa workers 3/3: at the cap, not starting
[04:53:38] dispatch lane=build issue=#247 pid=95287 claim=ToanMobile
[04:54:12] tick — Ready=0 Building=1 QA=3 Review=1 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:54:12] review workers: gates 6 >= 6: holding
[04:54:12] qa workers 3/3: at the cap, not starting
[04:54:12] qa workers 3/3: at the cap, not starting
[04:54:47] tick — Ready=0 Building=1 QA=3 Review=1 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:54:47] review workers: gates 6 >= 6: holding
[04:54:47] qa workers 3/3: at the cap, not starting
[04:54:47] qa workers 3/3: at the cap, not starting
[04:55:21] tick — Ready=0 Building=1 QA=3 Review=1 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:55:21] qa workers 3/3: at the cap, not starting
[04:55:21] qa workers 3/3: at the cap, not starting
[04:55:55] tick — Ready=0 Building=1 QA=3 Review=1 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +26077:240 61925:229) q_workers=3/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:55:55] review workers: gates 7 >= 6: holding
[04:55:55] qa workers 3/3: at the cap, not starting
[04:55:55] qa workers 3/3: at the cap, not starting
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live qa lane (pid 26077) holds it
[04:56:30] 💀 zombie qa worker on #240 (pid=26077) — card moved to 'Review'; killing
kept card 247: live build lane (pid 95287) holds it
[04:56:34] tick — Ready=0 Building=1 QA=2 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +61925:229) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:56:34] review workers: gates 10 >= 6: holding
[04:56:34] qa workers: gates 10 >= 6: holding
[04:56:34] qa workers: gates 10 >= 6: holding
kept card 254: live review lane (pid 11269) holds it
[04:57:09] tick — Ready=0 Building=1 QA=2 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +61925:229) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:57:09] review workers: gates 11 >= 6: holding
[04:57:09] qa workers: gates 11 >= 6: holding
[04:57:09] qa workers: gates 11 >= 6: holding
[04:57:44] tick — Ready=0 Building=1 QA=2 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +61925:229) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:57:44] review workers: gates 7 >= 6: holding
[04:57:44] qa workers: gates 7 >= 6: holding
[04:57:44] qa workers: gates 7 >= 6: holding
[04:58:18] tick — Ready=0 Building=1 QA=2 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +61925:229) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:58:18] review workers: gates 10 >= 6: holding
[04:58:19] qa workers: gates 10 >= 6: holding
[04:58:19] qa workers: gates 9 >= 6: holding
[04:58:53] tick — Ready=0 Building=1 QA=2 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227 +61925:229) q_workers=2/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:58:53] review workers: gates 10 >= 6: holding
[04:58:53] qa workers: gates 10 >= 6: holding
[04:58:54] qa workers: gates 10 >= 6: holding
[04:59:29] 💀 zombie qa worker on #229 (pid=61925) — card moved to 'Review'; killing
[04:59:32] tick — Ready=0 Building=1 QA=1 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227) q_workers=1/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[04:59:32] review workers: gates 9 >= 6: holding
[04:59:32] qa workers: gates 10 >= 6: holding
[04:59:32] qa workers: gates 10 >= 6: holding
[05:00:06] tick — Ready=0 Building=1 QA=1 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227) q_workers=1/3 r_idle=0(#247 +11269:254) r_workers=1/3 waiting_on_you=0
[05:00:13] dispatch lane=review issue=#240 pid=43664 claim=ToanMobile
[05:00:47] tick — Ready=0 Building=1 QA=1 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=0(#227) q_workers=1/3 r_idle=0(#240 +11269:254) r_workers=2/3 waiting_on_you=0
[05:00:53] dispatch lane=review issue=#229 pid=64906 claim=ToanMobile
[05:00:54] qa workers: gates 14 >= 6: holding
[05:00:54] qa workers: gates 14 >= 6: holding
[05:01:26] reaped stale lock + swept assignee on #227 (pid=13636)
[05:01:35] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229) r_workers=2/3 waiting_on_you=0
[05:01:41] dispatch lane=review issue=#227 pid=34011 claim=ToanMobile
[05:02:14] reaped stale lock + swept assignee on #254 (pid=11269)
[05:02:18] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:02:18] review workers 3/3: at the cap, not starting
[05:02:53] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:02:53] review workers 3/3: at the cap, not starting
[05:03:28] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:03:28] review workers 3/3: at the cap, not starting
[05:04:03] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:04:03] review workers 3/3: at the cap, not starting
[05:04:37] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:04:37] review workers 3/3: at the cap, not starting
[05:05:12] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:05:12] review workers 3/3: at the cap, not starting
[05:05:47] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:05:47] review workers 3/3: at the cap, not starting
[05:06:22] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:06:22] review workers 3/3: at the cap, not starting
kept card 247: live build lane (pid 95287) holds it
[05:06:56] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:06:56] review workers 3/3: at the cap, not starting
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 227: live review lane (pid 34011) holds it
kept card 240: live review lane (pid 43664) holds it
[05:07:30] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:07:30] review workers 3/3: at the cap, not starting
[05:08:04] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:08:04] review workers 3/3: at the cap, not starting
[05:08:38] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:08:38] review workers 3/3: at the cap, not starting
[05:09:12] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:09:12] review workers 3/3: at the cap, not starting
[05:09:47] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:09:47] review workers 3/3: at the cap, not starting
[05:10:22] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:10:22] review workers 3/3: at the cap, not starting
[05:10:56] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:10:56] review workers 3/3: at the cap, not starting
[05:11:30] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:11:30] review workers 3/3: at the cap, not starting
[05:12:05] tick — Ready=0 Building=1 QA=0 Review=3 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +64906:229 34011:227) r_workers=3/3 waiting_on_you=0
[05:12:05] review workers 3/3: at the cap, not starting
[05:12:38] reaped stale lock + swept assignee on #229 (pid=64906)
[05:12:47] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +34011:227) r_workers=2/3 waiting_on_you=0
[05:13:22] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240 +34011:227) r_workers=2/3 waiting_on_you=0
[05:13:55] reaped stale lock + swept assignee on #227 (pid=34011)
[05:14:00] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=11 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:14:05] dispatch lane=review issue=#240 pid=55825 claim=ToanMobile
[05:14:05] build workers 1/10, load 12.77978515625 < 24: starting #2
[05:14:14] preflight hold/unclear for #227: no `## Acceptance Criteria` bullets — not dispatched, card to Blocked
[05:14:52] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[05:15:27] tick — Ready=1 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#247) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:15:27] build workers 1/10, load 5.66162109375 < 24: starting #2
[05:15:27] ⚠ worker of #240 (lane review) ended 77s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: Gate `--full` và ảnh nghiệm thu không áp dụng ở lượt này, vì tôi không sửa file nào trong repo.
[05:15:42] dispatch lane=build issue=#240 pid=1675 claim=ToanMobile
[05:16:17] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=2/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:16:50] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=2/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
kept card 247: live build lane (pid 95287) holds it
[05:17:25] tick — Ready=0 Building=2 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=2/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
kept card 240: live build lane (pid 1675) holds it
✔ đã gỡ /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-254-review
[05:17:59] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=2/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:18:32] reaped stale lock + swept assignee on #247 (pid=95287)
[05:18:35] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=1(#227) q_workers=0/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:18:41] dispatch lane=qa issue=#247 pid=28303 claim=ToanMobile
[05:19:15] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:19:49] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:20:23] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:20:57] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:21:33] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:21:33] qa workers: gates 16 >= 6: holding
[05:21:33] qa workers: gates 16 >= 6: holding
[05:22:07] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:22:42] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:22:42] qa workers: gates 10 >= 6: holding
[05:22:42] qa workers: gates 11 >= 6: holding
[05:23:16] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:23:50] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:24:24] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:25:00] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:25:33] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=12 lanes: b_idle=0(#247 +1675:240) b_workers=1/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:26:06] reaped stale lock + swept assignee on #240 (pid=1675)
[05:26:11] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:26:16] dispatch lane=qa issue=#240 pid=34428 claim=ToanMobile
[05:26:49] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=2/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:27:23] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=2/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:27:57] tick — Ready=0 Building=0 QA=2 Review=0 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=2/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 247: live qa lane (pid 28303) holds it
kept card 240: live qa lane (pid 34428) holds it
[05:28:31] reaped stale lock + swept assignee on #247 (pid=28303)
[05:28:35] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=1(#240) r_workers=0/3 waiting_on_you=0
[05:28:40] dispatch lane=review issue=#247 pid=42562 claim=ToanMobile
[05:29:14] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:29:48] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:30:22] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:30:22] review workers: gates 6 >= 6: holding
[05:30:22] qa workers: gates 6 >= 6: holding
[05:30:56] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:31:30] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:32:05] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:32:05] review workers: gates 10 >= 6: holding
[05:32:05] qa workers: gates 10 >= 6: holding
[05:32:05] qa workers: gates 10 >= 6: holding
[05:32:39] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:32:39] review workers: gates 9 >= 6: holding
[05:32:39] qa workers: gates 8 >= 6: holding
[05:32:39] qa workers: gates 7 >= 6: holding
[05:33:13] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:33:13] review workers: gates 7 >= 6: holding
[05:33:13] qa workers: gates 7 >= 6: holding
[05:33:13] qa workers: gates 8 >= 6: holding
[05:33:47] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:33:47] review workers: gates 6 >= 6: holding
[05:33:47] qa workers: gates 6 >= 6: holding
[05:34:21] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:34:21] review workers: gates 17 >= 6: holding
[05:34:22] qa workers: gates 17 >= 6: holding
[05:34:22] qa workers: gates 18 >= 6: holding
[05:34:56] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:34:56] review workers: gates 10 >= 6: holding
[05:34:56] qa workers: gates 8 >= 6: holding
[05:34:56] qa workers: gates 8 >= 6: holding
[05:35:30] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:35:30] review workers: gates 8 >= 6: holding
[05:35:30] qa workers: gates 7 >= 6: holding
[05:35:30] qa workers: gates 7 >= 6: holding
[05:36:04] tick — Ready=0 Building=0 QA=1 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=0(#247 +34428:240) q_workers=1/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:36:38] tick — Ready=0 Building=0 QA=0 Review=2 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:36:44] dispatch lane=review issue=#240 pid=43715 claim=ToanMobile
[05:37:18] tick — Ready=0 Building=0 QA=0 Review=2 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247 +43715:240) r_workers=2/3 waiting_on_you=0
[05:37:52] tick — Ready=0 Building=0 QA=0 Review=2 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247 +43715:240) r_workers=2/3 waiting_on_you=0
[05:38:26] tick — Ready=0 Building=0 QA=0 Review=2 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247 +43715:240) r_workers=2/3 waiting_on_you=0
kept card 247: live review lane (pid 42562) holds it
[05:39:01] tick — Ready=1 Building=0 QA=0 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:39:01] review workers: gates 6 >= 6: holding
[05:39:01] build workers: gates 8 >= 6: holding
[05:39:35] tick — Ready=1 Building=0 QA=0 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:39:35] review workers: gates 8 >= 6: holding
[05:39:35] build workers: gates 9 >= 6: holding
[05:40:10] tick — Ready=1 Building=0 QA=0 Review=1 Blocked=12 lanes: b_idle=1(#247) b_workers=0/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:40:26] dispatch lane=build issue=#240 pid=93134 claim=ToanMobile
[05:41:00] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:41:33] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:42:07] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:42:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:42:42] review workers: gates 7 >= 6: holding
[05:43:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:43:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:44:24] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=0(#247) r_workers=1/3 waiting_on_you=0
[05:44:59] 💀 zombie review worker on #247 (pid=42562) — card moved to 'Done'; killing
[05:45:08] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:45:42] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:46:16] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:46:50] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:47:25] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:47:59] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:48:32] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[05:49:07] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:49:40] tick — Ready=0 Building=1 QA=0 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:50:14] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:50:48] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:51:22] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:51:56] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:52:31] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:53:05] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:53:39] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:54:14] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:54:48] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:55:23] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=12 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#247) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:55:29] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[05:55:30] adopted live build worker on #240 (pid=93134) from the previous run
[05:55:36] initial Ready count: 1
[05:55:46] tick — Ready=1 Building=0 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:55:46] ⚠ block-rate alert: 11/1 (1100%)
[05:55:46] build workers 1/10, load 13.04638671875 < 24: starting #2
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live build lane (pid 93134) holds it
[05:56:04] dispatch lane=build issue=#237 pid=57027 claim=ToanMobile
[05:56:39] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:57:14] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:57:48] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:58:23] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:58:56] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[05:59:30] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:00:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:00:39] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:01:13] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:01:48] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:02:22] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:02:56] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:03:30] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:04:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:04:39] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:05:12] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:05:48] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept card 240: live build lane (pid 93134) holds it
[06:06:24] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:06:59] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:07:33] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:08:09] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:08:44] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:09:18] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:09:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:10:28] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:11:02] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:11:36] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:12:09] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:12:44] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:13:18] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:13:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:14:27] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:15:02] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:15:36] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:16:10] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[06:16:45] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:17:19] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:17:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:18:27] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:19:01] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=11 lanes: b_idle=0(#240 +57027:237) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:19:35] reaped stale lock + swept assignee on #240 (pid=93134)
[06:19:39] tick — Ready=2 Building=1 QA=1 Review=0 Blocked=9 lanes: b_idle=0(#240 +57027:237) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:19:44] dispatch lane=qa issue=#240 pid=78515 claim=ToanMobile
[06:19:44] build workers 1/10, load 2.318359375 < 24: starting #2
[06:19:59] dispatch lane=build issue=#202 pid=83380 claim=ToanMobile
[06:20:33] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +57027:237) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:20:33] build workers 2/10, load 2.9853515625 < 24: starting #3
[06:20:48] dispatch lane=build issue=#227 pid=3858 claim=ToanMobile
[06:21:21] reaped stale lock + swept assignee on #237 (pid=57027)
[06:21:25] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:21:30] dispatch lane=qa issue=#237 pid=44698 claim=ToanMobile
[06:22:04] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:22:04] qa workers: gates 16 >= 6: holding
[06:22:04] qa workers: gates 17 >= 6: holding
[06:22:39] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:22:39] qa workers: gates 11 >= 6: holding
[06:22:39] qa workers: gates 12 >= 6: holding
[06:23:13] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:23:48] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:23:48] qa workers: gates 8 >= 6: holding
[06:23:48] qa workers: gates 8 >= 6: holding
[06:24:22] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:24:57] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:25:31] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:26:07] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:26:07] qa workers: gates 17 >= 6: holding
[06:26:07] qa workers: gates 15 >= 6: holding
kept card 227: live build lane (pid 3858) holds it
kept card 202: live build lane (pid 83380) holds it
[06:26:44] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 237: live qa lane (pid 44698) holds it
kept card 240: live qa lane (pid 78515) holds it
[06:27:18] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:27:52] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:27:53] qa workers: gates 7 >= 6: holding
[06:27:53] qa workers: gates 6 >= 6: holding
[06:28:27] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:28:27] qa workers: gates 7 >= 6: holding
[06:28:27] qa workers: gates 7 >= 6: holding
[06:29:03] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:29:03] qa workers: gates 10 >= 6: holding
[06:29:03] qa workers: gates 9 >= 6: holding
[06:29:37] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:29:37] qa workers: gates 6 >= 6: holding
[06:29:37] qa workers: gates 6 >= 6: holding
[06:30:12] tick — Ready=0 Building=2 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=2/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:30:12] qa workers 2/3: load 27.33544921875 >= 24: holding
[06:30:12] qa workers 2/3: load 27.33544921875 >= 24: holding
[06:30:50] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:30:50] qa workers: gates 16 >= 6: holding
[06:30:50] qa workers: gates 15 >= 6: holding
[06:31:24] reaped stale lock + swept assignee on #202 (pid=83380)
[06:31:29] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:31:29] qa workers: gates 6 >= 6: holding
[06:31:29] qa workers: gates 6 >= 6: holding
[06:32:04] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:32:04] qa workers: gates 8 >= 6: holding
[06:32:04] qa workers: gates 8 >= 6: holding
[06:32:40] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:32:40] qa workers: gates 6 >= 6: holding
[06:32:40] qa workers: gates 6 >= 6: holding
[06:33:15] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:33:15] qa workers: gates 6 >= 6: holding
[06:33:15] qa workers: gates 6 >= 6: holding
[06:33:52] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:33:52] qa workers: gates 14 >= 6: holding
[06:33:52] qa workers: gates 14 >= 6: holding
[06:34:27] tick — Ready=0 Building=1 QA=3 Review=0 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240 +44698:237) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:34:27] qa workers 2/3: load 55.59521484375 >= 24: holding
[06:34:27] qa workers 2/3: load 55.59521484375 >= 24: holding
[06:35:01] 💀 zombie qa worker on #237 (pid=44698) — card moved to 'Review'; killing
[06:35:04] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[06:35:10] dispatch lane=review issue=#237 pid=79607 claim=ToanMobile
[06:35:10] qa workers 1/3: load 28.01708984375 >= 24: holding
[06:35:10] qa workers 1/3: load 28.01708984375 >= 24: holding
[06:35:43] reaped stale lock + swept assignee on #240 (pid=78515)
[06:35:46] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=1(#240) q_workers=0/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[06:35:51] dispatch lane=review issue=#240 pid=6552 claim=ToanMobile
[06:35:56] dispatch lane=qa issue=#202 pid=11210 claim=ToanMobile
[06:36:31] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=2/3 waiting_on_you=0
[06:37:09] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=2/3 waiting_on_you=0
[06:37:09] review workers: gates 6 >= 6: holding
[06:37:09] qa workers: gates 6 >= 6: holding
[06:37:10] qa workers: gates 6 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 202: live qa lane (pid 11210) holds it
kept card 240: live review lane (pid 6552) holds it
[06:37:47] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=2/3 waiting_on_you=0
[06:37:47] review workers: gates 6 >= 6: holding
[06:37:47] qa workers: gates 6 >= 6: holding
[06:37:48] qa workers: gates 6 >= 6: holding
[06:38:26] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=2/3 waiting_on_you=0
[06:38:26] review workers: gates 18 >= 6: holding
[06:38:26] qa workers: gates 16 >= 6: holding
[06:38:26] qa workers: gates 17 >= 6: holding
[06:39:07] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:39:07] review workers: gates 18 >= 6: holding
[06:39:07] qa workers: gates 16 >= 6: holding
[06:39:07] qa workers: gates 18 >= 6: holding
[06:39:08] build workers: gates 18 >= 6: holding
[06:39:42] reaped stale lock + swept assignee on #237 (pid=79607)
[06:39:49] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:39:50] review workers: gates 9 >= 6: holding
[06:39:50] qa workers: gates 9 >= 6: holding
[06:39:50] qa workers: gates 10 >= 6: holding
[06:39:50] build workers: gates 10 >= 6: holding
[06:40:24] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:40:24] review workers: gates 8 >= 6: holding
[06:40:24] qa workers: gates 8 >= 6: holding
[06:40:24] qa workers: gates 8 >= 6: holding
[06:40:24] build workers: gates 8 >= 6: holding
[06:41:03] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:41:03] review workers: gates 6 >= 6: holding
[06:41:03] qa workers: gates 6 >= 6: holding
[06:41:03] qa workers: gates 6 >= 6: holding
[06:41:03] build workers: gates 7 >= 6: holding
[06:41:41] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:41:41] review workers: gates 8 >= 6: holding
[06:41:41] qa workers: gates 9 >= 6: holding
[06:41:41] qa workers: gates 9 >= 6: holding
[06:41:42] build workers: gates 8 >= 6: holding
[06:42:19] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:42:19] review workers: gates 14 >= 6: holding
[06:42:20] qa workers: gates 17 >= 6: holding
[06:42:20] qa workers: gates 17 >= 6: holding
[06:42:20] build workers: gates 16 >= 6: holding
[06:42:57] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:42:57] review workers: gates 7 >= 6: holding
[06:42:57] qa workers: gates 7 >= 6: holding
[06:42:57] qa workers: gates 8 >= 6: holding
[06:42:58] build workers: gates 8 >= 6: holding
[06:43:34] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:43:34] review workers: gates 7 >= 6: holding
[06:43:34] qa workers: gates 7 >= 6: holding
[06:43:34] qa workers: gates 7 >= 6: holding
[06:43:34] build workers: gates 7 >= 6: holding
[06:44:08] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#202 +3858:227) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:44:08] review workers: gates 7 >= 6: holding
[06:44:08] qa workers: gates 7 >= 6: holding
[06:44:08] qa workers: gates 6 >= 6: holding
[06:44:08] build workers: gates 7 >= 6: holding
[06:44:41] reaped stale lock + swept assignee on #227 (pid=3858)
[06:44:45] tick — Ready=1 Building=0 QA=2 Review=1 Blocked=9 lanes: b_idle=1(#202) b_workers=0/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:44:50] dispatch lane=qa issue=#227 pid=72783 claim=ToanMobile
[06:45:05] dispatch lane=build issue=#237 pid=80400 claim=ToanMobile
[06:45:39] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:46:15] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:46:15] review workers: gates 22 >= 6: holding
[06:46:16] qa workers: gates 26 >= 6: holding
[06:46:16] qa workers: gates 24 >= 6: holding
[06:46:55] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:46:55] review workers: gates 24 >= 6: holding
[06:46:55] qa workers: gates 24 >= 6: holding
[06:46:56] qa workers: gates 24 >= 6: holding
kept card 227: live qa lane (pid 72783) holds it
kept card 240: live review lane (pid 6552) holds it
[06:47:30] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:47:30] review workers: gates 6 >= 6: holding
[06:47:30] qa workers: gates 7 >= 6: holding
[06:47:30] qa workers: gates 7 >= 6: holding
kept card 202: live qa lane (pid 11210) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 237: live build lane (pid 80400) holds it
[06:48:06] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:48:06] review workers: gates 18 >= 6: holding
[06:48:06] qa workers: gates 19 >= 6: holding
[06:48:06] qa workers: gates 18 >= 6: holding
[06:48:42] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:48:42] review workers: gates 13 >= 6: holding
[06:48:43] qa workers: gates 13 >= 6: holding
[06:48:43] qa workers: gates 13 >= 6: holding
[06:49:18] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=0(#237 +6552:240) r_workers=1/3 waiting_on_you=0
[06:49:18] review workers: gates 7 >= 6: holding
[06:49:18] qa workers: gates 14 >= 6: holding
[06:49:18] qa workers: gates 18 >= 6: holding
[06:49:53] reaped stale lock + swept assignee on #240 (pid=6552)
[06:49:59] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:49:59] qa workers: gates 11 >= 6: holding
[06:49:59] qa workers: gates 11 >= 6: holding
[06:49:59] build workers: gates 12 >= 6: holding
[06:50:34] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:50:34] qa workers: gates 18 >= 6: holding
[06:50:34] qa workers: gates 18 >= 6: holding
[06:50:35] build workers: gates 18 >= 6: holding
[06:51:08] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:51:08] qa workers: gates 7 >= 6: holding
[06:51:08] qa workers: gates 7 >= 6: holding
[06:51:08] build workers: gates 7 >= 6: holding
[06:51:43] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:51:43] qa workers: gates 7 >= 6: holding
[06:51:43] qa workers: gates 7 >= 6: holding
[06:51:43] build workers: gates 7 >= 6: holding
[06:52:17] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:52:17] qa workers: gates 8 >= 6: holding
[06:52:17] qa workers: gates 8 >= 6: holding
[06:52:17] build workers: gates 8 >= 6: holding
[06:52:53] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:52:53] qa workers: gates 11 >= 6: holding
[06:52:53] qa workers: gates 11 >= 6: holding
[06:52:53] build workers: gates 11 >= 6: holding
[06:53:27] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:53:28] qa workers: gates 8 >= 6: holding
[06:53:28] qa workers: gates 8 >= 6: holding
[06:53:28] build workers: gates 8 >= 6: holding
[06:54:03] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:54:03] qa workers: gates 7 >= 6: holding
[06:54:03] qa workers: gates 7 >= 6: holding
[06:54:03] build workers: gates 7 >= 6: holding
[06:54:37] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:54:37] qa workers: gates 7 >= 6: holding
[06:54:37] qa workers: gates 7 >= 6: holding
[06:54:37] build workers: gates 7 >= 6: holding
[06:55:12] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:55:12] qa workers: gates 8 >= 6: holding
[06:55:12] qa workers: gates 8 >= 6: holding
[06:55:13] build workers: gates 7 >= 6: holding
[06:55:47] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:55:47] qa workers: gates 8 >= 6: holding
[06:55:47] qa workers: gates 8 >= 6: holding
[06:55:47] build workers: gates 8 >= 6: holding
[06:56:23] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:56:23] qa workers: gates 34 >= 6: holding
[06:56:23] qa workers: gates 38 >= 6: holding
[06:56:24] build workers: gates 34 >= 6: holding
[06:57:02] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:57:02] qa workers: gates 22 >= 6: holding
[06:57:02] qa workers: gates 24 >= 6: holding
[06:57:02] build workers: gates 22 >= 6: holding
[06:57:41] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:57:41] qa workers: gates 8 >= 6: holding
[06:57:41] qa workers: gates 7 >= 6: holding
[06:57:41] build workers: gates 7 >= 6: holding
kept card 237: live build lane (pid 80400) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 227: live qa lane (pid 72783) holds it
kept card 202: live qa lane (pid 11210) holds it
[06:58:19] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:58:19] qa workers: gates 6 >= 6: holding
[06:58:19] qa workers: gates 6 >= 6: holding
[06:58:19] build workers: gates 7 >= 6: holding
[06:58:57] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:58:57] qa workers 2/3: load 38.21044921875 >= 24: holding
[06:58:57] qa workers 2/3: load 38.21044921875 >= 24: holding
[06:58:58] build workers 1/10: load 38.21044921875 >= 24: holding
[06:59:33] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[06:59:33] qa workers 2/3: load 34.02783203125 >= 24: holding
[06:59:33] qa workers 2/3: load 34.02783203125 >= 24: holding
[06:59:33] build workers 1/10: load 34.02783203125 >= 24: holding
[07:00:14] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:00:14] qa workers: gates 20 >= 6: holding
[07:00:15] qa workers: gates 18 >= 6: holding
[07:00:15] build workers: gates 19 >= 6: holding
[07:00:55] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:00:56] qa workers: gates 25 >= 6: holding
[07:00:56] qa workers: gates 24 >= 6: holding
[07:00:56] build workers: gates 24 >= 6: holding
[07:01:32] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:01:32] qa workers: gates 8 >= 6: holding
[07:01:32] qa workers: gates 8 >= 6: holding
[07:01:32] build workers: gates 8 >= 6: holding
[07:02:07] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:02:07] qa workers: gates 7 >= 6: holding
[07:02:07] qa workers: gates 7 >= 6: holding
[07:02:07] build workers: gates 7 >= 6: holding
[07:02:44] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:02:44] qa workers: gates 9 >= 6: holding
[07:02:44] qa workers: gates 9 >= 6: holding
[07:02:44] build workers: gates 9 >= 6: holding
[07:03:21] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:03:21] qa workers: gates 18 >= 6: holding
[07:03:21] qa workers: gates 18 >= 6: holding
[07:03:21] build workers: gates 18 >= 6: holding
[07:04:00] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:04:00] qa workers: gates 26 >= 6: holding
[07:04:01] qa workers: gates 25 >= 6: holding
[07:04:01] build workers: gates 26 >= 6: holding
[07:04:37] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:04:38] qa workers: gates 10 >= 6: holding
[07:04:38] qa workers: gates 11 >= 6: holding
[07:04:38] build workers: gates 12 >= 6: holding
[07:05:16] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:05:16] qa workers: gates 22 >= 6: holding
[07:05:17] qa workers: gates 23 >= 6: holding
[07:05:17] build workers: gates 21 >= 6: holding
[07:05:52] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:05:52] qa workers: gates 6 >= 6: holding
[07:05:52] qa workers: gates 6 >= 6: holding
[07:05:52] build workers: gates 6 >= 6: holding
[07:06:27] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:06:27] qa workers: gates 7 >= 6: holding
[07:06:27] qa workers: gates 7 >= 6: holding
[07:06:27] build workers: gates 7 >= 6: holding
[07:07:03] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:07:03] qa workers: gates 6 >= 6: holding
[07:07:03] qa workers: gates 6 >= 6: holding
[07:07:03] build workers: gates 6 >= 6: holding
[07:07:41] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:07:41] qa workers: gates 15 >= 6: holding
[07:07:42] qa workers: gates 13 >= 6: holding
[07:07:42] build workers: gates 14 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 227: live qa lane (pid 72783) holds it
kept card 202: live qa lane (pid 11210) holds it
kept card 237: live build lane (pid 80400) holds it
[07:08:17] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202 +72783:227) q_workers=2/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:08:17] qa workers 2/3: load 30.7802734375 >= 24: holding
[07:08:17] qa workers 2/3: load 30.7802734375 >= 24: holding
[07:08:17] build workers 1/10: load 30.7802734375 >= 24: holding
[07:08:52] 💀 zombie qa worker on #202 (pid=11210) — card moved to 'Review'; killing
[07:08:55] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#_ +72783:227) q_workers=1/3 r_idle=1(#237) r_workers=0/3 waiting_on_you=0
[07:09:01] dispatch lane=review issue=#202 pid=11729 claim=ToanMobile
[07:09:01] qa workers: gates 7 >= 6: holding
[07:09:01] qa workers: gates 7 >= 6: holding
[07:09:01] build workers: gates 7 >= 6: holding
[07:09:35] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#_ +72783:227) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[07:09:36] build workers 1/10, load 15.94677734375 < 24: starting #2
[07:09:49] dispatch lane=build issue=#240 pid=58867 claim=ToanMobile
[07:10:24] 💀 zombie qa worker on #227 (pid=72783) — card moved to 'Review'; killing
[07:10:28] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#237 +58867:240) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[07:10:28] review workers: gates 17 >= 6: holding
[07:11:03] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=9 lanes: b_idle=0(#237 +58867:240) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[07:11:11] dispatch lane=review issue=#227 pid=28833 claim=ToanMobile
[07:11:46] 💀 zombie review worker on #202 (pid=11729) — card moved to 'Ready'; killing
[07:11:50] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:11:50] review workers: gates 11 >= 6: holding
[07:11:50] build workers: gates 11 >= 6: holding
[07:12:25] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:12:25] build workers 2/10, load 17.9375 < 24: starting #3
[07:12:40] dispatch lane=build issue=#202 pid=49095 claim=ToanMobile
[07:13:15] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:13:15] review workers: gates 13 >= 6: holding
[07:13:55] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:13:55] review workers: gates 15 >= 6: holding
[07:14:07] dispatch lane=qa issue=#237 pid=85841 claim=ToanMobile
[07:14:47] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:14:47] review workers: gates 8 >= 6: holding
[07:14:47] qa workers: gates 8 >= 6: holding
[07:14:47] qa workers: gates 8 >= 6: holding
[07:15:30] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:15:30] review workers: gates 28 >= 6: holding
[07:15:31] qa workers: gates 27 >= 6: holding
[07:15:31] qa workers: gates 28 >= 6: holding
[07:16:11] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:16:11] review workers: gates 13 >= 6: holding
[07:16:11] qa workers: gates 14 >= 6: holding
[07:16:11] qa workers: gates 14 >= 6: holding
[07:16:48] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:16:48] review workers: gates 10 >= 6: holding
[07:16:48] qa workers: gates 10 >= 6: holding
[07:16:48] qa workers: gates 10 >= 6: holding
[07:17:25] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:17:25] review workers: gates 9 >= 6: holding
[07:17:25] qa workers: gates 8 >= 6: holding
[07:17:25] qa workers: gates 9 >= 6: holding
[07:18:04] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:18:04] review workers: gates 11 >= 6: holding
[07:18:05] qa workers: gates 11 >= 6: holding
[07:18:05] qa workers: gates 12 >= 6: holding
kept card 227: live review lane (pid 28833) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live build lane (pid 58867) holds it
[07:18:39] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:18:39] review workers: gates 6 >= 6: holding
[07:18:39] qa workers: gates 6 >= 6: holding
[07:18:39] qa workers: gates 6 >= 6: holding
[07:19:14] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:19:14] review workers: gates 8 >= 6: holding
[07:19:14] qa workers: gates 8 >= 6: holding
[07:19:14] qa workers: gates 7 >= 6: holding
[07:19:55] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:19:55] review workers: gates 39 >= 6: holding
[07:19:55] qa workers: gates 41 >= 6: holding
[07:19:55] qa workers: gates 37 >= 6: holding
[07:20:32] 💀 zombie qa worker on #237 (pid=85841) — card moved to 'Review'; killing
[07:20:37] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:20:37] review workers: gates 16 >= 6: holding
[07:21:13] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:21:13] review workers: gates 6 >= 6: holding
[07:21:48] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=9 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#_ +28833:227) r_workers=1/3 waiting_on_you=0
[07:21:48] review workers: gates 8 >= 6: holding
[07:22:22] 💀 zombie review worker on #227 (pid=28833) — card moved to 'Done'; killing
[07:22:35] ↩ unblocked #228: Blocked → Ready (cleared by #227)
[07:22:37] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:22:44] dispatch lane=review issue=#237 pid=52538 claim=ToanMobile
[07:22:44] build workers: gates 6 >= 6: holding
[07:23:19] tick — Ready=1 Building=0 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +58867:240 49095:202) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[07:23:19] review workers 1/3: load 24.61767578125 >= 24: holding
[07:23:19] build workers 2/10: load 24.61767578125 >= 24: holding
[07:23:53] reaped stale lock + swept assignee on #240 (pid=58867)
[07:23:58] tick — Ready=1 Building=0 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +49095:202) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[07:24:03] dispatch lane=qa issue=#240 pid=95160 claim=ToanMobile
[07:24:03] build workers 1/10, load 15.93798828125 < 24: starting #2
[07:24:25] dispatch lane=build issue=#228 pid=44542 claim=ToanMobile
[07:25:01] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[07:25:01] review workers: gates 14 >= 6: holding
[07:25:01] qa workers: gates 14 >= 6: holding
[07:25:02] qa workers: gates 13 >= 6: holding
[07:25:42] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[07:25:42] review workers: gates 8 >= 6: holding
[07:25:42] qa workers: gates 10 >= 6: holding
[07:25:43] qa workers: gates 10 >= 6: holding
[07:26:24] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#237) r_workers=1/3 waiting_on_you=0
[07:26:24] review workers: gates 10 >= 6: holding
[07:26:25] qa workers: gates 10 >= 6: holding
[07:26:25] qa workers: gates 9 >= 6: holding
[07:27:04] 💀 zombie review worker on #237 (pid=52538) — card moved to 'Ready'; killing
[07:27:11] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:27:11] qa workers: gates 6 >= 6: holding
[07:27:11] qa workers: gates 7 >= 6: holding
[07:27:12] build workers: gates 6 >= 6: holding
[07:27:52] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:27:52] qa workers: gates 15 >= 6: holding
[07:27:52] qa workers: gates 17 >= 6: holding
[07:27:53] build workers: gates 16 >= 6: holding
[07:28:32] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:28:33] qa workers: gates 8 >= 6: holding
[07:28:33] qa workers: gates 8 >= 6: holding
[07:28:33] build workers: gates 8 >= 6: holding
kept card 240: live qa lane (pid 95160) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 227: a PR of it merged under 900s ago (Reviewer's post-merge steps)
kept card 202: live build lane (pid 49095) holds it
[07:29:13] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:29:13] qa workers: gates 15 >= 6: holding
[07:29:13] qa workers: gates 15 >= 6: holding
[07:29:13] build workers: gates 14 >= 6: holding
[07:29:49] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:29:49] qa workers: gates 7 >= 6: holding
[07:29:49] qa workers: gates 7 >= 6: holding
[07:29:49] build workers: gates 7 >= 6: holding
[07:30:27] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:30:27] qa workers: gates 10 >= 6: holding
[07:30:28] qa workers: gates 9 >= 6: holding
[07:30:28] build workers: gates 9 >= 6: holding
[07:31:05] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:31:05] qa workers: gates 6 >= 6: holding
[07:31:05] qa workers: gates 6 >= 6: holding
[07:31:05] build workers: gates 7 >= 6: holding
[07:31:43] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:31:43] qa workers: gates 13 >= 6: holding
[07:31:44] qa workers: gates 11 >= 6: holding
[07:31:44] build workers: gates 12 >= 6: holding
[07:32:19] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:32:19] qa workers: gates 11 >= 6: holding
[07:32:19] qa workers: gates 10 >= 6: holding
[07:32:19] build workers: gates 10 >= 6: holding
[07:32:56] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:32:56] qa workers: gates 10 >= 6: holding
[07:32:56] qa workers: gates 11 >= 6: holding
[07:32:56] build workers: gates 11 >= 6: holding
[07:33:40] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:33:40] qa workers: gates 16 >= 6: holding
[07:33:40] qa workers: gates 16 >= 6: holding
[07:33:41] build workers: gates 16 >= 6: holding
[07:34:19] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:34:19] qa workers: gates 11 >= 6: holding
[07:34:19] qa workers: gates 11 >= 6: holding
[07:34:19] build workers: gates 12 >= 6: holding
[07:34:56] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:34:56] qa workers: gates 7 >= 6: holding
[07:34:56] qa workers: gates 7 >= 6: holding
[07:34:56] build workers: gates 7 >= 6: holding
[07:35:32] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:35:32] qa workers: gates 7 >= 6: holding
[07:35:32] qa workers: gates 7 >= 6: holding
[07:35:32] build workers: gates 7 >= 6: holding
[07:36:09] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:36:09] qa workers: gates 7 >= 6: holding
[07:36:09] qa workers: gates 8 >= 6: holding
[07:36:09] build workers: gates 8 >= 6: holding
[07:36:44] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:36:44] qa workers: gates 9 >= 6: holding
[07:36:44] qa workers: gates 9 >= 6: holding
[07:36:44] build workers: gates 9 >= 6: holding
[07:37:19] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:37:19] qa workers: gates 8 >= 6: holding
[07:37:19] qa workers: gates 8 >= 6: holding
[07:37:19] build workers: gates 8 >= 6: holding
[07:37:59] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:37:59] qa workers: gates 15 >= 6: holding
[07:37:59] qa workers: gates 14 >= 6: holding
[07:37:59] build workers: gates 16 >= 6: holding
[07:38:36] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:38:36] qa workers: gates 12 >= 6: holding
[07:38:37] qa workers: gates 12 >= 6: holding
[07:38:37] build workers: gates 11 >= 6: holding
kept card 240: live qa lane (pid 95160) holds it
kept card 228: live build lane (pid 44542) holds it
[07:39:17] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:39:17] qa workers: gates 31 >= 6: holding
[07:39:18] qa workers: gates 30 >= 6: holding
[07:39:18] build workers: gates 30 >= 6: holding
[07:39:57] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:39:57] qa workers: gates 19 >= 6: holding
[07:39:57] qa workers: gates 20 >= 6: holding
[07:39:57] build workers: gates 18 >= 6: holding
[07:40:34] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:40:34] qa workers: gates 9 >= 6: holding
[07:40:34] qa workers: gates 8 >= 6: holding
[07:40:34] build workers: gates 8 >= 6: holding
[07:41:15] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:41:16] qa workers: gates 27 >= 6: holding
[07:41:16] qa workers: gates 25 >= 6: holding
[07:41:16] build workers: gates 21 >= 6: holding
[07:41:54] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:41:54] qa workers: gates 20 >= 6: holding
[07:41:54] qa workers: gates 20 >= 6: holding
[07:41:55] build workers: gates 21 >= 6: holding
[07:42:33] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:42:33] qa workers: gates 12 >= 6: holding
[07:42:33] qa workers: gates 12 >= 6: holding
[07:42:33] build workers: gates 14 >= 6: holding
[07:43:09] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:43:09] qa workers: gates 16 >= 6: holding
[07:43:09] qa workers: gates 16 >= 6: holding
[07:43:09] build workers: gates 18 >= 6: holding
[07:43:44] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:43:44] qa workers: gates 7 >= 6: holding
[07:43:44] qa workers: gates 6 >= 6: holding
[07:43:44] build workers 2/10: load 48.96923828125 >= 24: holding
[07:44:18] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:44:18] qa workers 1/3: load 32.72119140625 >= 24: holding
[07:44:18] qa workers 1/3: load 32.72119140625 >= 24: holding
[07:44:18] build workers 2/10: load 32.72119140625 >= 24: holding
[07:44:54] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:44:54] qa workers: gates 25 >= 6: holding
[07:44:55] qa workers: gates 25 >= 6: holding
[07:44:55] build workers: gates 25 >= 6: holding
[07:45:30] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:45:30] qa workers: gates 7 >= 6: holding
[07:45:30] qa workers: gates 6 >= 6: holding
[07:45:30] build workers: gates 6 >= 6: holding
[07:46:04] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228 +49095:202) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:46:05] qa workers 1/3: load 29.16943359375 >= 24: holding
[07:46:05] qa workers 1/3: load 29.16943359375 >= 24: holding
[07:46:05] build workers 2/10: load 29.16943359375 >= 24: holding
[07:46:39] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:46:47] dispatch lane=qa issue=#202 pid=60447 claim=ToanMobile
[07:46:47] build workers: gates 10 >= 6: holding
[07:47:27] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:47:27] qa workers: gates 20 >= 6: holding
[07:47:28] qa workers: gates 18 >= 6: holding
[07:47:28] build workers: gates 16 >= 6: holding
[07:48:07] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:48:07] qa workers: gates 16 >= 6: holding
[07:48:07] qa workers: gates 17 >= 6: holding
[07:48:07] build workers: gates 17 >= 6: holding
[07:48:44] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:48:44] qa workers: gates 9 >= 6: holding
[07:48:44] qa workers: gates 9 >= 6: holding
[07:48:44] build workers: gates 9 >= 6: holding
kept card 228: live build lane (pid 44542) holds it
kept card 202: live qa lane (pid 60447) holds it
kept card 240: live qa lane (pid 95160) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
✔ đã gỡ /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-227-review
[07:49:19] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:49:19] qa workers 2/3: load 29.10205078125 >= 24: holding
[07:49:19] qa workers 2/3: load 29.10205078125 >= 24: holding
[07:49:19] build workers 1/10: load 29.10205078125 >= 24: holding
[07:49:54] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:49:55] qa workers: gates 7 >= 6: holding
[07:49:55] qa workers: gates 7 >= 6: holding
[07:49:55] build workers: gates 7 >= 6: holding
[07:50:29] tick — Ready=1 Building=0 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:50:29] qa workers: gates 14 >= 6: holding
[07:50:29] qa workers: gates 14 >= 6: holding
[07:50:29] build workers: gates 13 >= 6: holding
[07:51:03] reaped stale lock + swept assignee on #228 (pid=44542)
[07:51:08] tick — Ready=1 Building=0 QA=3 Review=0 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240 +60447:202) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:51:14] dispatch lane=qa issue=#228 pid=51480 claim=ToanMobile
[07:51:14] build workers: gates 6 >= 6: holding
[07:51:50] tick — Ready=1 Building=0 QA=3 Review=0 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240 +60447:202 51480:228) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:51:50] qa workers 3/3: at the cap, not starting
[07:51:50] qa workers 3/3: at the cap, not starting
[07:51:50] build workers: gates 14 >= 6: holding
[07:52:25] tick — Ready=1 Building=0 QA=3 Review=0 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240 +60447:202 51480:228) q_workers=3/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:52:25] qa workers 3/3: at the cap, not starting
[07:52:25] qa workers 3/3: at the cap, not starting
[07:57:20] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[07:57:25] reaped stale lock + swept assignee on #202 (pid=60447)
[07:57:28] reaped stale lock + swept assignee on #228 (pid=51480)
[07:57:31] reaped stale lock + swept assignee on #240 (pid=95160)
[07:57:49] ↩ stranded #237: Building → Ready (branch issue-237-worker-silent-death)
[07:57:51] initial Ready count: 1
Post "https://api.github.com/graphql": net/http: TLS handshake timeout
sweep: gh pr list failed (card 151); stopping, nothing more removed
[07:58:17] tick — Ready=1 Building=0 QA=3 Review=0 Blocked=8 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:58:17] ⚠ block-rate alert: 8/1 (800%)
[07:58:22] dispatch lane=qa issue=#240 pid=31513 claim=ToanMobile
[07:58:40] dispatch lane=build issue=#237 pid=57804 claim=ToanMobile
[07:59:15] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:59:15] qa workers: gates 6 >= 6: holding
[07:59:15] qa workers: gates 6 >= 6: holding
[07:59:15] build workers: gates 6 >= 6: holding
[07:59:52] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[07:59:52] qa workers: gates 10 >= 6: holding
[07:59:52] qa workers: gates 10 >= 6: holding
[07:59:52] build workers: gates 9 >= 6: holding
[08:00:27] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:00:27] qa workers: gates 6 >= 6: holding
[08:00:27] qa workers: gates 6 >= 6: holding
[08:00:27] build workers: gates 6 >= 6: holding
[08:01:01] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:01:01] qa workers: gates 7 >= 6: holding
[08:01:01] build workers: gates 6 >= 6: holding
[08:01:37] 💀 zombie qa worker on #240 (pid=31513) — card moved to 'Review'; killing
[08:01:43] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:01:55] dispatch lane=review issue=#240 pid=7394 claim=ToanMobile
[08:02:04] dispatch lane=qa issue=#202 pid=14894 claim=ToanMobile
[08:02:04] build workers: gates 11 >= 6: holding
[08:02:42] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:02:42] review workers: gates 17 >= 6: holding
[08:02:42] qa workers: gates 17 >= 6: holding
[08:02:42] qa workers: gates 18 >= 6: holding
[08:02:42] build workers: gates 14 >= 6: holding
[08:03:20] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:03:20] review workers: gates 16 >= 6: holding
[08:03:21] qa workers: gates 17 >= 6: holding
[08:03:21] qa workers: gates 17 >= 6: holding
[08:03:21] build workers: gates 16 >= 6: holding
[08:03:58] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:03:58] review workers: gates 15 >= 6: holding
[08:03:58] qa workers: gates 14 >= 6: holding
[08:03:59] qa workers: gates 14 >= 6: holding
[08:03:59] build workers: gates 13 >= 6: holding
[08:04:36] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:04:36] review workers: gates 9 >= 6: holding
[08:04:36] qa workers: gates 10 >= 6: holding
[08:04:36] qa workers: gates 10 >= 6: holding
[08:04:36] build workers: gates 10 >= 6: holding
[08:05:13] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:05:13] review workers 1/3: load 85.86279296875 >= 36: holding
[08:05:14] qa workers 1/3: load 85.86279296875 >= 36: holding
[08:05:14] qa workers: gates 6 >= 6: holding
[08:05:14] build workers: gates 7 >= 6: holding
[08:05:50] 💀 zombie review worker on #240 (pid=7394) — card moved to 'QA'; killing
[08:05:55] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:05:56] qa workers: gates 10 >= 6: holding
[08:05:56] qa workers: gates 11 >= 6: holding
[08:05:56] build workers: gates 9 >= 6: holding
[08:06:31] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:06:31] qa workers 1/3: load 73.3720703125 >= 36: holding
[08:06:31] qa workers 1/3: load 73.3720703125 >= 36: holding
[08:06:31] build workers 1/10: load 73.3720703125 >= 36: holding
[08:07:09] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:07:10] qa workers: gates 23 >= 6: holding
[08:07:10] qa workers: gates 24 >= 6: holding
[08:07:10] build workers: gates 24 >= 6: holding
[08:07:47] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:07:47] qa workers: gates 20 >= 6: holding
[08:07:47] qa workers: gates 20 >= 6: holding
[08:07:48] build workers: gates 17 >= 6: holding
[08:08:24] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:08:25] qa workers: gates 12 >= 6: holding
[08:08:25] qa workers: gates 10 >= 6: holding
[08:08:25] build workers: gates 10 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 202: live qa lane (pid 14894) holds it
kept card 237: live build lane (pid 57804) holds it
[08:09:01] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:09:01] qa workers: gates 8 >= 6: holding
[08:09:01] qa workers: gates 8 >= 6: holding
[08:09:01] build workers: gates 13 >= 6: holding
[08:09:37] tick — Ready=1 Building=1 QA=3 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#202) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:09:37] qa workers: gates 8 >= 6: holding
[08:09:37] qa workers: gates 8 >= 6: holding
[08:09:37] build workers: gates 8 >= 6: holding
[08:10:13] 💀 zombie qa worker on #202 (pid=14894) — card moved to 'Review'; killing
[08:10:18] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:10:29] dispatch lane=review issue=#202 pid=42746 claim=ToanMobile
[08:10:38] dispatch lane=qa issue=#240 pid=62696 claim=ToanMobile
[08:10:38] build workers: gates 11 >= 6: holding
[08:11:17] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:11:18] review workers: gates 30 >= 6: holding
[08:11:18] qa workers: gates 30 >= 6: holding
[08:11:18] qa workers: gates 30 >= 6: holding
[08:11:18] build workers: gates 30 >= 6: holding
[08:11:54] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:11:54] review workers: gates 11 >= 6: holding
[08:11:54] qa workers: gates 11 >= 6: holding
[08:11:54] qa workers: gates 11 >= 6: holding
[08:11:54] build workers: gates 12 >= 6: holding
[08:12:32] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:12:32] review workers: gates 10 >= 6: holding
[08:12:32] qa workers: gates 8 >= 6: holding
[08:12:32] qa workers: gates 8 >= 6: holding
[08:12:32] build workers: gates 9 >= 6: holding
[08:13:10] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:13:10] review workers: gates 24 >= 6: holding
[08:13:10] qa workers: gates 24 >= 6: holding
[08:13:10] qa workers: gates 22 >= 6: holding
[08:13:11] build workers: gates 23 >= 6: holding
[08:13:47] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:13:47] review workers: gates 10 >= 6: holding
[08:13:47] qa workers: gates 10 >= 6: holding
[08:13:47] qa workers: gates 8 >= 6: holding
[08:13:47] build workers: gates 8 >= 6: holding
[08:14:24] tick — Ready=1 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:14:24] review workers: gates 13 >= 6: holding
[08:14:24] qa workers: gates 14 >= 6: holding
[08:14:25] qa workers: gates 15 >= 6: holding
[08:14:25] build workers: gates 15 >= 6: holding
[08:14:59] 💀 zombie qa worker on #240 (pid=62696) — card moved to 'Review'; killing
[08:15:03] tick — Ready=1 Building=1 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#202) r_workers=1/3 waiting_on_you=0
[08:15:14] dispatch lane=review issue=#240 pid=43893 claim=ToanMobile
[08:15:25] dispatch lane=qa issue=#228 pid=52129 claim=ToanMobile
[08:15:25] build workers: gates 19 >= 6: holding
[08:16:01] tick — Ready=1 Building=1 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#202 +43893:240) r_workers=2/3 waiting_on_you=0
[08:16:01] review workers: gates 7 >= 6: holding
[08:16:01] qa workers: gates 6 >= 6: holding
[08:16:01] qa workers: gates 7 >= 6: holding
[08:16:01] build workers: gates 7 >= 6: holding
[08:16:38] 💀 zombie review worker on #202 (pid=42746) — card moved to 'Done'; killing
[08:16:42] 💀 zombie review worker on #240 (pid=43893) — card moved to 'QA'; killing
[08:16:51] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:16:51] qa workers: gates 8 >= 6: holding
[08:16:51] qa workers: gates 10 >= 6: holding
[08:16:51] build workers: gates 11 >= 6: holding
[08:17:28] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:17:28] qa workers: gates 9 >= 6: holding
[08:17:28] qa workers: gates 9 >= 6: holding
[08:17:29] build workers: gates 10 >= 6: holding
[08:18:06] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:18:06] qa workers: gates 15 >= 6: holding
[08:18:06] qa workers: gates 15 >= 6: holding
[08:18:06] build workers: gates 19 >= 6: holding
[08:18:45] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:18:45] qa workers: gates 14 >= 6: holding
[08:18:45] qa workers: gates 14 >= 6: holding
[08:18:45] build workers: gates 15 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 237: live build lane (pid 57804) holds it
[08:19:22] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:19:22] qa workers: gates 6 >= 6: holding
[08:19:22] qa workers: gates 7 >= 6: holding
[08:19:22] build workers: gates 6 >= 6: holding
[08:19:59] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:19:59] qa workers: gates 16 >= 6: holding
[08:19:59] qa workers: gates 14 >= 6: holding
[08:19:59] build workers: gates 15 >= 6: holding
[08:20:34] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:20:34] qa workers: gates 11 >= 6: holding
[08:20:34] qa workers: gates 11 >= 6: holding
[08:20:34] build workers: gates 11 >= 6: holding
[08:21:10] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:21:10] qa workers: gates 13 >= 6: holding
[08:21:10] qa workers: gates 13 >= 6: holding
[08:21:10] build workers: gates 13 >= 6: holding
[08:21:45] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:21:51] dispatch lane=qa issue=#240 pid=10736 claim=ToanMobile
[08:21:51] build workers: gates 7 >= 6: holding
[08:22:29] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:22:29] qa workers: gates 26 >= 6: holding
[08:22:29] qa workers: gates 25 >= 6: holding
[08:22:29] build workers: gates 24 >= 6: holding
[08:23:06] tick — Ready=1 Building=1 QA=2 Review=0 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=2/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:23:06] qa workers: gates 7 >= 6: holding
[08:23:06] qa workers: gates 7 >= 6: holding
[08:23:06] build workers: gates 9 >= 6: holding
[08:23:39] reaped stale lock + swept assignee on #228 (pid=52129)
[08:23:44] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:23:52] dispatch lane=review issue=#228 pid=5525 claim=ToanMobile
[08:23:52] qa workers: gates 10 >= 6: holding
[08:23:52] qa workers: gates 10 >= 6: holding
[08:23:52] build workers: gates 9 >= 6: holding
[08:24:29] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[08:24:30] review workers: gates 18 >= 6: holding
[08:24:30] qa workers: gates 16 >= 6: holding
[08:24:30] qa workers: gates 17 >= 6: holding
[08:24:30] build workers: gates 17 >= 6: holding
[08:25:06] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[08:25:06] review workers 1/3: load 51.84521484375 >= 36: holding
[08:25:06] qa workers 1/3: load 51.84521484375 >= 36: holding
[08:25:06] qa workers: gates 6 >= 6: holding
[08:25:06] build workers 1/10: load 51.84521484375 >= 36: holding
[08:25:40] tick — Ready=1 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237) b_workers=1/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[08:25:40] build workers 1/10, load 31.56396484375 < 36: starting #2
[08:25:57] dispatch lane=build issue=#190 pid=48420 claim=ToanMobile
[08:26:32] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190) b_workers=2/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[08:27:07] 💀 zombie review worker on #228 (pid=5525) — card moved to 'Ready'; killing
[08:27:10] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#237 +48420:190) b_workers=2/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:27:10] build workers 2/10, load 11.33251953125 < 36: starting #3
[08:27:27] dispatch lane=build issue=#228 pid=16314 claim=ToanMobile
[08:28:01] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=3/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:28:36] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=3/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:29:11] tick — Ready=0 Building=3 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=3/10 q_idle=0(#228 +10736:240) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 190: live build lane (pid 48420) holds it
kept card 237: live build lane (pid 57804) holds it
kept card 240: live qa lane (pid 10736) holds it
[08:29:45] reaped stale lock + swept assignee on #240 (pid=10736)
[08:29:49] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=3/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[08:29:57] dispatch lane=review issue=#240 pid=40637 claim=ToanMobile
[08:30:31] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=3/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:31:05] reaped stale lock + swept assignee on #237 (pid=57804)
[08:31:09] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:31:14] dispatch lane=qa issue=#237 pid=61661 claim=ToanMobile
[08:31:49] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:32:24] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:32:24] review workers: gates 12 >= 6: holding
[08:32:24] qa workers: gates 12 >= 6: holding
[08:32:24] qa workers: gates 11 >= 6: holding
[08:32:58] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:33:33] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:34:08] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:34:43] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=0(#237) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:35:17] 💀 zombie qa worker on #237 (pid=61661) — card moved to 'Review'; killing
[08:35:21] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[08:35:28] dispatch lane=review issue=#237 pid=76103 claim=ToanMobile
[08:36:02] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#240 +76103:237) r_workers=2/3 waiting_on_you=0
[08:36:36] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#237 +48420:190 16314:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#240 +76103:237) r_workers=2/3 waiting_on_you=0
[08:37:09] reaped stale lock + swept assignee on #240 (pid=40637)
[08:37:14] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
[08:37:20] dispatch lane=qa issue=#240 pid=94298 claim=ToanMobile
[08:37:53] reaped stale lock + swept assignee on #190 (pid=48420)
[08:37:57] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
[08:38:03] dispatch lane=qa issue=#190 pid=1947 claim=ToanMobile
[08:38:38] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#240 +1947:190) q_workers=2/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
kept card 237: live review lane (pid 76103) holds it
[08:39:13] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#240 +1947:190) q_workers=2/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 228: live build lane (pid 16314) holds it
[08:39:48] tick — Ready=0 Building=1 QA=2 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#240 +1947:190) q_workers=2/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
[08:40:22] 💀 zombie qa worker on #240 (pid=94298) — card moved to 'Review'; killing
[08:40:26] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#_ +1947:190) q_workers=1/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
[08:40:33] dispatch lane=review issue=#240 pid=87221 claim=ToanMobile
[08:41:08] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#_ +1947:190) q_workers=1/3 r_idle=0(#240 +76103:237) r_workers=2/3 waiting_on_you=0
[08:41:43] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=0(#_ +1947:190) q_workers=1/3 r_idle=0(#240 +76103:237) r_workers=2/3 waiting_on_you=0
[08:41:43] review workers: gates 11 >= 6: holding
[08:41:43] qa workers: gates 12 >= 6: holding
[08:41:43] qa workers: gates 12 >= 6: holding
[08:42:17] 💀 zombie qa worker on #190 (pid=1947) — card moved to 'Review'; killing
[08:42:21] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=9 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#240 +76103:237) r_workers=1/3 waiting_on_you=0
[08:42:28] dispatch lane=review issue=#190 pid=98055 claim=ToanMobile
[08:42:59] ⚠ worker of #240 (lane review) ended 100s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: Tôi cố ý ghi `blocked-by: -` thay cho dòng `blocked-by: 78` mà script sinh ra. Thẻ chờ quyết định của người, không chờ #78 đóng. Nếu để `78`, bước quét Blocked sẽ t
[08:43:01] reaped stale lock + swept assignee on #240 (pid=87221)
[08:43:06] tick — Ready=0 Building=1 QA=0 Review=2 Blocked=9 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190 +76103:237) r_workers=2/3 waiting_on_you=0
[08:43:46] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=9 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[08:44:19] reaped stale lock + swept assignee on #237 (pid=76103)
[08:44:23] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#237 +16314:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[08:44:23] build workers 1/10, load 4.63671875 < 36: starting #2
[08:44:38] dispatch lane=build issue=#240 pid=72309 claim=ToanMobile
[08:45:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +16314:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:05:56] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[09:06:00] reaped stale lock + swept assignee on #190 (pid=98055)
[09:06:02] reaped stale lock + swept assignee on #228 (pid=16314)
[09:06:06] reaped stale lock + swept assignee on #240 (pid=72309)
[09:06:25] ↩ stranded #240: Building → Ready (branch issue-240-test-session-isolation)
[09:06:28] ℹ stranded #228: keeping existing worktree .claude/worktrees/issue-228-build (branch issue-228-merge-train-runner) for Builder to resume
[09:06:35] ↩ stranded #228: Building → Ready (branch issue-228-merge-train-runner)
[09:06:39] initial Ready count: 2
[09:06:44] ⚠ self-reload: origin/main has a newer super-board-run.sh but this runner keeps the old code — main checkout is not a fast-forward of origin/main (branch 'main'); bring it level, then the next idle tick reloads
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[09:06:56] tick — Ready=2 Building=0 QA=0 Review=1 Blocked=8 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[09:06:56] ⚠ block-rate alert: 8/2 (400%)
[09:07:09] dispatch lane=review issue=#190 pid=57020 claim=ToanMobile
[09:07:09] build workers: gates 6 >= 6: holding
[09:07:45] tick — Ready=2 Building=0 QA=0 Review=1 Blocked=8 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:08:03] dispatch lane=build issue=#240 pid=12129 claim=ToanMobile
[09:08:38] tick — Ready=1 Building=1 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:08:38] build workers 1/10, load 10.61962890625 < 36: starting #2
[09:08:52] dispatch lane=build issue=#228 pid=39599 claim=ToanMobile
[09:09:31] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:10:07] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:10:41] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:11:23] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:11:23] review workers: gates 19 >= 6: holding
[09:12:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:12:13] review workers: gates 39 >= 6: holding
[09:13:02] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:13:03] review workers: gates 24 >= 6: holding
[09:13:44] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:13:45] review workers: gates 18 >= 6: holding
[09:14:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:14:27] review workers: gates 11 >= 6: holding
[09:15:13] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:15:14] review workers: gates 27 >= 6: holding
[09:15:56] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:15:57] review workers: gates 14 >= 6: holding
[09:16:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:16:38] review workers: gates 23 >= 6: holding
[09:17:29] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:17:30] review workers: gates 18 >= 6: holding
kept card 190: live review lane (pid 57020) holds it
kept card 228: live build lane (pid 39599) holds it
kept card 240: live build lane (pid 12129) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[09:18:15] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:18:15] review workers: gates 20 >= 6: holding
[09:19:00] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:19:01] review workers: gates 21 >= 6: holding
[09:19:49] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:19:49] review workers: gates 18 >= 6: holding
[09:20:37] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:20:38] review workers: gates 9 >= 6: holding
[09:21:35] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:21:35] review workers: gates 29 >= 6: holding
[09:22:26] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:22:27] review workers: gates 23 >= 6: holding
[09:23:18] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:23:19] review workers: gates 22 >= 6: holding
[09:24:14] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:24:16] review workers: gates 20 >= 6: holding
[09:25:09] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:25:10] review workers: gates 16 >= 6: holding
[09:25:57] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:25:58] review workers: gates 19 >= 6: holding
[09:26:44] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:26:45] review workers: gates 7 >= 6: holding
[09:27:27] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:27:27] review workers: gates 9 >= 6: holding
kept card 240: live build lane (pid 12129) holds it
[09:28:11] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:28:11] review workers 1/3: load 62.34130859375 >= 36: holding
[09:28:55] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:28:56] review workers 1/3: load 51.94677734375 >= 36: holding
[09:29:41] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:29:41] review workers: gates 18 >= 6: holding
[09:30:24] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:30:24] review workers: gates 13 >= 6: holding
[09:31:07] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:31:08] review workers: gates 10 >= 6: holding
[09:31:51] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:31:52] review workers: gates 13 >= 6: holding
[09:32:34] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:32:34] review workers: gates 11 >= 6: holding
[09:33:17] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:33:17] review workers: gates 9 >= 6: holding
[09:34:03] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:34:04] review workers: gates 21 >= 6: holding
[09:34:47] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:34:47] review workers: gates 8 >= 6: holding
[09:35:28] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:35:28] review workers 1/3: load 68.58544921875 >= 36: holding
[09:36:03] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:36:04] review workers 1/3: load 49.3369140625 >= 36: holding
[09:36:38] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:36:38] review workers 1/3: load 38.404296875 >= 36: holding
[09:37:16] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:37:16] review workers: gates 11 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[09:37:50] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
kept card 190: live review lane (pid 57020) holds it
[09:38:25] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:38:25] review workers: gates 10 >= 6: holding
[09:39:00] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:39:35] tick — Ready=0 Building=2 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:40:10] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:40:44] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:41:19] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:41:53] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:42:27] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:43:09] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:43:10] review workers: gates 26 >= 6: holding
[09:43:51] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:43:51] review workers: gates 14 >= 6: holding
[09:44:27] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:45:03] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:45:03] review workers: gates 6 >= 6: holding
[09:45:37] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:45:37] review workers: gates 7 >= 6: holding
[09:46:12] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:46:12] review workers: gates 6 >= 6: holding
[09:46:57] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:46:57] review workers: gates 20 >= 6: holding
[09:47:41] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:47:42] review workers: gates 14 >= 6: holding
[09:48:26] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:48:26] review workers: gates 9 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 228: live build lane (pid 39599) holds it
kept card 190: live review lane (pid 57020) holds it
kept card 240: live build lane (pid 12129) holds it
[09:49:06] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:49:06] review workers: gates 9 >= 6: holding
[09:49:46] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:49:46] review workers: gates 10 >= 6: holding
[09:50:38] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:50:39] review workers: gates 14 >= 6: holding
[09:51:24] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:51:25] review workers: gates 14 >= 6: holding
[09:52:00] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:52:35] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:53:08] reaped stale lock + swept assignee on #190 (pid=57020)
[09:53:11] reaped stale lock + swept assignee on #240 (pid=12129)
[09:53:16] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[09:53:24] review lane issue=#190: PR #211 approved at head fa25ea40ae40ef14bc628901a0735414e53c7864 — merge-only, no fresh review
[09:53:24] dispatch lane=review issue=#190 pid=24026 claim=ToanMobile
[09:53:30] dispatch lane=qa issue=#240 pid=32675 claim=ToanMobile
[09:54:06] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#240 +39599:228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:54:27] super-board run started — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[09:54:28] adopted live review worker on #190 (pid=24026) from the previous run
[09:54:28] adopted live build worker on #228 (pid=39599) from the previous run
[09:54:28] adopted live qa worker on #240 (pid=32675) from the previous run
[09:54:35] initial Ready count: 0
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 228: live build lane (pid 39599) holds it
[09:54:51] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:54:52] review workers: gates 14 >= 6: holding
[09:54:52] qa workers: gates 13 >= 6: holding
[09:54:52] qa workers: gates 10 >= 6: holding
kept card 240: live qa lane (pid 32675) holds it
kept card 190: live review lane (pid 24026) holds it
[09:55:28] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:56:06] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:56:43] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:56:43] review workers: gates 11 >= 6: holding
[09:56:43] qa workers: gates 12 >= 6: holding
[09:56:43] qa workers: gates 12 >= 6: holding
[09:57:30] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:57:30] review workers: gates 13 >= 6: holding
[09:57:30] qa workers: gates 14 >= 6: holding
[09:57:30] qa workers: gates 15 >= 6: holding
[09:58:11] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:58:11] review workers: gates 14 >= 6: holding
[09:58:12] qa workers: gates 13 >= 6: holding
[09:58:12] qa workers: gates 13 >= 6: holding
[09:58:51] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:58:51] review workers: gates 11 >= 6: holding
[09:58:51] qa workers: gates 10 >= 6: holding
[09:58:51] qa workers: gates 10 >= 6: holding
[09:59:29] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[09:59:29] review workers: gates 21 >= 6: holding
[09:59:29] qa workers: gates 19 >= 6: holding
[09:59:29] qa workers: gates 20 >= 6: holding
[10:00:00] worker of #228 (lane build) exit record: none — wrapper killed or host asleep
[10:00:05] reaped stale lock + swept assignee on #228 (pid=39599)
[10:00:30] ↩ stranded #228: Building → Ready (branch issue-228-merge-train-runner)
[10:00:33] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:00:34] review workers: gates 13 >= 6: holding
[10:00:34] qa workers: gates 13 >= 6: holding
[10:00:34] qa workers: gates 14 >= 6: holding
[10:00:34] build workers: gates 11 >= 6: holding
[10:01:14] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:01:14] review workers: gates 12 >= 6: holding
[10:01:14] qa workers: gates 13 >= 6: holding
[10:01:15] qa workers: gates 14 >= 6: holding
[10:01:15] build workers: gates 12 >= 6: holding
[10:01:57] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:01:57] review workers: gates 20 >= 6: holding
[10:01:58] qa workers: gates 22 >= 6: holding
[10:01:58] qa workers: gates 19 >= 6: holding
[10:01:58] build workers: gates 18 >= 6: holding
[10:02:33] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=8 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:02:49] dispatch lane=build issue=#228 pid=43891 claim=ToanMobile
[10:03:31] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:03:31] review workers: gates 46 >= 6: holding
[10:03:31] qa workers: gates 35 >= 6: holding
[10:03:31] qa workers: gates 38 >= 6: holding
[10:04:11] tick — Ready=2 Building=1 QA=1 Review=1 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:04:11] review workers: gates 25 >= 6: holding
[10:04:11] qa workers: gates 24 >= 6: holding
[10:04:12] qa workers: gates 27 >= 6: holding
[10:04:12] build workers: gates 27 >= 6: holding
kept card 228: live build lane (pid 43891) holds it
kept card 240: live qa lane (pid 32675) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[10:04:54] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=0(#190) r_workers=1/3 waiting_on_you=0
[10:04:54] qa workers 1/3: load 62.265625 >= 36: holding
[10:04:54] qa workers 1/3: load 62.265625 >= 36: holding
[10:04:54] build workers 1/10: load 62.265625 >= 36: holding
[10:05:24] worker of #190 (lane review) exit record: none — wrapper killed or host asleep
[10:05:29] reaped stale lock + swept assignee on #190 (pid=24026)
[10:05:33] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:05:33] qa workers 1/3: load 36.78271484375 >= 36: holding
[10:05:33] qa workers 1/3: load 36.78271484375 >= 36: holding
[10:05:33] build workers 1/10: load 36.78271484375 >= 36: holding
[10:06:07] tick — Ready=4 Building=1 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228) b_workers=1/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:06:08] build workers 1/10, load 21.86962890625 < 36: starting #2
[10:06:26] dispatch lane=build issue=#306 pid=97189 claim=ToanMobile
[10:07:01] tick — Ready=3 Building=2 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228 +97189:306) b_workers=2/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:07:02] build workers 2/10, load 21.7490234375 < 36: starting #3
[10:07:20] dispatch lane=build issue=#307 pid=46635 claim=ToanMobile
[10:07:54] tick — Ready=2 Building=3 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228 +97189:306 46635:307) b_workers=3/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:07:55] build workers 3/10, load 17.7666015625 < 36: starting #4
[10:08:11] dispatch lane=build issue=#291 pid=98629 claim=ToanMobile
[10:08:45] tick — Ready=1 Building=4 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291) b_workers=4/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:08:46] build workers 4/10, load 13.2392578125 < 36: starting #5
[10:09:01] dispatch lane=build issue=#303 pid=35233 claim=ToanMobile
[10:09:36] tick — Ready=1 Building=5 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:09:37] build workers 5/10, load 9.85888671875 < 36: starting #6
[10:09:52] dispatch lane=build issue=#308 pid=73050 claim=ToanMobile
[10:10:33] tick — Ready=0 Building=6 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:10:33] qa workers: gates 12 >= 6: holding
[10:10:33] qa workers: gates 12 >= 6: holding
[10:11:08] tick — Ready=1 Building=6 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:11:09] build workers 6/10, load 8.34912109375 < 36: starting #7
[10:11:25] dispatch lane=build issue=#200 pid=36566 claim=ToanMobile
[10:12:04] tick — Ready=0 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:12:50] tick — Ready=1 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:12:50] qa workers: gates 16 >= 6: holding
[10:12:50] qa workers: gates 16 >= 6: holding
[10:12:51] build workers: gates 17 >= 6: holding
[10:13:32] tick — Ready=1 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:13:32] qa workers: gates 7 >= 6: holding
[10:13:32] qa workers: gates 7 >= 6: holding
[10:13:32] build workers: gates 7 >= 6: holding
[10:14:21] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:14:21] qa workers: gates 29 >= 6: holding
[10:14:22] qa workers: gates 27 >= 6: holding
[10:14:22] build workers: gates 27 >= 6: holding
[10:15:06] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:15:06] qa workers: gates 16 >= 6: holding
[10:15:07] qa workers: gates 15 >= 6: holding
[10:15:07] build workers: gates 15 >= 6: holding
kept card 308: live build lane (pid 73050) holds it
kept card 306: live build lane (pid 97189) holds it
kept card 228: live build lane (pid 43891) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 307: live build lane (pid 46635) holds it
kept card 303: live build lane (pid 35233) holds it
[10:15:46] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:15:47] qa workers: gates 12 >= 6: holding
[10:15:47] qa workers: gates 12 >= 6: holding
[10:15:47] build workers: gates 12 >= 6: holding
[10:16:24] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:16:24] qa workers: gates 7 >= 6: holding
[10:16:24] qa workers: gates 7 >= 6: holding
[10:16:24] build workers: gates 7 >= 6: holding
[10:17:08] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:17:08] qa workers: gates 8 >= 6: holding
[10:17:08] qa workers: gates 8 >= 6: holding
[10:17:08] build workers: gates 8 >= 6: holding
[10:17:46] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:17:46] qa workers: gates 6 >= 6: holding
[10:17:46] qa workers: gates 6 >= 6: holding
[10:17:46] build workers: gates 6 >= 6: holding
[10:18:25] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:18:25] qa workers: gates 6 >= 6: holding
[10:18:25] qa workers: gates 6 >= 6: holding
[10:18:25] build workers: gates 6 >= 6: holding
[10:19:07] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:19:07] qa workers: gates 17 >= 6: holding
[10:19:07] qa workers: gates 16 >= 6: holding
[10:19:08] build workers: gates 15 >= 6: holding
[10:19:46] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:19:46] qa workers: gates 11 >= 6: holding
[10:19:46] qa workers: gates 10 >= 6: holding
[10:19:47] build workers: gates 11 >= 6: holding
[10:20:23] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:20:23] qa workers: gates 7 >= 6: holding
[10:20:23] qa workers: gates 7 >= 6: holding
[10:20:24] build workers: gates 8 >= 6: holding
[10:21:13] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:21:14] qa workers: gates 36 >= 6: holding
[10:21:14] qa workers: gates 37 >= 6: holding
[10:21:14] build workers: gates 37 >= 6: holding
[10:21:56] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:21:56] qa workers: gates 20 >= 6: holding
[10:21:56] qa workers: gates 19 >= 6: holding
[10:21:56] build workers: gates 18 >= 6: holding
[10:22:40] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:22:40] qa workers: gates 20 >= 6: holding
[10:22:40] qa workers: gates 19 >= 6: holding
[10:22:41] build workers: gates 20 >= 6: holding
[10:23:22] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:23:22] qa workers: gates 18 >= 6: holding
[10:23:22] qa workers: gates 18 >= 6: holding
[10:23:22] build workers: gates 18 >= 6: holding
[10:23:59] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:23:59] qa workers: gates 12 >= 6: holding
[10:24:00] qa workers: gates 12 >= 6: holding
[10:24:00] build workers: gates 12 >= 6: holding
[10:24:44] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:24:44] qa workers: gates 23 >= 6: holding
[10:24:44] qa workers: gates 25 >= 6: holding
[10:24:44] build workers: gates 25 >= 6: holding
[10:25:27] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:25:27] qa workers: gates 13 >= 6: holding
[10:25:27] qa workers: gates 13 >= 6: holding
[10:25:27] build workers: gates 14 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 308: live build lane (pid 73050) holds it
kept card 200: live build lane (pid 36566) holds it
kept card 228: live build lane (pid 43891) holds it
kept card 291: live build lane (pid 98629) holds it
kept card 306: live build lane (pid 97189) holds it
kept card 307: live build lane (pid 46635) holds it
[10:26:10] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:26:10] qa workers: gates 14 >= 6: holding
[10:26:11] qa workers: gates 13 >= 6: holding
[10:26:11] build workers: gates 12 >= 6: holding
[10:26:55] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:26:55] qa workers: gates 16 >= 6: holding
[10:26:55] qa workers: gates 15 >= 6: holding
[10:26:56] build workers: gates 15 >= 6: holding
[10:27:39] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:27:39] qa workers: gates 17 >= 6: holding
[10:27:40] qa workers: gates 16 >= 6: holding
[10:27:40] build workers: gates 16 >= 6: holding
[10:28:27] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:28:27] qa workers: gates 17 >= 6: holding
[10:28:28] qa workers: gates 17 >= 6: holding
[10:28:28] build workers: gates 16 >= 6: holding
[10:29:12] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:29:12] qa workers: gates 17 >= 6: holding
[10:29:13] qa workers: gates 18 >= 6: holding
[10:29:13] build workers: gates 18 >= 6: holding
[10:29:59] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:29:59] qa workers: gates 26 >= 6: holding
[10:29:59] qa workers: gates 26 >= 6: holding
[10:29:59] build workers: gates 25 >= 6: holding
[10:30:43] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:30:43] qa workers: gates 17 >= 6: holding
[10:30:43] qa workers: gates 18 >= 6: holding
[10:30:44] build workers: gates 18 >= 6: holding
[10:31:26] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:31:26] qa workers: gates 16 >= 6: holding
[10:31:26] qa workers: gates 16 >= 6: holding
[10:31:27] build workers: gates 17 >= 6: holding
[10:32:08] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:32:08] qa workers: gates 16 >= 6: holding
[10:32:08] qa workers: gates 16 >= 6: holding
[10:32:08] build workers: gates 15 >= 6: holding
[10:32:49] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:32:49] qa workers: gates 22 >= 6: holding
[10:32:50] qa workers: gates 21 >= 6: holding
[10:32:50] build workers: gates 21 >= 6: holding
[10:33:34] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:33:34] qa workers: gates 26 >= 6: holding
[10:33:35] qa workers: gates 28 >= 6: holding
[10:33:35] build workers: gates 26 >= 6: holding
[10:34:19] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:34:19] qa workers: gates 28 >= 6: holding
[10:34:19] qa workers: gates 26 >= 6: holding
[10:34:19] build workers: gates 26 >= 6: holding
[10:35:00] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:35:00] qa workers: gates 20 >= 6: holding
[10:35:00] qa workers: gates 19 >= 6: holding
[10:35:00] build workers: gates 25 >= 6: holding
[10:35:41] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:35:41] qa workers: gates 21 >= 6: holding
[10:35:41] qa workers: gates 20 >= 6: holding
[10:35:41] build workers: gates 18 >= 6: holding
kept card 303: live build lane (pid 35233) holds it
kept card 308: live build lane (pid 73050) holds it
kept card 240: live qa lane (pid 32675) holds it
kept card 200: live build lane (pid 36566) holds it
kept card 291: live build lane (pid 98629) holds it
[10:36:20] tick — Ready=2 Building=7 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:36:20] qa workers: gates 24 >= 6: holding
[10:36:20] qa workers: gates 24 >= 6: holding
[10:36:21] build workers: gates 24 >= 6: holding
[10:37:03] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:37:03] qa workers: gates 19 >= 6: holding
[10:37:04] qa workers: gates 19 >= 6: holding
[10:37:04] build workers: gates 18 >= 6: holding
[10:37:43] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:37:43] qa workers: gates 23 >= 6: holding
[10:37:43] qa workers: gates 23 >= 6: holding
[10:37:43] build workers: gates 22 >= 6: holding
[10:38:20] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:38:21] qa workers: gates 12 >= 6: holding
[10:38:21] qa workers: gates 12 >= 6: holding
[10:38:21] build workers: gates 12 >= 6: holding
[10:39:01] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:39:01] qa workers: gates 16 >= 6: holding
[10:39:01] qa workers: gates 16 >= 6: holding
[10:39:02] build workers: gates 16 >= 6: holding
[10:39:39] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:39:39] qa workers: gates 15 >= 6: holding
[10:39:39] qa workers: gates 15 >= 6: holding
[10:39:39] build workers: gates 15 >= 6: holding
[10:40:21] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:40:21] qa workers: gates 23 >= 6: holding
[10:40:21] qa workers: gates 24 >= 6: holding
[10:40:21] build workers: gates 25 >= 6: holding
[10:41:00] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:41:00] qa workers: gates 15 >= 6: holding
[10:41:00] qa workers: gates 16 >= 6: holding
[10:41:00] build workers: gates 17 >= 6: holding
[10:41:39] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:41:39] qa workers: gates 14 >= 6: holding
[10:41:39] qa workers: gates 15 >= 6: holding
[10:41:39] build workers: gates 14 >= 6: holding
[10:42:21] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:42:21] qa workers: gates 27 >= 6: holding
[10:42:21] qa workers: gates 29 >= 6: holding
[10:42:21] build workers: gates 30 >= 6: holding
[10:43:00] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 73050:308 36566:200) b_workers=7/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:43:00] qa workers: gates 14 >= 6: holding
[10:43:00] qa workers: gates 15 >= 6: holding
[10:43:01] build workers: gates 16 >= 6: holding
[10:43:40] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:43:40] qa workers: gates 23 >= 6: holding
[10:43:40] qa workers: gates 23 >= 6: holding
[10:43:40] build workers: gates 22 >= 6: holding
[10:44:14] worker of #308 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2024s
[10:44:18] reaped stale lock + swept assignee on #308 (pid=73050)
[10:44:28] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:44:28] qa workers: gates 22 >= 6: holding
[10:44:28] qa workers: gates 22 >= 6: holding
[10:44:28] build workers: gates 22 >= 6: holding
[10:45:07] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:45:08] qa workers: gates 13 >= 6: holding
[10:45:08] qa workers: gates 13 >= 6: holding
[10:45:08] build workers: gates 13 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[10:45:48] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:45:49] qa workers: gates 19 >= 6: holding
[10:45:49] qa workers: gates 18 >= 6: holding
[10:45:49] build workers: gates 19 >= 6: holding
kept card 307: live build lane (pid 46635) holds it
kept card 200: live build lane (pid 36566) holds it
kept card 306: live build lane (pid 97189) holds it
[10:46:34] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:46:35] qa workers: gates 21 >= 6: holding
[10:46:35] qa workers: gates 21 >= 6: holding
[10:46:35] build workers: gates 22 >= 6: holding
[10:47:16] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:47:16] qa workers: gates 16 >= 6: holding
[10:47:16] qa workers: gates 17 >= 6: holding
[10:47:16] build workers: gates 15 >= 6: holding
[10:47:55] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=6/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:47:55] qa workers: gates 10 >= 6: holding
[10:47:55] qa workers: gates 11 >= 6: holding
[10:47:55] build workers: gates 11 >= 6: holding
[10:48:30] tick — Ready=2 Building=6 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:48:31] qa workers: gates 9 >= 6: holding
[10:48:31] qa workers: gates 9 >= 6: holding
[10:48:31] build workers: gates 9 >= 6: holding
[10:49:02] worker of #228 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2741s
[10:49:05] reaped stale lock + swept assignee on #228 (pid=43891)
[10:49:25] ↩ stranded #228: Building → Ready (branch issue-228-merge-train-runner)
[10:49:28] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:49:29] qa workers: gates 12 >= 6: holding
[10:49:29] qa workers: gates 12 >= 6: holding
[10:49:29] build workers: gates 12 >= 6: holding
[10:50:08] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:50:08] qa workers: gates 9 >= 6: holding
[10:50:08] qa workers: gates 9 >= 6: holding
[10:50:09] build workers: gates 9 >= 6: holding
[10:50:45] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:50:45] qa workers: gates 7 >= 6: holding
[10:50:45] qa workers: gates 7 >= 6: holding
[10:50:45] build workers: gates 7 >= 6: holding
[10:51:21] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:51:21] qa workers: gates 10 >= 6: holding
[10:51:21] qa workers: gates 10 >= 6: holding
[10:51:21] build workers: gates 9 >= 6: holding
[10:51:58] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:51:58] qa workers: gates 10 >= 6: holding
[10:51:58] qa workers: gates 12 >= 6: holding
[10:51:58] build workers: gates 11 >= 6: holding
[10:52:34] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:52:34] qa workers: gates 10 >= 6: holding
[10:52:34] qa workers: gates 10 >= 6: holding
[10:52:35] build workers: gates 10 >= 6: holding
[10:53:12] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:53:12] qa workers: gates 9 >= 6: holding
[10:53:12] qa workers: gates 8 >= 6: holding
[10:53:12] build workers: gates 9 >= 6: holding
[10:53:49] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:53:49] qa workers: gates 11 >= 6: holding
[10:53:49] qa workers: gates 11 >= 6: holding
[10:53:49] build workers: gates 11 >= 6: holding
kept card 303: live build lane (pid 35233) holds it
[10:59:13] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:59:13] qa workers: gates 8 >= 6: holding
[10:59:13] qa workers: gates 8 >= 6: holding
[10:59:13] build workers: gates 8 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 240: live qa lane (pid 32675) holds it
kept card 307: live build lane (pid 46635) holds it
[10:59:49] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[10:59:49] qa workers: gates 9 >= 6: holding
[10:59:49] qa workers: gates 9 >= 6: holding
[10:59:49] build workers: gates 8 >= 6: holding
[11:00:29] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[11:00:29] qa workers: gates 18 >= 6: holding
[11:00:29] qa workers: gates 17 >= 6: holding
[11:00:30] build workers: gates 18 >= 6: holding
[11:01:06] tick — Ready=3 Building=5 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[11:01:06] qa workers: gates 8 >= 6: holding
[11:01:06] qa workers: gates 7 >= 6: holding
[11:01:06] build workers: gates 7 >= 6: holding
[11:01:42] tick — Ready=3 Building=5 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[11:01:42] qa workers: gates 7 >= 6: holding
[11:01:42] qa workers: gates 7 >= 6: holding
[11:01:42] build workers: gates 8 >= 6: holding
[11:02:21] tick — Ready=3 Building=5 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#240) q_workers=1/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[11:02:21] qa workers: gates 16 >= 6: holding
[11:02:21] qa workers: gates 16 >= 6: holding
[11:02:21] build workers: gates 13 >= 6: holding
[11:02:53] 💀 zombie qa worker on #240 (pid=32675) — card moved to 'Review'; killing
[11:03:02] tick — Ready=3 Building=5 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#190) r_workers=0/3 waiting_on_you=0
[11:03:09] dispatch lane=review issue=#240 pid=58985 claim=ToanMobile
[11:03:14] dispatch lane=qa issue=#308 pid=63298 claim=ToanMobile
[11:03:14] build workers 5/10: load 64.78564453125 >= 36: holding
[11:03:48] tick — Ready=3 Building=5 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:03:48] review workers: gates 7 >= 6: holding
[11:03:48] qa workers: gates 7 >= 6: holding
[11:03:49] qa workers: gates 7 >= 6: holding
[11:03:49] build workers: gates 7 >= 6: holding
[11:04:25] tick — Ready=3 Building=5 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:04:25] review workers: gates 15 >= 6: holding
[11:04:26] qa workers: gates 15 >= 6: holding
[11:04:26] qa workers: gates 16 >= 6: holding
[11:04:26] build workers: gates 15 >= 6: holding
[11:05:06] tick — Ready=3 Building=4 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:05:06] review workers: gates 11 >= 6: holding
[11:05:06] qa workers: gates 11 >= 6: holding
[11:05:06] qa workers: gates 11 >= 6: holding
[11:05:07] build workers: gates 13 >= 6: holding
[11:05:48] tick — Ready=3 Building=4 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:05:48] review workers: gates 18 >= 6: holding
[11:05:48] qa workers: gates 19 >= 6: holding
[11:05:48] qa workers: gates 21 >= 6: holding
[11:05:49] build workers: gates 21 >= 6: holding
[11:08:10] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:08:11] review workers: gates 9 >= 6: holding
[11:08:11] qa workers: gates 11 >= 6: holding
[11:08:11] qa workers: gates 12 >= 6: holding
[11:08:11] build workers: gates 13 >= 6: holding
[11:08:48] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:08:48] review workers: gates 11 >= 6: holding
[11:08:48] qa workers: gates 11 >= 6: holding
[11:08:48] qa workers: gates 10 >= 6: holding
[11:08:48] build workers: gates 11 >= 6: holding
[11:09:34] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:09:34] review workers: gates 7 >= 6: holding
[11:09:34] qa workers: gates 7 >= 6: holding
[11:09:34] qa workers: gates 7 >= 6: holding
[11:09:35] build workers: gates 7 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 200: live build lane (pid 36566) holds it
kept card 306: live build lane (pid 97189) holds it
kept card 291: live build lane (pid 98629) holds it
kept card 307: live build lane (pid 46635) holds it
[11:10:23] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 35233:303 36566:200) b_workers=5/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:10:23] review workers: gates 21 >= 6: holding
[11:10:23] qa workers: gates 20 >= 6: holding
[11:10:23] qa workers: gates 20 >= 6: holding
[11:10:24] build workers: gates 20 >= 6: holding
[11:10:57] worker of #303 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3686s
[11:11:01] reaped stale lock + swept assignee on #303 (pid=35233)
[11:11:11] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:11:11] review workers: gates 11 >= 6: holding
[11:11:11] qa workers: gates 11 >= 6: holding
[11:11:11] qa workers: gates 11 >= 6: holding
[11:11:11] build workers: gates 11 >= 6: holding
[11:11:51] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:11:51] review workers: gates 14 >= 6: holding
[11:11:51] qa workers: gates 14 >= 6: holding
[11:11:51] qa workers: gates 13 >= 6: holding
[11:11:52] build workers: gates 13 >= 6: holding
[11:12:31] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:12:31] review workers: gates 10 >= 6: holding
[11:12:31] qa workers: gates 10 >= 6: holding
[11:12:31] qa workers: gates 10 >= 6: holding
[11:12:32] build workers: gates 10 >= 6: holding
[11:13:14] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:13:14] review workers: gates 17 >= 6: holding
[11:13:14] qa workers: gates 17 >= 6: holding
[11:13:14] qa workers: gates 17 >= 6: holding
[11:13:15] build workers: gates 19 >= 6: holding
[11:13:54] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:13:54] review workers: gates 9 >= 6: holding
[11:13:55] qa workers: gates 10 >= 6: holding
[11:13:55] qa workers: gates 10 >= 6: holding
[11:13:55] build workers: gates 10 >= 6: holding
[11:14:48] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:14:48] review workers: gates 13 >= 6: holding
[11:14:48] qa workers: gates 14 >= 6: holding
[11:14:48] qa workers: gates 14 >= 6: holding
[11:14:49] build workers: gates 14 >= 6: holding
[11:15:28] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:15:28] review workers: gates 9 >= 6: holding
[11:15:28] qa workers: gates 9 >= 6: holding
[11:15:28] qa workers: gates 9 >= 6: holding
[11:15:28] build workers: gates 9 >= 6: holding
[11:16:07] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:16:07] review workers: gates 10 >= 6: holding
[11:16:07] qa workers: gates 9 >= 6: holding
[11:16:08] qa workers: gates 10 >= 6: holding
[11:16:08] build workers: gates 10 >= 6: holding
[11:16:45] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:16:45] review workers: gates 11 >= 6: holding
[11:16:45] qa workers: gates 10 >= 6: holding
[11:16:45] qa workers: gates 10 >= 6: holding
[11:16:46] build workers: gates 10 >= 6: holding
[11:17:37] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:17:37] review workers: gates 37 >= 6: holding
[11:17:38] qa workers: gates 36 >= 6: holding
[11:17:38] qa workers: gates 38 >= 6: holding
[11:17:38] build workers: gates 39 >= 6: holding
[11:18:22] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:18:22] review workers: gates 24 >= 6: holding
[11:18:22] qa workers: gates 23 >= 6: holding
[11:18:23] qa workers: gates 22 >= 6: holding
[11:18:23] build workers: gates 22 >= 6: holding
[11:19:03] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:19:03] review workers: gates 13 >= 6: holding
[11:19:03] qa workers: gates 13 >= 6: holding
[11:19:03] qa workers: gates 14 >= 6: holding
[11:19:03] build workers: gates 13 >= 6: holding
[11:19:49] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:19:49] review workers: gates 26 >= 6: holding
[11:19:49] qa workers: gates 26 >= 6: holding
[11:19:50] qa workers: gates 27 >= 6: holding
[11:19:50] build workers: gates 27 >= 6: holding
kept card 240: live review lane (pid 58985) holds it
kept card 306: live build lane (pid 97189) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 307: live build lane (pid 46635) holds it
kept card 200: live build lane (pid 36566) holds it
[11:20:31] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:20:32] review workers: gates 17 >= 6: holding
[11:20:32] qa workers: gates 17 >= 6: holding
[11:20:32] qa workers: gates 17 >= 6: holding
[11:20:32] build workers: gates 17 >= 6: holding
[11:21:14] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:21:14] review workers: gates 8 >= 6: holding
[11:21:15] qa workers: gates 8 >= 6: holding
[11:21:15] qa workers: gates 8 >= 6: holding
[11:21:15] build workers: gates 8 >= 6: holding
[11:22:00] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:22:00] review workers: gates 25 >= 6: holding
[11:22:01] qa workers: gates 25 >= 6: holding
[11:22:01] qa workers: gates 24 >= 6: holding
[11:22:02] build workers: gates 26 >= 6: holding
kept card 200: live build lane (pid 36566) holds it
kept card 308: live qa lane (pid 63298) holds it
kept card 306: live build lane (pid 97189) holds it
[11:41:51] tick — Ready=3 Building=3 QA=3 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:41:52] review workers: gates 15 >= 6: holding
[11:41:52] qa workers: gates 18 >= 6: holding
[11:41:52] qa workers: gates 18 >= 6: holding
[11:41:52] build workers: gates 19 >= 6: holding
kept card 291: live build lane (pid 98629) holds it
kept card 307: live build lane (pid 46635) holds it
[11:42:33] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:42:33] review workers: gates 16 >= 6: holding
[11:42:33] qa workers: gates 16 >= 6: holding
[11:42:33] qa workers: gates 16 >= 6: holding
[11:42:33] build workers: gates 14 >= 6: holding
[11:43:23] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:43:24] review workers: gates 30 >= 6: holding
[11:43:24] qa workers: gates 26 >= 6: holding
[11:43:24] qa workers: gates 27 >= 6: holding
[11:43:24] build workers: gates 28 >= 6: holding
[11:43:58] worker of #308 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=2431s
[11:44:01] reaped stale lock + swept assignee on #308 (pid=63298)
[11:44:09] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:44:10] review workers: gates 18 >= 6: holding
[11:44:18] dispatch lane=qa issue=#303 pid=48433 claim=ToanMobile
[11:44:18] build workers: gates 12 >= 6: holding
[11:45:13] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:45:13] review workers: gates 28 >= 6: holding
[11:45:14] qa workers: gates 30 >= 6: holding
[11:45:15] qa workers: gates 29 >= 6: holding
[11:45:16] build workers: gates 28 >= 6: holding
[11:46:13] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:46:14] review workers: gates 31 >= 6: holding
[11:46:14] qa workers: gates 29 >= 6: holding
[11:46:14] qa workers: gates 28 >= 6: holding
[11:46:14] build workers: gates 28 >= 6: holding
[11:46:55] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:46:56] review workers: gates 21 >= 6: holding
[11:46:56] qa workers: gates 19 >= 6: holding
[11:46:56] qa workers: gates 17 >= 6: holding
[11:46:56] build workers: gates 17 >= 6: holding
[11:47:33] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:47:33] review workers: gates 13 >= 6: holding
[11:47:33] qa workers: gates 13 >= 6: holding
[11:47:33] qa workers: gates 12 >= 6: holding
[11:47:33] build workers: gates 13 >= 6: holding
[11:48:14] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:48:15] review workers: gates 20 >= 6: holding
[11:48:15] qa workers: gates 23 >= 6: holding
[11:48:15] qa workers: gates 20 >= 6: holding
[11:48:15] build workers: gates 20 >= 6: holding
[11:48:55] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:48:55] review workers: gates 16 >= 6: holding
[11:48:56] qa workers: gates 18 >= 6: holding
[11:48:56] qa workers: gates 18 >= 6: holding
[11:48:56] build workers: gates 19 >= 6: holding
[11:49:39] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:49:39] review workers: gates 26 >= 6: holding
[11:49:40] qa workers: gates 26 >= 6: holding
[11:49:40] qa workers: gates 27 >= 6: holding
[11:49:40] build workers: gates 28 >= 6: holding
[11:50:20] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:50:20] review workers: gates 20 >= 6: holding
[11:50:20] qa workers: gates 19 >= 6: holding
[11:50:20] qa workers: gates 20 >= 6: holding
[11:50:21] build workers: gates 18 >= 6: holding
[11:51:00] tick — Ready=4 Building=3 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#228 +97189:306 46635:307 98629:291 36566:200) b_workers=4/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:51:00] review workers: gates 20 >= 6: holding
[11:51:00] qa workers: gates 20 >= 6: holding
[11:51:00] qa workers: gates 20 >= 6: holding
[11:51:00] build workers: gates 19 >= 6: holding
[11:51:32] worker of #306 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=6282s
[11:51:36] reaped stale lock + swept assignee on #306 (pid=97189)
kept card 291: live build lane (pid 98629) holds it
[11:51:46] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:51:47] review workers: gates 25 >= 6: holding
[11:51:47] qa workers: gates 26 >= 6: holding
[11:51:48] qa workers: gates 26 >= 6: holding
[11:51:48] build workers: gates 28 >= 6: holding
kept card 240: live review lane (pid 58985) holds it
kept card 303: live qa lane (pid 48433) holds it
[11:52:36] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#303) q_workers=1/3 r_idle=0(#240) r_workers=1/3 waiting_on_you=0
[11:52:36] review workers: gates 31 >= 6: holding
[11:52:37] qa workers: gates 31 >= 6: holding
[11:52:37] qa workers: gates 32 >= 6: holding
[11:52:37] build workers: gates 31 >= 6: holding
[11:53:12] 💀 zombie qa worker on #303 (pid=48433) — card moved to 'Review'; killing
[11:53:17] 💀 zombie review worker on #240 (pid=58985) — card moved to 'Blocked'; killing
[11:53:31] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[11:53:42] dispatch lane=review issue=#303 pid=37738 claim=ToanMobile
[11:53:52] dispatch lane=qa issue=#306 pid=43981 claim=ToanMobile
[11:53:52] build workers: gates 10 >= 6: holding
[11:54:46] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:54:47] review workers: gates 21 >= 6: holding
[11:54:48] qa workers: gates 18 >= 6: holding
[11:54:48] qa workers: gates 20 >= 6: holding
[11:54:49] build workers: gates 19 >= 6: holding
[11:55:36] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:55:37] review workers: gates 12 >= 6: holding
[11:55:37] qa workers: gates 13 >= 6: holding
[11:55:38] qa workers: gates 25 >= 6: holding
[11:55:38] build workers: gates 24 >= 6: holding
[11:56:23] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:56:23] review workers: gates 14 >= 6: holding
[11:56:23] qa workers: gates 15 >= 6: holding
[11:56:24] qa workers: gates 13 >= 6: holding
[11:56:24] build workers: gates 14 >= 6: holding
[11:57:16] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:57:16] review workers: gates 31 >= 6: holding
[11:57:16] qa workers: gates 29 >= 6: holding
[11:57:17] qa workers: gates 28 >= 6: holding
[11:57:18] build workers: gates 29 >= 6: holding
[11:58:06] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:58:07] review workers: gates 17 >= 6: holding
[11:58:07] qa workers: gates 16 >= 6: holding
[11:58:08] qa workers: gates 17 >= 6: holding
[11:58:08] build workers: gates 19 >= 6: holding
[11:58:49] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:58:49] review workers: gates 11 >= 6: holding
[11:58:49] qa workers: gates 12 >= 6: holding
[11:58:50] qa workers: gates 12 >= 6: holding
[11:58:50] build workers: gates 13 >= 6: holding
[11:59:31] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[11:59:32] review workers: gates 15 >= 6: holding
[11:59:32] qa workers: gates 15 >= 6: holding
[11:59:32] qa workers: gates 14 >= 6: holding
[11:59:32] build workers: gates 13 >= 6: holding
[12:00:12] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:00:13] review workers: gates 23 >= 6: holding
[12:00:13] qa workers: gates 21 >= 6: holding
[12:00:13] qa workers: gates 23 >= 6: holding
[12:00:13] build workers: gates 26 >= 6: holding
[12:00:51] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:00:51] review workers: gates 14 >= 6: holding
[12:00:51] qa workers: gates 13 >= 6: holding
[12:00:51] qa workers: gates 13 >= 6: holding
[12:00:51] build workers: gates 13 >= 6: holding
[12:01:30] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:01:30] review workers: gates 11 >= 6: holding
[12:01:30] qa workers: gates 11 >= 6: holding
[12:01:30] qa workers: gates 11 >= 6: holding
[12:01:30] build workers: gates 10 >= 6: holding
[12:02:07] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:02:07] review workers: gates 8 >= 6: holding
[12:02:07] qa workers: gates 8 >= 6: holding
[12:02:08] qa workers: gates 8 >= 6: holding
[12:02:08] build workers: gates 8 >= 6: holding
kept card 303: live review lane (pid 37738) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 306: live qa lane (pid 43981) holds it
kept card 307: live build lane (pid 46635) holds it
[12:02:44] tick — Ready=4 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:02:45] review workers: gates 6 >= 6: holding
[12:02:45] qa workers: gates 6 >= 6: holding
[12:02:45] qa workers: gates 6 >= 6: holding
[12:02:45] build workers: gates 6 >= 6: holding
[12:03:27] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:03:27] qa workers: gates 11 >= 6: holding
[12:03:27] qa workers: gates 11 >= 6: holding
[12:03:28] build workers: gates 11 >= 6: holding
[12:04:06] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=0(#303) r_workers=1/3 waiting_on_you=0
[12:04:06] qa workers: gates 10 >= 6: holding
[12:04:06] qa workers: gates 10 >= 6: holding
[12:04:06] build workers: gates 11 >= 6: holding
[12:04:38] 💀 zombie review worker on #303 (pid=37738) — card moved to 'Done'; killing
[12:04:48] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:04:48] qa workers: gates 11 >= 6: holding
[12:04:48] qa workers: gates 12 >= 6: holding
[12:04:49] build workers: gates 11 >= 6: holding
[12:05:26] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:05:27] qa workers: gates 10 >= 6: holding
[12:05:27] qa workers: gates 10 >= 6: holding
[12:05:27] build workers: gates 10 >= 6: holding
[12:06:03] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:06:03] qa workers: gates 6 >= 6: holding
[12:06:03] qa workers: gates 6 >= 6: holding
[12:06:03] build workers: gates 6 >= 6: holding
[12:06:39] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:06:40] qa workers: gates 9 >= 6: holding
[12:06:40] qa workers: gates 9 >= 6: holding
[12:06:40] build workers: gates 16 >= 6: holding
[12:07:16] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:07:16] qa workers: gates 8 >= 6: holding
[12:07:16] qa workers: gates 8 >= 6: holding
[12:07:16] build workers: gates 7 >= 6: holding
[12:07:51] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:07:51] qa workers 1/3: load 83.5546875 >= 36: holding
[12:07:51] qa workers 1/3: load 83.5546875 >= 36: holding
[12:07:51] build workers 3/10: load 83.5546875 >= 36: holding
[12:08:25] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:08:25] qa workers 1/3: load 51.65234375 >= 36: holding
[12:08:25] qa workers 1/3: load 51.65234375 >= 36: holding
[12:08:25] build workers 3/10: load 51.65234375 >= 36: holding
[12:09:01] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:09:01] qa workers: gates 18 >= 6: holding
[12:09:01] qa workers: gates 19 >= 6: holding
[12:09:01] build workers: gates 18 >= 6: holding
[12:09:37] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:09:37] qa workers: gates 10 >= 6: holding
[12:09:37] qa workers: gates 10 >= 6: holding
[12:09:37] build workers: gates 10 >= 6: holding
[12:10:12] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:10:12] qa workers: gates 15 >= 6: holding
[12:10:12] qa workers: gates 13 >= 6: holding
[12:10:12] build workers: gates 14 >= 6: holding
[12:10:46] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:10:46] qa workers: gates 10 >= 6: holding
[12:10:47] qa workers: gates 10 >= 6: holding
[12:10:47] build workers: gates 10 >= 6: holding
[12:11:22] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:11:22] qa workers: gates 22 >= 6: holding
[12:11:22] qa workers: gates 23 >= 6: holding
[12:11:23] build workers: gates 22 >= 6: holding
[12:11:58] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:11:59] qa workers: gates 12 >= 6: holding
[12:11:59] qa workers: gates 12 >= 6: holding
[12:11:59] build workers: gates 12 >= 6: holding
kept card 200: live build lane (pid 36566) holds it
[12:12:38] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
kept card 306: live qa lane (pid 43981) holds it
kept card 291: live build lane (pid 98629) holds it
[12:12:38] qa workers: gates 11 >= 6: holding
[12:12:38] qa workers: gates 9 >= 6: holding
[12:12:38] build workers: gates 10 >= 6: holding
[12:13:15] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:13:15] qa workers: gates 7 >= 6: holding
[12:13:15] qa workers: gates 7 >= 6: holding
[12:13:15] build workers: gates 6 >= 6: holding
[12:13:50] tick — Ready=4 Building=3 QA=1 Review=0 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:13:50] qa workers: gates 7 >= 6: holding
[12:13:50] qa workers: gates 7 >= 6: holding
[12:13:50] build workers: gates 6 >= 6: holding
[12:14:26] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=0(#306) q_workers=1/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:14:26] qa workers: gates 8 >= 6: holding
[12:14:26] build workers: gates 10 >= 6: holding
[12:14:57] worker of #306 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1247s
[12:14:59] reaped stale lock + swept assignee on #306 (pid=43981)
[12:15:03] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[12:15:10] dispatch lane=review issue=#306 pid=12887 claim=ToanMobile
[12:15:10] build workers: gates 7 >= 6: holding
[12:15:46] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +46635:307 98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:15:46] review workers 1/3: load 37.1376953125 >= 36: holding
[12:15:46] build workers 3/10: load 37.1376953125 >= 36: holding
[12:16:18] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=7725s
[12:16:21] reaped stale lock + swept assignee on #307 (pid=46635)
[12:16:38] ↩ stranded #307: Building → Ready (branch none)
[12:16:41] tick — Ready=5 Building=2 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=2/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:16:41] review workers: gates 9 >= 6: holding
[12:16:41] build workers: gates 10 >= 6: holding
[12:17:17] tick — Ready=5 Building=2 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=2/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:17:17] build workers 2/10, load 19.5224609375 < 36: starting #3
[12:17:33] dispatch lane=build issue=#228 pid=54496 claim=ToanMobile
[12:18:08] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:18:08] review workers: gates 14 >= 6: holding
[12:18:08] build workers: gates 14 >= 6: holding
[12:18:46] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:18:46] review workers: gates 9 >= 6: holding
[12:18:46] build workers: gates 9 >= 6: holding
[12:19:25] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:19:25] review workers: gates 9 >= 6: holding
[12:19:25] build workers: gates 10 >= 6: holding
[12:20:06] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:20:07] review workers: gates 8 >= 6: holding
[12:20:07] build workers: gates 9 >= 6: holding
[12:20:46] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:20:46] review workers 1/3: load 94.22119140625 >= 36: holding
[12:20:46] build workers 3/10: load 94.22119140625 >= 36: holding
[12:21:25] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:21:25] review workers 1/3: load 67.296875 >= 36: holding
[12:21:25] build workers: gates 6 >= 6: holding
[12:22:02] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:22:02] review workers 1/3: load 53.61083984375 >= 36: holding
[12:22:02] build workers: gates 6 >= 6: holding
kept card 306: live review lane (pid 12887) holds it
[12:22:38] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:22:38] review workers 1/3: load 41.94189453125 >= 36: holding
[12:22:39] build workers 3/10: load 41.94189453125 >= 36: holding
kept card 200: live build lane (pid 36566) holds it
kept card 228: live build lane (pid 54496) holds it
kept card 291: live build lane (pid 98629) holds it
[12:23:16] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:23:16] review workers: gates 6 >= 6: holding
[12:23:16] build workers: gates 6 >= 6: holding
[12:23:54] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:23:54] review workers: gates 15 >= 6: holding
[12:23:54] build workers: gates 15 >= 6: holding
[12:24:31] tick — Ready=4 Building=3 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200) b_workers=3/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:24:31] build workers 3/10, load 34.61181640625 < 36: starting #4
[12:24:45] dispatch lane=build issue=#307 pid=86992 claim=ToanMobile
[12:25:20] tick — Ready=3 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +98629:291 36566:200 86992:307) b_workers=4/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:25:20] build workers 4/10, load 20.9130859375 < 36: starting #5
[12:25:36] dispatch lane=build issue=#308 pid=37244 claim=ToanMobile
[12:26:06] worker of #291 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=8237s
[12:26:09] reaped stale lock + swept assignee on #291 (pid=98629)
[12:26:15] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#306) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:26:15] review workers: gates 20 >= 6: holding
[12:26:21] dispatch lane=qa issue=#291 pid=78724 claim=ToanMobile
[12:26:21] build workers: gates 13 >= 6: holding
[12:26:56] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:26:57] review workers: gates 14 >= 6: holding
[12:26:57] qa workers: gates 13 >= 6: holding
[12:26:57] qa workers: gates 14 >= 6: holding
[12:26:57] build workers: gates 14 >= 6: holding
[12:27:36] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:27:36] review workers: gates 23 >= 6: holding
[12:27:36] qa workers: gates 23 >= 6: holding
[12:27:36] qa workers: gates 24 >= 6: holding
[12:27:36] build workers: gates 23 >= 6: holding
[12:28:17] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:28:17] review workers: gates 15 >= 6: holding
[12:28:17] qa workers: gates 14 >= 6: holding
[12:28:18] qa workers: gates 14 >= 6: holding
[12:28:18] build workers: gates 14 >= 6: holding
[12:28:56] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:28:56] review workers: gates 11 >= 6: holding
[12:28:56] qa workers: gates 13 >= 6: holding
[12:28:56] qa workers: gates 11 >= 6: holding
[12:28:56] build workers: gates 11 >= 6: holding
[12:29:36] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:29:36] review workers: gates 7 >= 6: holding
[12:29:36] qa workers: gates 8 >= 6: holding
[12:29:36] qa workers: gates 9 >= 6: holding
[12:29:36] build workers: gates 9 >= 6: holding
[12:30:14] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:30:14] review workers: gates 8 >= 6: holding
[12:30:14] qa workers: gates 8 >= 6: holding
[12:30:14] qa workers: gates 8 >= 6: holding
[12:30:14] build workers: gates 8 >= 6: holding
[12:30:50] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:30:50] review workers: gates 9 >= 6: holding
[12:30:50] qa workers: gates 9 >= 6: holding
[12:30:50] qa workers: gates 8 >= 6: holding
[12:30:51] build workers: gates 9 >= 6: holding
[12:31:31] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:31:31] review workers: gates 19 >= 6: holding
[12:31:31] qa workers: gates 20 >= 6: holding
[12:31:32] qa workers: gates 20 >= 6: holding
[12:31:32] build workers: gates 19 >= 6: holding
[12:32:11] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:32:11] review workers: gates 29 >= 6: holding
[12:32:11] qa workers: gates 27 >= 6: holding
[12:32:12] qa workers: gates 27 >= 6: holding
[12:32:12] build workers: gates 29 >= 6: holding
kept card 307: live build lane (pid 86992) holds it
[12:32:51] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:32:51] review workers: gates 22 >= 6: holding
[12:32:51] qa workers: gates 20 >= 6: holding
[12:32:51] qa workers: gates 20 >= 6: holding
[12:32:51] build workers: gates 21 >= 6: holding
kept card 306: live review lane (pid 12887) holds it
kept card 228: live build lane (pid 54496) holds it
kept card 200: live build lane (pid 36566) holds it
kept card 308: live build lane (pid 37244) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[12:33:29] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:33:29] review workers: gates 13 >= 6: holding
[12:33:29] qa workers: gates 13 >= 6: holding
[12:33:29] qa workers: gates 13 >= 6: holding
[12:33:29] build workers: gates 13 >= 6: holding
[12:34:05] tick — Ready=2 Building=4 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=0(#291) q_workers=1/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:34:05] review workers: gates 16 >= 6: holding
[12:34:06] qa workers: gates 16 >= 6: holding
[12:34:06] qa workers: gates 15 >= 6: holding
[12:34:06] build workers: gates 14 >= 6: holding
[12:34:36] worker of #291 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=487s
[12:34:39] reaped stale lock + swept assignee on #291 (pid=78724)
[12:34:48] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#306) r_workers=1/3 waiting_on_you=0
[12:34:48] review workers: gates 11 >= 6: holding
[12:34:48] build workers: gates 13 >= 6: holding
[12:35:21] worker of #306 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1195s
[12:35:23] reaped stale lock + swept assignee on #306 (pid=12887)
[12:35:28] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=1(#306) r_workers=0/3 waiting_on_you=0
[12:35:37] dispatch lane=review issue=#291 pid=23295 claim=ToanMobile
[12:35:37] build workers: gates 12 >= 6: holding
[12:36:16] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:36:16] review workers: gates 15 >= 6: holding
[12:36:16] build workers: gates 14 >= 6: holding
[12:36:56] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:36:56] review workers: gates 14 >= 6: holding
[12:36:56] build workers: gates 15 >= 6: holding
[12:37:34] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:37:34] review workers: gates 6 >= 6: holding
[12:37:34] build workers: gates 6 >= 6: holding
[12:38:12] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:38:12] review workers: gates 7 >= 6: holding
[12:38:12] build workers: gates 7 >= 6: holding
[12:38:50] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:38:50] review workers: gates 6 >= 6: holding
[12:38:50] build workers: gates 6 >= 6: holding
[12:39:30] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:39:30] review workers: gates 16 >= 6: holding
[12:39:30] build workers: gates 15 >= 6: holding
[12:40:10] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:40:10] review workers: gates 9 >= 6: holding
[12:40:10] build workers: gates 9 >= 6: holding
[12:40:51] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:40:51] review workers: gates 19 >= 6: holding
[12:40:52] build workers: gates 18 >= 6: holding
[12:41:32] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:41:32] review workers: gates 21 >= 6: holding
[12:41:33] build workers: gates 17 >= 6: holding
[12:42:12] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:42:12] review workers: gates 7 >= 6: holding
[12:42:12] build workers: gates 8 >= 6: holding
[12:42:58] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:42:58] review workers: gates 27 >= 6: holding
[12:42:59] build workers: gates 25 >= 6: holding
kept card 200: live build lane (pid 36566) holds it
kept card 307: live build lane (pid 86992) holds it
kept card 291: live review lane (pid 23295) holds it
kept card 308: live build lane (pid 37244) holds it
[12:43:43] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:43:43] review workers: gates 8 >= 6: holding
[12:43:44] build workers: gates 8 >= 6: holding
[12:44:25] tick — Ready=2 Building=4 QA=0 Review=1 Blocked=7 lanes: b_idle=0(#228 +36566:200 86992:307 37244:308) b_workers=4/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:44:26] review workers: gates 7 >= 6: holding
[12:44:26] build workers: gates 7 >= 6: holding
[12:45:07] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=1(#291) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:45:08] review workers: gates 16 >= 6: holding
[12:45:08] worker of #200 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=9214s
[12:45:16] dispatch lane=qa issue=#200 pid=15636 claim=ToanMobile
[12:45:16] build workers: gates 11 >= 6: holding
[12:45:53] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:45:53] review workers: gates 7 >= 6: holding
[12:45:53] qa workers: gates 7 >= 6: holding
[12:45:53] qa workers: gates 7 >= 6: holding
[12:45:53] build workers: gates 8 >= 6: holding
[12:46:31] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:46:31] review workers: gates 19 >= 6: holding
[12:46:31] qa workers: gates 22 >= 6: holding
[12:46:32] qa workers: gates 20 >= 6: holding
[12:46:32] build workers: gates 23 >= 6: holding
[12:47:07] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:47:07] review workers: gates 8 >= 6: holding
[12:47:07] qa workers: gates 8 >= 6: holding
[12:47:07] qa workers: gates 8 >= 6: holding
[12:47:07] build workers: gates 8 >= 6: holding
[12:47:45] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:47:45] review workers: gates 14 >= 6: holding
[12:47:45] qa workers: gates 14 >= 6: holding
[12:47:45] qa workers: gates 14 >= 6: holding
[12:47:46] build workers: gates 13 >= 6: holding
[12:48:23] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:48:23] review workers: gates 15 >= 6: holding
[12:48:24] qa workers: gates 15 >= 6: holding
[12:48:24] qa workers: gates 13 >= 6: holding
[12:48:24] build workers: gates 14 >= 6: holding
[12:49:02] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:49:02] review workers: gates 10 >= 6: holding
[12:49:03] qa workers: gates 10 >= 6: holding
[12:49:03] qa workers: gates 9 >= 6: holding
[12:49:03] build workers: gates 10 >= 6: holding
[12:49:46] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:49:46] review workers: gates 17 >= 6: holding
[12:49:47] qa workers: gates 19 >= 6: holding
[12:49:47] qa workers: gates 18 >= 6: holding
[12:49:47] build workers: gates 16 >= 6: holding
[12:50:27] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:50:27] review workers: gates 12 >= 6: holding
[12:50:27] qa workers: gates 12 >= 6: holding
[12:50:28] qa workers: gates 10 >= 6: holding
[12:50:28] build workers: gates 11 >= 6: holding
[12:51:11] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:51:11] review workers: gates 13 >= 6: holding
[12:51:11] qa workers: gates 10 >= 6: holding
[12:51:12] qa workers: gates 11 >= 6: holding
[12:51:12] build workers: gates 11 >= 6: holding
[12:51:54] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:51:54] review workers: gates 10 >= 6: holding
[12:51:54] qa workers: gates 10 >= 6: holding
[12:51:54] qa workers: gates 10 >= 6: holding
[12:51:55] build workers: gates 9 >= 6: holding
[12:52:37] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:52:37] review workers: gates 10 >= 6: holding
[12:52:37] qa workers: gates 11 >= 6: holding
[12:52:37] qa workers: gates 11 >= 6: holding
[12:52:38] build workers: gates 11 >= 6: holding
kept card 291: live review lane (pid 23295) holds it
kept card 308: live build lane (pid 37244) holds it
[12:53:20] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:53:20] review workers: gates 10 >= 6: holding
[12:53:21] qa workers: gates 10 >= 6: holding
[12:53:21] qa workers: gates 9 >= 6: holding
[12:53:22] build workers: gates 9 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 200: live qa lane (pid 15636) holds it
kept card 228: live build lane (pid 54496) holds it
kept card 307: live build lane (pid 86992) holds it
[12:54:05] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:54:06] review workers: gates 15 >= 6: holding
[12:54:06] qa workers: gates 14 >= 6: holding
[12:54:06] qa workers: gates 15 >= 6: holding
[12:54:06] build workers: gates 15 >= 6: holding
[12:54:47] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:54:47] review workers: gates 12 >= 6: holding
[12:54:47] qa workers: gates 12 >= 6: holding
[12:54:47] qa workers: gates 13 >= 6: holding
[12:54:48] build workers: gates 13 >= 6: holding
[12:55:29] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:55:29] review workers: gates 21 >= 6: holding
[12:55:29] qa workers: gates 21 >= 6: holding
[12:55:29] qa workers: gates 20 >= 6: holding
[12:55:30] build workers: gates 20 >= 6: holding
[12:56:12] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:56:12] review workers: gates 17 >= 6: holding
[12:56:12] qa workers: gates 19 >= 6: holding
[12:56:12] qa workers: gates 16 >= 6: holding
[12:56:13] build workers: gates 15 >= 6: holding
[12:56:53] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:56:53] review workers: gates 12 >= 6: holding
[12:56:53] qa workers: gates 12 >= 6: holding
[12:56:53] qa workers: gates 12 >= 6: holding
[12:56:53] build workers: gates 12 >= 6: holding
[12:57:33] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:57:34] review workers: gates 11 >= 6: holding
[12:57:34] qa workers: gates 12 >= 6: holding
[12:57:34] qa workers: gates 12 >= 6: holding
[12:57:34] build workers: gates 12 >= 6: holding
[12:58:15] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:58:15] review workers: gates 11 >= 6: holding
[12:58:15] qa workers: gates 10 >= 6: holding
[12:58:16] qa workers: gates 10 >= 6: holding
[12:58:16] build workers: gates 10 >= 6: holding
[12:58:58] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:58:58] review workers: gates 16 >= 6: holding
[12:58:59] qa workers: gates 18 >= 6: holding
[12:58:59] qa workers: gates 18 >= 6: holding
[12:58:59] build workers: gates 20 >= 6: holding
[12:59:39] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[12:59:39] review workers: gates 14 >= 6: holding
[12:59:39] qa workers: gates 16 >= 6: holding
[12:59:40] qa workers: gates 16 >= 6: holding
[12:59:40] build workers: gates 15 >= 6: holding
[13:00:20] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:00:20] review workers: gates 10 >= 6: holding
[13:00:20] qa workers: gates 11 >= 6: holding
[13:00:20] qa workers: gates 11 >= 6: holding
[13:00:20] build workers: gates 11 >= 6: holding
[13:00:55] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:00:55] review workers 1/3: load 77.14306640625 >= 36: holding
[13:00:56] qa workers 1/3: load 77.14306640625 >= 36: holding
[13:00:56] qa workers 1/3: load 77.14306640625 >= 36: holding
[13:00:56] build workers 3/10: load 77.14306640625 >= 36: holding
[13:01:31] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:01:31] review workers 1/3: load 59.3955078125 >= 36: holding
[13:01:31] qa workers 1/3: load 59.3955078125 >= 36: holding
[13:01:31] qa workers 1/3: load 59.3955078125 >= 36: holding
[13:01:31] build workers 3/10: load 59.3955078125 >= 36: holding
[13:02:09] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:02:09] review workers: gates 24 >= 6: holding
[13:02:09] qa workers: gates 24 >= 6: holding
[13:02:09] qa workers: gates 22 >= 6: holding
[13:02:09] build workers: gates 22 >= 6: holding
[13:02:44] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:02:44] review workers: gates 6 >= 6: holding
[13:02:44] qa workers: gates 6 >= 6: holding
[13:02:44] qa workers: gates 6 >= 6: holding
[13:02:44] build workers: gates 6 >= 6: holding
kept card 307: live build lane (pid 86992) holds it
kept card 228: live build lane (pid 54496) holds it
[13:03:18] tick — Ready=2 Building=3 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#228 +86992:307 37244:308) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:03:18] build workers 3/10, load 25.41259765625 < 36: starting #4
kept card 291: live review lane (pid 23295) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 308: live build lane (pid 37244) holds it
[13:03:37] dispatch lane=build issue=#309 pid=66937 claim=ToanMobile
[13:04:08] worker of #308 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2284s
[13:04:12] reaped stale lock + swept assignee on #308 (pid=37244)
[13:04:20] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#200) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:04:20] review workers: gates 12 >= 6: holding
[13:04:20] qa workers: gates 13 >= 6: holding
[13:04:21] qa workers: gates 14 >= 6: holding
[13:04:21] build workers: gates 13 >= 6: holding
[13:04:52] worker of #200 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1166s
[13:04:56] reaped stale lock + swept assignee on #200 (pid=15636)
[13:05:07] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#200) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:05:07] review workers: gates 13 >= 6: holding
[13:05:19] dispatch lane=qa issue=#308 pid=11621 claim=ToanMobile
[13:05:19] build workers: gates 12 >= 6: holding
[13:05:58] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:05:58] review workers: gates 15 >= 6: holding
[13:05:58] qa workers: gates 15 >= 6: holding
[13:05:58] qa workers: gates 15 >= 6: holding
[13:05:58] build workers: gates 15 >= 6: holding
[13:06:38] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:06:38] review workers: gates 8 >= 6: holding
[13:06:38] qa workers: gates 10 >= 6: holding
[13:06:38] qa workers: gates 11 >= 6: holding
[13:06:39] build workers: gates 10 >= 6: holding
[13:07:17] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:07:17] review workers: gates 7 >= 6: holding
[13:07:17] qa workers: gates 8 >= 6: holding
[13:07:17] qa workers: gates 9 >= 6: holding
[13:07:17] build workers: gates 10 >= 6: holding
[13:07:57] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:07:57] review workers: gates 14 >= 6: holding
[13:07:57] qa workers: gates 15 >= 6: holding
[13:07:57] qa workers: gates 14 >= 6: holding
[13:07:57] build workers: gates 14 >= 6: holding
[13:08:39] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:08:40] review workers: gates 24 >= 6: holding
[13:08:40] qa workers: gates 23 >= 6: holding
[13:08:40] qa workers: gates 26 >= 6: holding
[13:08:40] build workers: gates 28 >= 6: holding
[13:09:19] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:09:19] review workers: gates 15 >= 6: holding
[13:09:19] qa workers: gates 14 >= 6: holding
[13:09:20] qa workers: gates 14 >= 6: holding
[13:09:20] build workers: gates 12 >= 6: holding
[13:09:57] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:09:57] review workers: gates 14 >= 6: holding
[13:09:57] qa workers: gates 14 >= 6: holding
[13:09:58] qa workers: gates 14 >= 6: holding
[13:09:58] build workers: gates 14 >= 6: holding
[13:10:37] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:10:37] review workers: gates 14 >= 6: holding
[13:10:37] qa workers: gates 13 >= 6: holding
[13:10:37] qa workers: gates 14 >= 6: holding
[13:10:37] build workers: gates 12 >= 6: holding
[13:11:16] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:11:16] review workers: gates 8 >= 6: holding
[13:11:16] qa workers: gates 8 >= 6: holding
[13:11:16] qa workers: gates 8 >= 6: holding
[13:11:17] build workers: gates 8 >= 6: holding
[13:11:52] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:11:52] review workers 1/3: load 46.65576171875 >= 36: holding
[13:11:52] qa workers 1/3: load 46.65576171875 >= 36: holding
[13:11:52] qa workers 1/3: load 46.65576171875 >= 36: holding
[13:11:52] build workers 3/10: load 46.65576171875 >= 36: holding
[13:12:29] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:12:29] review workers: gates 13 >= 6: holding
[13:12:29] qa workers: gates 13 >= 6: holding
[13:12:29] qa workers: gates 13 >= 6: holding
[13:12:29] build workers: gates 12 >= 6: holding
[13:13:04] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:13:04] review workers 1/3: load 39.20458984375 >= 36: holding
[13:13:04] qa workers 1/3: load 39.20458984375 >= 36: holding
[13:13:04] qa workers 1/3: load 39.20458984375 >= 36: holding
[13:13:04] build workers 3/10: load 39.20458984375 >= 36: holding
kept card 307: live build lane (pid 86992) holds it
[13:13:39] tick — Ready=1 Building=3 QA=1 Review=2 Blocked=7 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:13:46] dispatch lane=review issue=#200 pid=87938 claim=ToanMobile
[13:13:46] build workers 3/10, load 23.6611328125 < 36: starting #4
kept card 291: live review lane (pid 23295) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
[13:13:58] preflight sequence/overlap for #304: open PRs touch the same files — build after them — not dispatched, card to Blocked
[13:14:37] tick — Ready=0 Building=3 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:15:14] tick — Ready=0 Building=3 QA=1 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:15:14] review workers: gates 11 >= 6: holding
[13:15:15] qa workers: gates 11 >= 6: holding
[13:15:15] qa workers: gates 11 >= 6: holding
[13:15:51] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=0(#308) q_workers=1/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:15:51] review workers: gates 11 >= 6: holding
[13:15:51] qa workers: gates 12 >= 6: holding
[13:16:22] worker of #308 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=643s
[13:16:25] reaped stale lock + swept assignee on #308 (pid=11621)
[13:16:31] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:16:31] review workers: gates 14 >= 6: holding
[13:17:13] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:17:13] review workers: gates 10 >= 6: holding
[13:17:54] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:17:54] review workers: gates 16 >= 6: holding
[13:18:35] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:18:35] review workers: gates 10 >= 6: holding
[13:19:17] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:19:17] review workers: gates 17 >= 6: holding
[13:19:57] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:19:57] review workers: gates 10 >= 6: holding
[13:20:36] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:20:36] review workers: gates 12 >= 6: holding
[13:21:16] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:21:16] review workers: gates 12 >= 6: holding
[13:21:54] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:21:54] review workers: gates 10 >= 6: holding
[13:22:30] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:22:30] review workers 2/3: load 51.8984375 >= 36: holding
[13:23:06] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:23:06] review workers: gates 9 >= 6: holding
[13:23:41] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
kept card 309: live build lane (pid 66937) holds it
kept card 307: live build lane (pid 86992) holds it
kept card 291: live review lane (pid 23295) holds it
kept card 200: live review lane (pid 87938) holds it
[13:23:48] dispatch lane=review issue=#308 pid=23598 claim=ToanMobile
kept card 228: live build lane (pid 54496) holds it
[13:24:23] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:24:23] review workers 3/3: at the cap, not starting
[13:25:00] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:25:00] review workers 3/3: at the cap, not starting
[13:25:37] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:25:37] review workers 3/3: at the cap, not starting
[13:26:14] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:26:14] review workers 3/3: at the cap, not starting
[13:26:49] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:26:49] review workers 3/3: at the cap, not starting
[13:27:26] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:27:26] review workers 3/3: at the cap, not starting
[13:28:03] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:28:04] review workers 3/3: at the cap, not starting
[13:28:39] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:28:39] review workers 3/3: at the cap, not starting
[13:29:15] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=3/3 waiting_on_you=0
[13:29:15] review workers 3/3: at the cap, not starting
[13:29:46] worker of #291 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=3230s
[13:29:49] reaped stale lock + swept assignee on #291 (pid=23295)
[13:29:58] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=2/3 waiting_on_you=0
[13:29:58] review workers: gates 18 >= 6: holding
[13:30:38] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=2/3 waiting_on_you=0
[13:30:38] review workers: gates 17 >= 6: holding
[13:31:18] tick — Ready=0 Building=3 QA=0 Review=3 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200 23598:308) r_workers=2/3 waiting_on_you=0
[13:31:18] review workers: gates 18 >= 6: holding
[13:32:06] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:32:06] review workers: gates 16 >= 6: holding
[13:32:39] worker of #308 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=489s
[13:32:43] reaped stale lock + swept assignee on #308 (pid=23598)
[13:32:53] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:32:53] review workers: gates 16 >= 6: holding
[13:33:38] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:33:38] review workers: gates 15 >= 6: holding
[13:34:24] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:34:24] review workers: gates 13 >= 6: holding
kept card 307: live build lane (pid 86992) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 200: live review lane (pid 87938) holds it
kept card 309: live build lane (pid 66937) holds it
[13:35:03] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:35:03] review workers: gates 7 >= 6: holding
[13:35:42] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:35:43] review workers: gates 7 >= 6: holding
[13:36:21] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:36:21] review workers: gates 6 >= 6: holding
[13:36:57] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:36:57] review workers: gates 6 >= 6: holding
[13:37:36] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:37:36] review workers: gates 17 >= 6: holding
[13:38:13] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:38:13] review workers: gates 8 >= 6: holding
[13:38:49] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=1/3 waiting_on_you=0
[13:38:56] dispatch lane=review issue=#291 pid=47733 claim=ToanMobile
[13:39:33] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:39:33] review workers: gates 13 >= 6: holding
[13:40:08] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:40:45] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:40:45] review workers: gates 11 >= 6: holding
[13:41:21] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:41:21] review workers: gates 16 >= 6: holding
[13:41:59] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:41:59] review workers: gates 12 >= 6: holding
[13:42:35] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:42:35] review workers: gates 6 >= 6: holding
[13:43:10] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:43:10] review workers: gates 17 >= 6: holding
[13:43:46] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:43:46] review workers: gates 8 >= 6: holding
[13:44:21] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
kept card 307: live build lane (pid 86992) holds it
kept card 309: live build lane (pid 66937) holds it
kept card 228: live build lane (pid 54496) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 291: live review lane (pid 47733) holds it
[13:45:07] tick — Ready=0 Building=3 QA=0 Review=2 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:45:07] review workers: gates 15 >= 6: holding
[13:45:47] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:45:47] review workers: gates 10 >= 6: holding
[13:46:22] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291 +87938:200) r_workers=2/3 waiting_on_you=0
[13:46:54] 💀 zombie review worker on #200 (pid=87938) — card moved to 'Done'; killing
[13:47:04] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:47:04] review workers: gates 15 >= 6: holding
[13:47:51] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:47:52] review workers: gates 23 >= 6: holding
[13:48:35] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:48:35] review workers: gates 15 >= 6: holding
[13:49:14] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:49:14] review workers: gates 12 >= 6: holding
[13:49:53] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:49:53] review workers: gates 7 >= 6: holding
[13:50:36] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:50:36] review workers: gates 14 >= 6: holding
[13:51:19] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:51:19] review workers: gates 11 >= 6: holding
[13:51:59] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:51:59] review workers: gates 10 >= 6: holding
[13:52:40] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:52:40] review workers: gates 8 >= 6: holding
[13:53:20] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:53:20] review workers: gates 8 >= 6: holding
[13:54:02] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:54:02] review workers: gates 11 >= 6: holding
kept card 291: live review lane (pid 47733) holds it
[13:54:46] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:54:47] review workers: gates 17 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 307: live build lane (pid 86992) holds it
kept card 228: live build lane (pid 54496) holds it
kept card 309: live build lane (pid 66937) holds it
[13:55:30] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:55:31] review workers: gates 11 >= 6: holding
[13:56:22] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:56:22] review workers: gates 10 >= 6: holding
[13:57:10] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:57:11] review workers: gates 12 >= 6: holding
[13:57:55] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:57:55] review workers: gates 11 >= 6: holding
[13:58:40] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:58:41] review workers: gates 9 >= 6: holding
[13:59:26] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[13:59:27] review workers: gates 8 >= 6: holding
[14:00:12] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:00:12] review workers: gates 8 >= 6: holding
[14:00:54] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:00:55] review workers: gates 8 >= 6: holding
[14:01:30] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:01:30] review workers 1/3: load 82.11083984375 >= 36: holding
[14:02:07] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:02:07] review workers: gates 13 >= 6: holding
[14:02:47] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:02:47] review workers: gates 26 >= 6: holding
[14:03:23] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:03:23] review workers: gates 9 >= 6: holding
[14:03:58] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:03:58] review workers 1/3: load 47.3076171875 >= 36: holding
[14:04:33] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:04:33] review workers: gates 14 >= 6: holding
kept card 307: live build lane (pid 86992) holds it
[14:05:08] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:05:08] review workers: gates 9 >= 6: holding
kept card 291: live review lane (pid 47733) holds it
kept card 309: live build lane (pid 66937) holds it
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 228: live build lane (pid 54496) holds it
[14:05:45] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:05:45] review workers: gates 11 >= 6: holding
[14:06:22] tick — Ready=0 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:06:22] review workers: gates 11 >= 6: holding
[14:06:58] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:06:58] review workers: gates 7 >= 6: holding
[14:07:38] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:07:38] review workers: gates 15 >= 6: holding
[14:08:16] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:08:16] review workers: gates 10 >= 6: holding
[14:08:54] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:08:54] review workers: gates 11 >= 6: holding
[14:09:31] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:09:31] review workers: gates 10 >= 6: holding
[14:10:06] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:10:41] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:11:16] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:11:50] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307 66937:309) b_workers=3/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:12:22] worker of #309 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4110s
[14:12:26] reaped stale lock + swept assignee on #309 (pid=66937)
[14:12:35] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#308) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:12:44] dispatch lane=qa issue=#309 pid=4869 claim=ToanMobile
[14:13:22] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:13:22] review workers 1/3: load 46.17138671875 >= 36: holding
[14:13:22] qa workers 1/3: load 46.17138671875 >= 36: holding
[14:13:22] qa workers 1/3: load 46.17138671875 >= 36: holding
[14:14:05] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:14:05] review workers: gates 16 >= 6: holding
[14:14:05] qa workers: gates 14 >= 6: holding
[14:14:05] qa workers: gates 15 >= 6: holding
[14:14:44] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:14:44] review workers: gates 6 >= 6: holding
[14:14:44] qa workers: gates 6 >= 6: holding
[14:14:44] qa workers: gates 6 >= 6: holding
[14:15:20] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:15:20] review workers: gates 6 >= 6: holding
[14:15:20] qa workers: gates 6 >= 6: holding
[14:15:20] qa workers 1/3: load 43.72509765625 >= 36: holding
kept card 309: live qa lane (pid 4869) holds it
kept card 307: live build lane (pid 86992) holds it
[14:15:57] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:15:57] review workers: gates 15 >= 6: holding
[14:15:57] qa workers: gates 15 >= 6: holding
[14:15:57] qa workers: gates 15 >= 6: holding
[14:16:32] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:17:07] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=0(#309) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:17:38] worker of #309 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=274s
[14:17:42] reaped stale lock + swept assignee on #309 (pid=4869)
[14:17:50] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:17:50] review workers: gates 11 >= 6: holding
[14:18:37] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:18:38] review workers: gates 21 >= 6: holding
[14:19:20] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:19:20] review workers: gates 14 >= 6: holding
[14:20:09] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:20:09] review workers: gates 13 >= 6: holding
[14:21:06] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:21:06] review workers: gates 15 >= 6: holding
[14:21:53] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:21:53] review workers: gates 12 >= 6: holding
[14:22:40] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:22:41] review workers: gates 10 >= 6: holding
[14:23:25] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:23:25] review workers: gates 9 >= 6: holding
[14:24:14] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:24:15] review workers: gates 8 >= 6: holding
[14:25:03] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:25:03] review workers: gates 6 >= 6: holding
[14:25:48] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:25:49] review workers: gates 8 >= 6: holding
kept /Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-216-build: on branch issue-216-merge-gate-dead-holder, HEAD de7d003f550211b69a2be72b4f7015d3ef7a9120 is not the head of a merged PR of card 216
kept card 291: live review lane (pid 47733) holds it
kept card 307: live build lane (pid 86992) holds it
[14:26:38] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:26:38] review workers: gates 9 >= 6: holding
[14:27:27] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:27:27] review workers: gates 9 >= 6: holding
[14:28:14] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:28:14] review workers: gates 6 >= 6: holding
[14:29:00] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:29:01] review workers: gates 9 >= 6: holding
[14:29:45] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:29:45] review workers: gates 12 >= 6: holding
[14:30:36] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:30:37] review workers: gates 10 >= 6: holding
[14:31:17] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:31:18] review workers: gates 17 >= 6: holding
[14:31:51] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:31:52] review workers 1/3: load 46.36474609375 >= 36: holding
[14:32:25] tick — Ready=0 Building=2 QA=0 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:32:34] dispatch lane=review issue=#309 pid=9470 claim=ToanMobile
[14:33:09] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:33:09] review workers 2/3: load 38.408203125 >= 36: holding
[14:33:42] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:34:16] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:34:55] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:34:56] review workers 2/3: load 41.728515625 >= 36: holding
[14:35:33] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:35:34] review workers: gates 14 >= 6: holding
[14:36:13] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:36:13] review workers: gates 9 >= 6: holding
kept card 291: live review lane (pid 47733) holds it
kept card 307: live build lane (pid 86992) holds it
kept card 228: live build lane (pid 54496) holds it
[14:36:52] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:36:52] review workers: gates 15 >= 6: holding
[14:37:28] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:37:28] review workers: gates 12 >= 6: holding
[14:38:07] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:38:07] review workers: gates 13 >= 6: holding
[14:38:43] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:38:43] review workers: gates 13 >= 6: holding
[14:39:20] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:39:20] review workers: gates 17 >= 6: holding
[14:39:57] tick — Ready=0 Building=1 QA=1 Review=2 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=2/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:39:57] review workers: gates 12 >= 6: holding
[14:40:35] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=1(#309) q_workers=0/3 r_idle=0(#291 +9470:309) r_workers=2/3 waiting_on_you=0
[14:40:35] review workers: gates 14 >= 6: holding
[14:40:36] worker of #228 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=8578s
[14:40:43] dispatch lane=qa issue=#228 pid=77414 claim=ToanMobile
[14:41:15] worker of #309 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=498s
[14:41:18] reaped stale lock + swept assignee on #309 (pid=9470)
[14:41:22] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:41:22] review workers: gates 16 >= 6: holding
[14:41:22] qa workers: gates 12 >= 6: holding
[14:41:23] qa workers: gates 15 >= 6: holding
[14:41:58] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:41:58] review workers: gates 15 >= 6: holding
[14:41:58] qa workers: gates 15 >= 6: holding
[14:41:58] qa workers: gates 15 >= 6: holding
[14:42:33] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:42:33] review workers: gates 7 >= 6: holding
[14:42:33] qa workers: gates 7 >= 6: holding
[14:42:33] qa workers: gates 7 >= 6: holding
[14:43:07] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:43:07] review workers: gates 10 >= 6: holding
[14:43:07] qa workers: gates 10 >= 6: holding
[14:43:07] qa workers: gates 10 >= 6: holding
[14:43:45] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:43:45] review workers: gates 13 >= 6: holding
[14:43:45] qa workers: gates 13 >= 6: holding
[14:43:45] qa workers: gates 13 >= 6: holding
[14:44:19] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:44:55] tick — Ready=0 Building=1 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#228 +86992:307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:44:55] review workers: gates 26 >= 6: holding
[14:44:55] qa workers: gates 25 >= 6: holding
[14:44:55] qa workers: gates 29 >= 6: holding
[14:45:28] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=8435s
[14:45:32] reaped stale lock + swept assignee on #307 (pid=86992)
[14:45:53] ↩ stranded #307: Building → Ready (branch none)
[14:45:55] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=5 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:45:55] review workers: gates 14 >= 6: holding
[14:45:55] qa workers: gates 14 >= 6: holding
[14:45:55] qa workers: gates 14 >= 6: holding
[14:45:55] build workers: gates 14 >= 6: holding
[14:46:29] tick — Ready=1 Building=0 QA=1 Review=1 Blocked=5 lanes: b_idle=1(#228) b_workers=0/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:46:30] review workers 1/3: load 84.7646484375 >= 36: holding
[14:46:30] qa workers 1/3: load 84.7646484375 >= 36: holding
[14:46:30] qa workers 1/3: load 84.7646484375 >= 36: holding
kept card 291: live review lane (pid 47733) holds it
kept card 228: live qa lane (pid 77414) holds it
[14:46:48] dispatch lane=build issue=#307 pid=74943 claim=ToanMobile
[14:47:21] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=0(#291) r_workers=1/3 waiting_on_you=0
[14:47:21] qa workers 1/3: load 56.04736328125 >= 36: holding
[14:47:21] qa workers 1/3: load 56.04736328125 >= 36: holding
[14:47:52] worker of #291 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=4132s
[14:47:56] reaped stale lock + swept assignee on #291 (pid=47733)
[14:48:04] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:48:05] qa workers: gates 20 >= 6: holding
[14:48:05] qa workers: gates 18 >= 6: holding
[14:48:43] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:48:43] qa workers: gates 10 >= 6: holding
[14:48:43] qa workers: gates 11 >= 6: holding
[14:49:23] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:49:23] qa workers: gates 6 >= 6: holding
[14:49:24] qa workers: gates 7 >= 6: holding
[14:50:00] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:50:00] qa workers: gates 6 >= 6: holding
[14:50:00] qa workers: gates 6 >= 6: holding
[14:50:38] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:50:38] qa workers: gates 23 >= 6: holding
[14:50:39] qa workers: gates 21 >= 6: holding
[14:51:17] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:51:17] qa workers: gates 23 >= 6: holding
[14:51:17] qa workers: gates 22 >= 6: holding
[14:51:53] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:51:54] qa workers: gates 10 >= 6: holding
[14:51:54] qa workers: gates 10 >= 6: holding
[14:52:29] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:52:29] qa workers: gates 24 >= 6: holding
[14:52:30] qa workers: gates 22 >= 6: holding
[14:53:05] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:53:05] qa workers: gates 14 >= 6: holding
[14:53:05] qa workers: gates 15 >= 6: holding
[14:53:41] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:53:41] qa workers: gates 15 >= 6: holding
[14:53:41] qa workers: gates 15 >= 6: holding
[14:54:19] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:54:19] qa workers: gates 16 >= 6: holding
[14:54:19] qa workers: gates 16 >= 6: holding
[14:54:56] tick — Ready=0 Building=1 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:54:56] qa workers: gates 19 >= 6: holding
[14:54:57] qa workers: gates 17 >= 6: holding
[14:55:35] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=0(#228) q_workers=1/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:55:36] qa workers: gates 21 >= 6: holding
[14:56:07] worker of #228 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=893s
[14:56:11] reaped stale lock + swept assignee on #228 (pid=77414)
[14:56:19] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#291) r_workers=0/3 waiting_on_you=0
[14:56:34] dispatch lane=review issue=#228 pid=30186 claim=ToanMobile
[14:57:08] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:57:08] review workers: gates 13 >= 6: holding
kept card 228: live review lane (pid 30186) holds it
[14:57:42] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:57:42] review workers: gates 16 >= 6: holding
[14:58:16] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:58:16] review workers: gates 14 >= 6: holding
[14:58:50] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:58:50] review workers: gates 12 >= 6: holding
[14:59:23] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:59:23] review workers: gates 15 >= 6: holding
[14:59:57] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[14:59:57] review workers: gates 11 >= 6: holding
[15:00:30] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:00:30] review workers 1/3: load 100.07568359375 >= 36: holding
[15:01:03] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:01:03] review workers: gates 6 >= 6: holding
[15:01:39] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:01:39] review workers: gates 9 >= 6: holding
[15:02:14] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:02:14] review workers 1/3: load 73.474609375 >= 36: holding
[15:02:51] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:02:51] review workers: gates 7 >= 6: holding
[15:03:25] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:03:25] review workers: gates 7 >= 6: holding
[15:03:59] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:03:59] review workers 1/3: load 46.99755859375 >= 36: holding
[15:04:34] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:04:34] review workers: gates 18 >= 6: holding
[15:05:07] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:05:07] review workers 1/3: load 43.90576171875 >= 36: holding
[15:05:40] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:06:13] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:06:13] review workers: gates 14 >= 6: holding
[15:06:46] tick — Ready=0 Building=1 QA=0 Review=1 Blocked=6 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
[15:07:37] ↩ unblocked #226: Blocked → Ready (cleared by #227, #228, #229)
[15:07:45] ↩ unblocked #304: Blocked → Ready (cleared by #228, #308)
[15:07:48] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=0(#228) r_workers=1/3 waiting_on_you=0
kept card 307: live build lane (pid 74943) holds it
[15:07:49] build workers: gates 10 >= 6: holding
[15:08:25] worker of #228 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=657s
[15:08:31] reaped stale lock + swept assignee on #228 (pid=30186)
[15:08:41] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:08:41] build workers: gates 18 >= 6: holding
[15:09:25] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:09:25] build workers: gates 29 >= 6: holding
[15:10:10] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:10:11] build workers: gates 27 >= 6: holding
[15:10:58] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:10:58] build workers: gates 17 >= 6: holding
[15:11:44] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:11:44] build workers: gates 12 >= 6: holding
[15:12:30] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:12:31] build workers: gates 14 >= 6: holding
[15:13:14] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:13:14] build workers: gates 11 >= 6: holding
[15:14:04] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:14:05] build workers: gates 10 >= 6: holding
[15:14:51] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:14:51] build workers: gates 10 >= 6: holding
[15:15:41] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:15:42] build workers: gates 12 >= 6: holding
[15:16:34] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:16:34] build workers: gates 20 >= 6: holding
[15:17:23] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:17:24] build workers: gates 10 >= 6: holding
[15:18:15] tick — Ready=2 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:18:17] build workers 1/10: load 70.79833984375 >= 36: holding
kept card 307: live build lane (pid 74943) holds it
[15:19:05] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:19:05] build workers: gates 19 >= 6: holding
[15:19:52] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#228) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:19:53] build workers: gates 12 >= 6: holding
[15:20:42] 💀 zombie qa worker on #228 (pid=77414) — card moved to 'Done'; killing
[15:20:49] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:20:49] build workers: gates 8 >= 6: holding
[15:21:33] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:21:34] build workers: gates 6 >= 6: holding
[15:22:15] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:22:15] build workers 1/10: load 51.3994140625 >= 36: holding
[15:22:54] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:22:54] build workers 1/10: load 43.0048828125 >= 36: holding
[15:23:28] tick — Ready=13 Building=1 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:23:28] build workers 1/10, load 26.435546875 < 36: starting #2
[15:23:38] preflight #226: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[15:23:49] dispatch lane=build issue=#226 pid=83533 claim=ToanMobile
[15:24:23] tick — Ready=12 Building=2 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:24:23] build workers 2/10, load 26.00341796875 < 36: starting #3
[15:24:40] dispatch lane=build issue=#316 pid=42527 claim=ToanMobile
[15:25:13] tick — Ready=11 Building=3 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:25:13] build workers 3/10, load 15.91357421875 < 36: starting #4
[15:25:28] dispatch lane=build issue=#317 pid=84880 claim=ToanMobile
[15:26:02] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:26:02] build workers: gates 10 >= 6: holding
[15:26:44] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:26:44] build workers: gates 33 >= 6: holding
[15:27:26] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:27:26] build workers: gates 18 >= 6: holding
[15:28:04] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:28:04] build workers: gates 12 >= 6: holding
[15:28:42] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:28:42] build workers: gates 11 >= 6: holding
kept card 317: live build lane (pid 84880) holds it
kept card 226: live build lane (pid 83533) holds it
[15:29:30] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:29:30] build workers: gates 28 >= 6: holding
[15:30:20] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:30:20] build workers: gates 21 >= 6: holding
[15:31:15] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:31:15] build workers: gates 29 >= 6: holding
[15:32:09] tick — Ready=10 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:32:09] build workers: gates 24 >= 6: holding
[15:33:03] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:33:03] build workers: gates 24 >= 6: holding
[15:33:57] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:33:58] build workers: gates 14 >= 6: holding
[15:34:44] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:34:44] build workers: gates 13 >= 6: holding
[15:35:30] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:35:30] build workers: gates 17 >= 6: holding
[15:36:16] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:36:17] build workers: gates 18 >= 6: holding
[15:37:01] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:37:01] build workers: gates 16 >= 6: holding
[15:37:41] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:37:41] build workers: gates 15 >= 6: holding
[15:38:19] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:38:19] build workers: gates 10 >= 6: holding
kept card 316: live build lane (pid 42527) holds it
[15:38:54] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:38:54] build workers 4/10: load 58.1416015625 >= 36: holding
kept card 317: live build lane (pid 84880) holds it
kept card 226: live build lane (pid 83533) holds it
[15:39:30] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:39:30] build workers: gates 15 >= 6: holding
[15:40:05] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:40:05] build workers 4/10: load 37.97705078125 >= 36: holding
[15:40:40] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:40:41] build workers 4/10, load 26.44189453125 < 36: starting #5
[15:40:56] dispatch lane=build issue=#318 pid=76248 claim=ToanMobile
[15:41:29] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317 76248:318) b_workers=5/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:41:29] build workers 5/10, load 17.6708984375 < 36: starting #6
[15:41:45] dispatch lane=build issue=#319 pid=11482 claim=ToanMobile
[15:42:22] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 42527:316 84880:317 76248:318 11482:319) b_workers=6/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:42:22] build workers: gates 14 >= 6: holding
[15:42:55] worker of #316 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1074s
[15:42:58] reaped stale lock + swept assignee on #316 (pid=42527)
[15:43:03] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:43:11] dispatch lane=qa issue=#316 pid=13737 claim=ToanMobile
[15:43:11] build workers: gates 7 >= 6: holding
[15:43:51] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:43:51] qa workers: gates 25 >= 6: holding
[15:43:52] qa workers: gates 23 >= 6: holding
[15:43:52] build workers: gates 23 >= 6: holding
[15:44:34] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:44:34] qa workers: gates 17 >= 6: holding
[15:44:34] qa workers: gates 19 >= 6: holding
[15:44:34] build workers: gates 20 >= 6: holding
[15:45:17] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:45:18] qa workers: gates 15 >= 6: holding
[15:45:18] qa workers: gates 16 >= 6: holding
[15:45:18] build workers: gates 16 >= 6: holding
[15:46:00] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:46:00] qa workers: gates 21 >= 6: holding
[15:46:01] qa workers: gates 20 >= 6: holding
[15:46:01] build workers: gates 20 >= 6: holding
[15:46:42] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:46:42] qa workers: gates 19 >= 6: holding
[15:46:43] qa workers: gates 19 >= 6: holding
[15:46:43] build workers: gates 19 >= 6: holding
[15:47:26] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:47:26] qa workers: gates 34 >= 6: holding
[15:47:26] qa workers: gates 33 >= 6: holding
[15:47:26] build workers: gates 32 >= 6: holding
[15:48:08] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:48:08] qa workers: gates 23 >= 6: holding
[15:48:09] qa workers: gates 23 >= 6: holding
[15:48:09] build workers: gates 24 >= 6: holding
[15:48:52] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:48:52] qa workers: gates 16 >= 6: holding
[15:48:52] qa workers: gates 19 >= 6: holding
[15:48:53] build workers: gates 18 >= 6: holding
[15:49:41] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:49:42] qa workers: gates 24 >= 6: holding
kept card 317: live build lane (pid 84880) holds it
[15:49:43] qa workers: gates 25 >= 6: holding
[15:49:44] build workers: gates 24 >= 6: holding
kept card 318: live build lane (pid 76248) holds it
[15:50:35] tick — Ready=6 Building=5 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:50:36] qa workers: gates 29 >= 6: holding
[15:50:37] qa workers: gates 30 >= 6: holding
[15:50:38] build workers: gates 26 >= 6: holding
[15:51:32] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=0(#316) q_workers=1/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:51:33] qa workers: gates 27 >= 6: holding
[15:51:34] build workers: gates 27 >= 6: holding
[15:52:07] worker of #316 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=514s
[15:52:13] reaped stale lock + swept assignee on #316 (pid=13737)
[15:52:29] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#228) r_workers=0/3 waiting_on_you=0
[15:52:55] dispatch lane=review issue=#316 pid=32985 claim=ToanMobile
[15:52:56] build workers: gates 21 >= 6: holding
[15:53:57] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:53:58] review workers: gates 30 >= 6: holding
[15:53:58] build workers: gates 28 >= 6: holding
[15:54:59] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:55:00] review workers: gates 27 >= 6: holding
[15:55:00] build workers: gates 26 >= 6: holding
[15:55:59] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:56:00] review workers: gates 22 >= 6: holding
[15:56:00] build workers: gates 23 >= 6: holding
[15:56:57] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:56:58] review workers: gates 31 >= 6: holding
[15:56:59] build workers: gates 31 >= 6: holding
[15:57:52] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:57:53] review workers: gates 22 >= 6: holding
[15:57:54] build workers: gates 22 >= 6: holding
[15:58:49] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:58:50] review workers: gates 22 >= 6: holding
[15:58:50] build workers: gates 23 >= 6: holding
kept card 307: live build lane (pid 74943) holds it
[15:59:49] tick — Ready=6 Building=5 QA=0 Review=1 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=0(#316) r_workers=1/3 waiting_on_you=0
[15:59:50] review workers: gates 28 >= 6: holding
[15:59:50] build workers: gates 27 >= 6: holding
kept card 318: live build lane (pid 76248) holds it
kept card 317: live build lane (pid 84880) holds it
kept card 319: live build lane (pid 11482) holds it
kept card 226: live build lane (pid 83533) holds it
[16:01:09] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:01:10] build workers: gates 26 >= 6: holding
[16:01:12] worker of #316 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=485s
[16:02:46] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:02:47] build workers: gates 37 >= 6: holding
[16:04:02] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:04:03] build workers: gates 30 >= 6: holding
[16:05:20] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:05:21] build workers: gates 30 >= 6: holding
[16:06:53] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:06:54] build workers: gates 21 >= 6: holding
[16:08:03] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:08:49] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:09:33] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:10:21] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
kept card 319: live build lane (pid 11482) holds it
kept card 226: live build lane (pid 83533) holds it
kept card 318: live build lane (pid 76248) holds it
kept card 307: live build lane (pid 74943) holds it
[16:10:58] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:11:36] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:12:11] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:12:46] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:13:25] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:14:03] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:14:39] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:15:18] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:15:59] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:16:46] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:17:35] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:18:23] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:19:11] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:20:06] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:20:54] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
kept card 317: live build lane (pid 84880) holds it
kept card 318: live build lane (pid 76248) holds it
kept card 226: live build lane (pid 83533) holds it
kept card 307: live build lane (pid 74943) holds it
[16:21:45] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:22:35] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:23:26] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:24:20] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:25:05] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:25:53] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:26:40] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:27:27] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:28:17] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:28:59] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:29:43] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:30:22] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:30:59] tick — Ready=0 Building=5 QA=0 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
kept card 307: live build lane (pid 74943) holds it
kept card 226: live build lane (pid 83533) holds it
kept card 318: live build lane (pid 76248) holds it
kept card 319: live build lane (pid 11482) holds it
[16:31:37] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:32:14] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:33:00] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:33:48] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:34:35] tick — Ready=0 Building=4 QA=1 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:35:18] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:36:04] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:36:50] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:37:39] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 84880:317 76248:318 11482:319) b_workers=5/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:38:24] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 76248:318 11482:319) b_workers=4/10 q_idle=1(#316) q_workers=0/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:38:26] worker of #317 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4366s
[16:38:41] dispatch lane=qa issue=#317 pid=58259 claim=ToanMobile
[16:39:24] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 76248:318 11482:319) b_workers=4/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:39:25] qa workers: gates 11 >= 6: holding
[16:39:25] qa workers: gates 11 >= 6: holding
[16:40:05] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +83533:226 76248:318 11482:319) b_workers=4/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:40:06] qa workers: gates 7 >= 6: holding
[16:40:06] qa workers: gates 7 >= 6: holding
[16:40:36] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4587s
[16:40:39] reaped stale lock + swept assignee on #226 (pid=83533)
[16:40:44] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:40:44] qa workers: gates 8 >= 6: holding
[16:40:44] qa workers: gates 9 >= 6: holding
[16:41:18] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:41:18] qa workers: gates 6 >= 6: holding
[16:41:18] qa workers: gates 6 >= 6: holding
kept card 319: live build lane (pid 11482) holds it
[16:41:51] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:41:57] dispatch lane=qa issue=#226 pid=43778 claim=ToanMobile
[16:42:30] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:42:30] qa workers: gates 6 >= 6: holding
[16:42:30] qa workers: gates 6 >= 6: holding
[16:43:04] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:43:04] qa workers: gates 8 >= 6: holding
[16:43:04] qa workers: gates 8 >= 6: holding
[16:43:37] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:43:37] qa workers: gates 8 >= 6: holding
[16:43:37] qa workers: gates 8 >= 6: holding
[16:44:12] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:44:12] qa workers: gates 15 >= 6: holding
[16:44:13] qa workers: gates 15 >= 6: holding
[16:44:49] tick — Ready=0 Building=3 QA=2 Review=0 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:44:49] qa workers: gates 13 >= 6: holding
[16:44:49] qa workers: gates 14 >= 6: holding
[16:45:29] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317 +43778:226) q_workers=2/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:45:30] qa workers: gates 9 >= 6: holding
[16:45:30] qa workers: gates 10 >= 6: holding
[16:46:01] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=219s
[16:46:07] reaped stale lock + swept assignee on #226 (pid=43778)
[16:46:17] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#316) r_workers=0/3 waiting_on_you=0
[16:46:33] dispatch lane=review issue=#226 pid=19991 claim=ToanMobile
[16:46:34] qa workers: gates 10 >= 6: holding
[16:46:34] qa workers: gates 11 >= 6: holding
[16:47:18] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:47:19] review workers: gates 15 >= 6: holding
[16:47:19] qa workers: gates 15 >= 6: holding
[16:47:20] qa workers: gates 16 >= 6: holding
[16:48:05] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:48:06] review workers: gates 14 >= 6: holding
[16:48:06] qa workers: gates 16 >= 6: holding
[16:48:07] qa workers: gates 16 >= 6: holding
[16:48:53] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:48:54] review workers: gates 13 >= 6: holding
[16:48:54] qa workers: gates 14 >= 6: holding
[16:48:55] qa workers: gates 14 >= 6: holding
[16:49:42] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:49:43] review workers: gates 18 >= 6: holding
[16:49:43] qa workers: gates 15 >= 6: holding
[16:49:44] qa workers: gates 15 >= 6: holding
[16:50:29] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:50:29] review workers: gates 17 >= 6: holding
[16:50:30] qa workers: gates 17 >= 6: holding
[16:50:30] qa workers: gates 17 >= 6: holding
[16:51:15] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:51:16] review workers: gates 21 >= 6: holding
[16:51:17] qa workers: gates 19 >= 6: holding
[16:51:17] qa workers: gates 18 >= 6: holding
[16:52:00] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:52:01] review workers: gates 14 >= 6: holding
kept card 318: live build lane (pid 76248) holds it
kept card 226: live review lane (pid 19991) holds it
[16:52:02] qa workers: gates 15 >= 6: holding
[16:52:02] qa workers: gates 15 >= 6: holding
kept card 307: live build lane (pid 74943) holds it
kept card 319: live build lane (pid 11482) holds it
[16:52:53] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:52:54] review workers: gates 14 >= 6: holding
[16:52:54] qa workers: gates 13 >= 6: holding
[16:52:55] qa workers: gates 12 >= 6: holding
[16:53:46] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:53:46] review workers: gates 13 >= 6: holding
[16:53:47] qa workers: gates 13 >= 6: holding
[16:53:47] qa workers: gates 12 >= 6: holding
[16:54:25] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:54:25] review workers: gates 13 >= 6: holding
[16:54:25] qa workers: gates 13 >= 6: holding
[16:54:25] qa workers: gates 13 >= 6: holding
[16:55:02] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:55:03] review workers: gates 22 >= 6: holding
[16:55:03] qa workers: gates 22 >= 6: holding
[16:55:03] qa workers: gates 22 >= 6: holding
[16:55:39] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:55:39] review workers: gates 12 >= 6: holding
[16:55:39] qa workers: gates 13 >= 6: holding
[16:55:39] qa workers: gates 13 >= 6: holding
[16:56:17] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:56:18] review workers: gates 9 >= 6: holding
[16:56:18] qa workers: gates 10 >= 6: holding
[16:56:18] qa workers: gates 10 >= 6: holding
[16:56:55] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:56:55] review workers: gates 9 >= 6: holding
[16:56:56] qa workers: gates 9 >= 6: holding
[16:56:56] qa workers: gates 9 >= 6: holding
[16:57:33] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:57:33] review workers: gates 8 >= 6: holding
[16:57:34] qa workers: gates 8 >= 6: holding
[16:57:34] qa workers: gates 8 >= 6: holding
[16:58:13] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:58:13] review workers: gates 9 >= 6: holding
[16:58:14] qa workers: gates 9 >= 6: holding
[16:58:14] qa workers: gates 8 >= 6: holding
[16:58:53] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:58:53] review workers: gates 8 >= 6: holding
[16:58:54] qa workers: gates 7 >= 6: holding
[16:58:54] qa workers: gates 7 >= 6: holding
[16:59:35] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[16:59:35] review workers: gates 6 >= 6: holding
[16:59:35] qa workers: gates 7 >= 6: holding
[16:59:36] qa workers: gates 7 >= 6: holding
[17:00:12] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:00:12] review workers: gates 7 >= 6: holding
[17:00:12] qa workers: gates 7 >= 6: holding
[17:00:12] qa workers: gates 6 >= 6: holding
[17:00:50] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:00:50] review workers 1/3: load 104.77978515625 >= 36: holding
[17:00:50] qa workers 1/3: load 104.77978515625 >= 36: holding
[17:00:51] qa workers 1/3: load 104.77978515625 >= 36: holding
[17:01:29] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:01:29] review workers: gates 8 >= 6: holding
[17:01:29] qa workers: gates 9 >= 6: holding
[17:01:29] qa workers: gates 9 >= 6: holding
[17:02:03] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:02:03] review workers 1/3: load 66.875 >= 36: holding
[17:02:03] qa workers 1/3: load 66.875 >= 36: holding
[17:02:03] qa workers 1/3: load 66.875 >= 36: holding
kept card 319: live build lane (pid 11482) holds it
kept card 307: live build lane (pid 74943) holds it
kept card 226: live review lane (pid 19991) holds it
[17:02:43] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:02:44] review workers: gates 18 >= 6: holding
[17:02:44] qa workers: gates 18 >= 6: holding
[17:02:44] qa workers: gates 15 >= 6: holding
[17:03:20] tick — Ready=0 Building=3 QA=1 Review=1 Blocked=4 lanes: b_idle=0(#307 +76248:318 11482:319) b_workers=3/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:03:20] review workers: gates 8 >= 6: holding
[17:03:20] qa workers: gates 8 >= 6: holding
[17:03:20] qa workers: gates 8 >= 6: holding
[17:03:51] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4909s
[17:03:54] reaped stale lock + swept assignee on #319 (pid=11482)
[17:03:58] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:03:58] review workers 1/3: load 40.068359375 >= 36: holding
[17:03:58] qa workers 1/3: load 40.068359375 >= 36: holding
[17:03:58] qa workers 1/3: load 40.068359375 >= 36: holding
[17:04:34] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:04:34] review workers: gates 13 >= 6: holding
[17:04:34] qa workers: gates 13 >= 6: holding
[17:04:35] qa workers: gates 12 >= 6: holding
[17:05:10] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:05:10] review workers: gates 9 >= 6: holding
[17:05:10] qa workers: gates 8 >= 6: holding
[17:05:10] qa workers: gates 8 >= 6: holding
[17:05:43] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:05:43] review workers: gates 8 >= 6: holding
[17:05:43] qa workers: gates 8 >= 6: holding
[17:05:43] qa workers: gates 8 >= 6: holding
[17:06:16] tick — Ready=0 Building=2 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:06:16] review workers: gates 6 >= 6: holding
[17:06:17] qa workers: gates 6 >= 6: holding
[17:06:17] qa workers: gates 6 >= 6: holding
[17:06:50] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=0(#226) r_workers=1/3 waiting_on_you=0
[17:06:50] qa workers: gates 6 >= 6: holding
[17:06:50] qa workers: gates 6 >= 6: holding
[17:06:50] build workers: gates 6 >= 6: holding
[17:07:20] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1218s
[17:07:23] reaped stale lock + swept assignee on #226 (pid=19991)
[17:07:26] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:07:26] qa workers: gates 14 >= 6: holding
[17:07:26] qa workers: gates 15 >= 6: holding
[17:07:27] build workers: gates 14 >= 6: holding
[17:08:00] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:08:00] qa workers: gates 14 >= 6: holding
[17:08:00] qa workers: gates 14 >= 6: holding
[17:08:00] build workers: gates 13 >= 6: holding
[17:08:34] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:08:34] qa workers: gates 14 >= 6: holding
[17:08:34] qa workers: gates 13 >= 6: holding
[17:08:34] build workers: gates 12 >= 6: holding
[17:09:08] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:09:08] qa workers: gates 13 >= 6: holding
[17:09:08] qa workers: gates 14 >= 6: holding
[17:09:08] build workers: gates 14 >= 6: holding
[17:09:42] tick — Ready=1 Building=2 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:09:42] qa workers: gates 12 >= 6: holding
[17:09:43] qa workers: gates 12 >= 6: holding
[17:09:43] build workers: gates 12 >= 6: holding
[17:10:16] tick — Ready=1 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:10:17] qa workers: gates 8 >= 6: holding
[17:10:17] build workers: gates 8 >= 6: holding
[17:10:58] tick — Ready=1 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=0(#317) q_workers=1/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:10:59] qa workers: gates 26 >= 6: holding
[17:10:59] build workers: gates 25 >= 6: holding
[17:11:32] 💀 zombie qa worker on #317 (pid=58259) — card moved to 'Review'; killing
[17:11:40] tick — Ready=8 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#226) r_workers=0/3 waiting_on_you=0
[17:11:48] dispatch lane=review issue=#317 pid=75217 claim=ToanMobile
[17:11:48] build workers 2/10: load 79.8603515625 >= 36: holding
kept card 318: live build lane (pid 76248) holds it
[17:12:23] tick — Ready=11 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:12:23] review workers 1/3: load 49.267578125 >= 36: holding
[17:12:23] build workers 2/10: load 49.267578125 >= 36: holding
kept card 317: live review lane (pid 75217) holds it
kept card 307: live build lane (pid 74943) holds it
[17:12:59] tick — Ready=11 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:12:59] build workers 2/10, load 35.09423828125 < 36: starting #3
[17:13:16] dispatch lane=build issue=#226 pid=5242 claim=ToanMobile
[17:13:55] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318 5242:226) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:13:56] review workers: gates 8 >= 6: holding
[17:13:56] build workers: gates 9 >= 6: holding
[17:14:39] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318 5242:226) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:14:39] review workers: gates 6 >= 6: holding
[17:14:39] build workers: gates 6 >= 6: holding
[17:15:22] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318 5242:226) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:15:22] review workers: gates 9 >= 6: holding
[17:15:22] build workers: gates 9 >= 6: holding
[17:16:10] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318 5242:226) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:16:11] build workers 3/10, load 30.482421875 < 36: starting #4
[17:16:50] dispatch lane=build issue=#316 pid=55974 claim=ToanMobile
[17:17:31] tick — Ready=9 Building=4 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#307 +76248:318 5242:226 55974:316) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:17:31] review workers 1/3: load 38.86962890625 >= 36: holding
[17:17:32] build workers 4/10: load 38.86962890625 >= 36: holding
[17:21:54] super-board run started (watchdog restart) — config=agent-workbench base=main tick=30s max_workers=10 no_progress_cycles=240 max_dispatches=0
[17:21:55] worker of #226 (lane build) exit record: worker_exit: exit=143 signal=TERM elapsed=514s
[17:21:58] reaped stale lock + swept assignee on #226 (pid=5242)
[17:21:58] worker of #307 (lane build) exit record: worker_exit: exit=143 signal=TERM elapsed=9300s
[17:22:01] reaped stale lock + swept assignee on #307 (pid=74943)
[17:22:02] worker of #316 (lane build) exit record: worker_exit: exit=143 signal=TERM elapsed=298s
[17:22:05] reaped stale lock + swept assignee on #316 (pid=55974)
[17:22:06] worker of #317 (lane review) exit record: worker_exit: exit=143 signal=TERM elapsed=600s
[17:22:09] reaped stale lock + swept assignee on #317 (pid=75217)
[17:22:10] worker of #318 (lane build) exit record: worker_exit: exit=143 signal=TERM elapsed=6052s
[17:22:14] reaped stale lock + swept assignee on #318 (pid=76248)
[17:22:23] ℹ stranded #316: keeping existing worktree .claude/worktrees/issue-316-build (branch issue-316-runner-lifecycle) for Builder to resume
[17:22:35] ↩ stranded #316: Building → Ready (branch issue-316-runner-lifecycle)
[17:22:40] ℹ stranded #226: keeping existing worktree .claude/worktrees/issue-226-build (branch issue-226-merge-gate-skip-verified-tree) for Builder to resume
[17:22:49] ↩ stranded #226: Building → Ready (branch issue-226-merge-gate-skip-verified-tree)
[17:22:53] ℹ stranded #307: keeping existing worktree .claude/worktrees/issue-307-build (branch issue-307-gate-tree-mode) for Builder to resume
[17:23:02] ↩ stranded #307: Building → Ready (branch none)
[17:23:17] ↩ stranded #318: Building → Ready (branch none)
[17:23:18] initial Ready count: 13
[17:23:19] ⚠ self-reload: git fetch origin main failed; retrying next check
[17:23:25] tick — Ready=13 Building=0 QA=0 Review=1 Blocked=5 lanes: b_idle=1(#_) b_workers=0/10 q_idle=1(#_) q_workers=0/3 r_idle=1(#_) r_workers=0/3 waiting_on_you=0
[17:23:25] ⚠ block-rate alert: 5/13 (38%)
[17:23:39] dispatch lane=review issue=#317 pid=65053 claim=ToanMobile
[17:24:00] dispatch lane=build issue=#226 pid=98153 claim=ToanMobile
[17:24:34] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:24:34] review workers 1/3: load 98.8154296875 >= 36: holding
[17:24:34] build workers 1/10: load 98.8154296875 >= 36: holding
[17:25:10] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:25:11] review workers 1/3: load 93.94775390625 >= 36: holding
[17:25:11] build workers 1/10: load 93.94775390625 >= 36: holding
[17:25:47] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:25:47] review workers 1/3: load 91.52490234375 >= 36: holding
[17:25:47] build workers: gates 6 >= 6: holding
[17:26:23] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:26:23] review workers: gates 9 >= 6: holding
[17:26:23] build workers: gates 9 >= 6: holding
[17:26:59] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:26:59] review workers: gates 6 >= 6: holding
[17:26:59] build workers: gates 6 >= 6: holding
[17:27:36] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:27:36] review workers: gates 7 >= 6: holding
[17:27:36] build workers: gates 6 >= 6: holding
[17:28:12] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:28:12] review workers 1/3: load 139.76708984375 >= 36: holding
[17:28:12] build workers 1/10: load 139.76708984375 >= 36: holding
[17:28:48] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:28:48] review workers: gates 6 >= 6: holding
[17:28:48] build workers: gates 7 >= 6: holding
[17:29:24] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:29:24] review workers: gates 9 >= 6: holding
[17:29:24] build workers: gates 9 >= 6: holding
[17:30:01] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:30:02] review workers 1/3: load 97.54150390625 >= 36: holding
[17:30:02] build workers 1/10: load 97.54150390625 >= 36: holding
[17:30:39] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:30:39] review workers: gates 13 >= 6: holding
[17:30:39] build workers: gates 11 >= 6: holding
[17:31:14] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:31:14] review workers 1/3: load 40.53466796875 >= 36: holding
[17:31:14] build workers 1/10: load 40.53466796875 >= 36: holding
[17:31:49] tick — Ready=12 Building=1 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226) b_workers=1/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:31:49] build workers 1/10, load 24.5791015625 < 36: starting #2
[17:32:08] dispatch lane=build issue=#307 pid=7982 claim=ToanMobile
[17:32:41] tick — Ready=11 Building=2 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307) b_workers=2/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:32:41] build workers 2/10, load 12.14990234375 < 36: starting #3
[17:32:58] dispatch lane=build issue=#316 pid=30789 claim=ToanMobile
kept card 226: live build lane (pid 98153) holds it
[17:33:32] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:33:32] review workers: gates 6 >= 6: holding
[17:33:32] build workers: gates 6 >= 6: holding
kept card 317: live review lane (pid 65053) holds it
kept card 307: live build lane (pid 7982) holds it
kept card 316: live build lane (pid 30789) holds it
[17:34:07] tick — Ready=10 Building=3 QA=0 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:34:07] build workers 3/10, load 20.3701171875 < 36: starting #4
[17:34:25] dispatch lane=build issue=#318 pid=90838 claim=ToanMobile
[17:35:00] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:35:00] review workers: gates 16 >= 6: holding
[17:35:00] build workers: gates 16 >= 6: holding
[17:35:40] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=4/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:35:40] review workers: gates 16 >= 6: holding
[17:35:40] build workers: gates 17 >= 6: holding
[17:36:14] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=732s
[17:36:19] reaped stale lock + swept assignee on #226 (pid=98153)
[17:36:26] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=1(#_) q_workers=0/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:36:26] review workers: gates 16 >= 6: holding
[17:36:35] dispatch lane=qa issue=#226 pid=8763 claim=ToanMobile
[17:36:35] build workers: gates 20 >= 6: holding
[17:37:11] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:37:11] review workers: gates 17 >= 6: holding
[17:37:11] qa workers: gates 17 >= 6: holding
[17:37:11] qa workers: gates 13 >= 6: holding
[17:37:11] build workers: gates 13 >= 6: holding
[17:37:48] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:37:48] review workers: gates 20 >= 6: holding
[17:37:48] qa workers: gates 21 >= 6: holding
[17:37:48] qa workers: gates 20 >= 6: holding
[17:37:49] build workers: gates 20 >= 6: holding
[17:38:25] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:38:25] review workers: gates 17 >= 6: holding
[17:38:25] qa workers: gates 17 >= 6: holding
[17:38:25] qa workers: gates 18 >= 6: holding
[17:38:25] build workers: gates 18 >= 6: holding
[17:39:00] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:39:00] review workers: gates 17 >= 6: holding
[17:39:00] qa workers: gates 17 >= 6: holding
[17:39:00] qa workers: gates 16 >= 6: holding
[17:39:00] build workers: gates 15 >= 6: holding
[17:39:35] tick — Ready=9 Building=3 QA=1 Review=1 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=0(#317) r_workers=1/3 waiting_on_you=0
[17:39:36] review workers: gates 17 >= 6: holding
[17:39:36] qa workers: gates 17 >= 6: holding
[17:39:36] qa workers: gates 18 >= 6: holding
[17:39:36] build workers: gates 17 >= 6: holding
[17:40:06] worker of #317 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=987s
[17:40:09] reaped stale lock + swept assignee on #317 (pid=65053)
[17:40:15] tick — Ready=9 Building=3 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[17:40:15] qa workers: gates 6 >= 6: holding
[17:40:15] qa workers: gates 6 >= 6: holding
[17:40:15] build workers: gates 6 >= 6: holding
[17:40:49] tick — Ready=9 Building=3 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[17:40:49] qa workers: gates 14 >= 6: holding
[17:40:49] qa workers: gates 13 >= 6: holding
[17:40:49] build workers: gates 13 >= 6: holding
[17:41:23] tick — Ready=9 Building=3 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[17:41:23] qa workers 1/3: load 43.7685546875 >= 36: holding
[17:41:24] qa workers 1/3: load 43.7685546875 >= 36: holding
[17:41:24] build workers 3/10: load 43.7685546875 >= 36: holding
[17:41:57] tick — Ready=10 Building=3 QA=0 Review=0 Blocked=5 lanes: b_idle=0(#226 +7982:307 30789:316 90838:318) b_workers=3/10 q_idle=0(#226) q_workers=1/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[17:41:57] build workers 3/10, load 30.31298828125 < 36: starting #4
[17:42:14] dispatch lane=build issue=#320 pid=71239 claim=ToanMobile
[17:42:44] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=323s
[17:42:47] reaped stale lock + swept assignee on #226 (pid=8763)
[17:42:52] tick — Ready=9 Building=4 QA=0 Review=0 Blocked=5 lanes: b_idle=0(#320 +7982:307 30789:316 90838:318) b_workers=4/10 q_idle=1(#226) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[17:42:52] build workers: gates 14 >= 6: holding
[17:43:25] worker of #307 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=660s
[17:43:28] reaped stale lock + swept assignee on #307 (pid=7982)
[17:43:33] tick — Ready=9 Building=3 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#320 +30789:316 90838:318) b_workers=3/10 q_idle=1(#226) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
kept card 318: live build lane (pid 90838) holds it
kept card 320: live build lane (pid 71239) holds it
[17:43:39] dispatch lane=qa issue=#307 pid=16679 claim=ToanMobile
[17:43:39] build workers: gates 7 >= 6: holding
kept card 307: live qa lane (pid 16679) holds it
[18:10:22] tick — Ready=9 Building=3 QA=1 Review=0 Blocked=5 lanes: b_idle=0(#320 +30789:316 90838:318) b_workers=3/10 q_idle=0(#307) q_workers=1/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:10:22] build workers 3/10, load 22.6806640625 < 36: starting #4
kept card 320: live build lane (pid 71239) holds it
kept card 316: live build lane (pid 30789) holds it
kept card 307: live qa lane (pid 16679) holds it
[18:10:39] dispatch lane=build issue=#226 pid=4655 claim=ToanMobile
[18:11:09] worker of #307 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1640s
[18:11:12] reaped stale lock + swept assignee on #307 (pid=16679)
[18:11:15] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226) b_workers=4/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:11:15] build workers 4/10, load 13.59619140625 < 36: starting #5
[18:11:32] dispatch lane=build issue=#321 pid=77476 claim=ToanMobile
[18:12:06] tick — Ready=7 Building=5 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321) b_workers=5/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:12:06] build workers 5/10, load 11.36669921875 < 36: starting #6
[18:12:22] dispatch lane=build issue=#323 pid=32840 claim=ToanMobile
[18:12:56] tick — Ready=6 Building=6 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323) b_workers=6/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:12:56] build workers 6/10, load 6.91357421875 < 36: starting #7
[18:13:06] preflight #325: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[18:13:12] dispatch lane=build issue=#325 pid=66688 claim=ToanMobile
[18:13:46] tick — Ready=5 Building=7 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325) b_workers=7/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:13:46] build workers 7/10, load 8.37890625 < 36: starting #8
[18:14:04] dispatch lane=build issue=#327 pid=50961 claim=ToanMobile
[18:15:05] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:15:06] build workers: gates 13 >= 6: holding
[18:16:07] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:16:07] build workers: gates 6 >= 6: holding
[18:16:56] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:16:56] build workers 8/10: load 79.21923828125 >= 36: holding
[18:17:44] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:17:44] build workers 8/10: load 53.5908203125 >= 36: holding
[18:19:03] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:19:04] build workers: gates 18 >= 6: holding
kept card 327: live build lane (pid 50961) holds it
[18:20:42] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:20:44] build workers: gates 10 >= 6: holding
kept card 321: live build lane (pid 77476) holds it
kept card 318: live build lane (pid 90838) holds it
[18:22:21] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:22:23] build workers: gates 8 >= 6: holding
[18:23:46] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:23:48] build workers: gates 9 >= 6: holding
[18:25:06] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:25:07] build workers: gates 9 >= 6: holding
[18:27:07] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:27:07] build workers: gates 9 >= 6: holding
[18:27:47] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:27:47] build workers: gates 9 >= 6: holding
[18:28:26] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:28:26] build workers: gates 9 >= 6: holding
[18:29:15] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:29:17] build workers: gates 20 >= 6: holding
[18:30:02] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:30:02] build workers: gates 14 >= 6: holding
[18:30:47] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:30:47] build workers: gates 12 >= 6: holding
kept card 321: live build lane (pid 77476) holds it
kept card 325: live build lane (pid 66688) holds it
kept card 316: live build lane (pid 30789) holds it
[18:31:33] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:31:33] build workers: gates 12 >= 6: holding
[18:32:23] tick — Ready=4 Building=8 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#320 +30789:316 90838:318 4655:226 77476:321 32840:323 66688:325 50961:327) b_workers=8/10 q_idle=1(#307) q_workers=0/3 r_idle=1(#317) r_workers=0/3 waiting_on_you=0
[18:32:24] build workers: gates 13 >= 6: holding
[18:32:52] STOP 📋 8 in-flight worker(s) to wrap up
[18:32:52] STOP 
[18:32:52] STOP ─── #226 (lane=build, pid=4655) ───
[18:32:55] STOP   💬 issue comment posted on #226
[18:32:57] STOP   💬 PR comment posted on #340
[18:32:59] 🛑 stop marker .claude/super-board/runner/agent-workbench.stopped — board stopped by the user; runner exits (super-board run agent-workbench clears it)
[18:32:59] super-board run finished. manifest: docs/super-board/runs/2026-10-23-agent-workbench.md
[18:33:04] STOP   🔓 released assignee + lane labels on #226
[18:33:05] STOP   ☠ worker(build/#226) pid=4655 SIGKILLed (didn't respond to SIGTERM)
[18:33:05] STOP 
[18:33:05] STOP ─── #316 (lane=build, pid=30789) ───
[18:33:07] STOP   💬 issue comment posted on #316
[18:33:09] STOP   💬 PR comment posted on #331
[18:33:15] STOP   🔓 released assignee + lane labels on #316
[18:33:16] STOP   ☠ worker(build/#316) pid=30789 SIGKILLed (didn't respond to SIGTERM)
[18:33:16] STOP 
[18:33:16] STOP ─── #318 (lane=build, pid=90838) ───
[18:33:19] STOP   💬 issue comment posted on #318
[18:33:25] STOP   🔓 released assignee + lane labels on #318
[18:33:26] STOP   ☠ worker(build/#318) pid=90838 SIGKILLed (didn't respond to SIGTERM)
[18:33:26] STOP 
[18:33:26] STOP ─── #320 (lane=build, pid=71239) ───
[18:33:30] STOP   💬 issue comment posted on #320
[18:33:36] STOP   🔓 released assignee + lane labels on #320
[18:33:37] STOP   ☠ worker(build/#320) pid=71239 SIGKILLed (didn't respond to SIGTERM)
[18:33:37] STOP 
[18:33:37] STOP ─── #321 (lane=build, pid=77476) ───
[18:33:40] STOP   💬 issue comment posted on #321
[18:33:46] STOP   🔓 released assignee + lane labels on #321
[18:33:47] STOP   ☠ worker(build/#321) pid=77476 SIGTERMed
[18:33:47] STOP 
[18:33:47] STOP ─── #323 (lane=build, pid=32840) ───
[18:33:50] STOP   💬 issue comment posted on #323
[18:33:56] STOP   🔓 released assignee + lane labels on #323
[18:33:57] STOP   ☠ worker(build/#323) pid=32840 SIGTERMed
[18:33:57] STOP 
[18:33:57] STOP ─── #325 (lane=build, pid=66688) ───
[18:34:00] STOP   💬 issue comment posted on #325
[18:34:07] STOP   🔓 released assignee + lane labels on #325
[18:34:08] STOP   ☠ worker(build/#325) pid=66688 SIGKILLed (didn't respond to SIGTERM)
[18:34:08] STOP 
[18:34:08] STOP ─── #327 (lane=build, pid=50961) ───
[18:34:10] STOP   💬 issue comment posted on #327
[18:34:16] STOP   🔓 released assignee + lane labels on #327
[18:34:17] STOP   ☠ worker(build/#327) pid=50961 SIGTERMed
[18:34:17] STOP 
[18:34:17] STOP 🛑 stopping dispatcher loop
[18:34:17] STOP   ⊘ dispatcher pid=1527 already dead
[18:34:18] STOP 
[18:34:18] STOP 🧽 cleared .claude/super-board/inflight
[19:27:21] ▶ explicit start: cleared the stop marker (STOPPED_AT=2026-10-23T11:34:17Z BY=alex via super-board-stop.sh PID=85535 )
[19:27:21] super-board run started — config=agent-workbench base=main tick=30s max_workers=4 no_progress_cycles=240 max_dispatches=0
[19:27:32] ℹ stranded #325: keeping existing worktree .claude/worktrees/issue-325-build (branch issue-325-ocr-six-findings) for Builder to resume
[19:27:43] ↩ stranded #325: Building → Ready (branch none)
[19:27:54] ↩ stranded #323: Building → Ready (branch none)
[19:28:07] ↩ stranded #321: Building → Ready (branch none)
[19:28:19] ↩ stranded #320: Building → Ready (branch none)
[19:28:23] ℹ stranded #316: keeping existing worktree .claude/worktrees/issue-316-build (branch issue-316-runner-lifecycle) for Builder to resume
[19:28:31] ↩ stranded #316: Building → Ready (branch issue-316-runner-lifecycle)
[19:28:42] ↩ stranded #226: Building → Ready (branch issue-226-merge-gate-skip-verified-tree)
[19:28:55] ↩ stranded #318: Building → Ready (branch none)
[19:29:07] ↩ stranded #327: Building → Ready (branch none)
[19:29:09] initial Ready count: 12
[19:29:22] ⏳ #78: label '⏳ chờ thẻ khác' (waits on other cards)
[19:29:25] ⏳ #228: label '⏳ chờ thẻ khác' removed
[19:29:28] ⏳ #226: label '⏳ chờ thẻ khác' removed
[19:29:28] tick — Ready=12 Building=0 QA=0 Review=0 Blocked=6 lanes: b_idle=1(#_) b_workers=0/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:29:28] ⚠ block-rate alert: 6/12 (50%)
[19:29:47] dispatch lane=build issue=#226 pid=80078 claim=ToanMobile
[19:30:21] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:30:21] build workers: gates 6 >= 6: holding
[19:30:57] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:30:57] build workers: gates 7 >= 6: holding
[19:31:33] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:31:33] build workers: gates 8 >= 6: holding
[19:32:08] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:32:08] build workers: gates 10 >= 6: holding
[19:32:43] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:32:43] build workers: gates 8 >= 6: holding
[19:33:17] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:33:18] build workers: gates 8 >= 6: holding
[19:33:52] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:33:52] build workers: gates 8 >= 6: holding
[19:34:28] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:34:28] build workers: gates 7 >= 6: holding
[19:35:02] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:35:02] build workers: gates 8 >= 6: holding
[19:35:36] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:35:37] build workers: gates 8 >= 6: holding
[19:36:11] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:36:11] build workers: gates 7 >= 6: holding
[19:36:46] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:36:46] build workers: gates 10 >= 6: holding
[19:37:22] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:37:22] build workers: gates 10 >= 6: holding
[19:37:58] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/3 q_idle=1(#_) q_workers=0/1 r_idle=1(#_) r_workers=0/1 waiting_on_you=0
[19:37:58] build workers: gates 8 >= 6: holding
[19:38:29] super-board run started — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[19:38:31] adopted live build worker on #226 (pid=80078) from the previous run
[19:38:35] initial Ready count: 11
[19:38:42] tick — Ready=11 Building=1 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226) b_workers=1/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:38:42] ⚠ block-rate alert: 6/11 (54%)
[19:39:03] dispatch lane=build issue=#316 pid=90876 claim=ToanMobile
[19:39:38] tick — Ready=10 Building=2 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226 +90876:316) b_workers=2/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:39:59] dispatch lane=build issue=#318 pid=73004 claim=ToanMobile
[19:40:37] tick — Ready=9 Building=3 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226 +90876:316 73004:318) b_workers=3/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:41:02] dispatch lane=build issue=#320 pid=47645 claim=ToanMobile
[19:41:39] tick — Ready=8 Building=4 QA=0 Review=0 Blocked=6 lanes: b_idle=0(#226 +90876:316 73004:318 47645:320) b_workers=4/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[19:42:19] dispatch lane=build issue=#321 pid=31536 claim=ToanMobile
[19:42:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:43:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:43:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:44:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:45:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:45:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:46:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:46:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:47:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:47:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:48:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:48:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 318: live build lane (pid 73004) holds it
kept card 320: live build lane (pid 47645) holds it
kept card 316: live build lane (pid 90876) holds it
kept card 321: live build lane (pid 31536) holds it
[19:49:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:49:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:50:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:50:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:51:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:51:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:52:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:52:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:53:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:53:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:54:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:54:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:55:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:55:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:56:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:56:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:57:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:57:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:58:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[19:59:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 226: live build lane (pid 80078) holds it
kept card 316: live build lane (pid 90876) holds it
[19:59:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:00:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:00:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:01:04] worker of #316 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1309s
[20:01:07] reaped stale lock + swept assignee on #316 (pid=90876)
[20:01:13] tick — Ready=7 Building=4 QA=1 Review=0 Blocked=6 lanes: b_idle=0(#226 +73004:318 47645:320 31536:321) b_workers=4/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:01:20] dispatch lane=qa issue=#316 pid=72184 claim=ToanMobile
[20:01:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:02:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:02:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:03:24] worker of #321 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1263s
[20:03:27] reaped stale lock + swept assignee on #321 (pid=31536)
[20:03:29] tick — Ready=7 Building=3 QA=2 Review=0 Blocked=6 lanes: b_idle=0(#226 +73004:318 47645:320) b_workers=3/5 q_idle=0(#316) q_workers=1/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:03:36] dispatch lane=qa issue=#321 pid=42972 claim=ToanMobile
[20:04:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:04:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:05:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:05:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:06:10] worker of #318 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1551s
[20:06:13] reaped stale lock + swept assignee on #318 (pid=73004)
[20:06:17] tick — Ready=7 Building=2 QA=3 Review=0 Blocked=6 lanes: b_idle=0(#226 +47645:320) b_workers=2/5 q_idle=0(#316 +42972:321) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:06:23] dispatch lane=qa issue=#318 pid=8065 claim=ToanMobile
[20:06:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:07:24] worker of #321 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=217s
[20:07:27] reaped stale lock + swept assignee on #321 (pid=42972)
[20:07:29] tick — Ready=7 Building=2 QA=1 Review=2 Blocked=6 lanes: b_idle=0(#226 +47645:320) b_workers=2/5 q_idle=0(#316 +8065:318) q_workers=2/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:07:41] dispatch lane=review issue=#321 pid=98554 claim=ToanMobile
[20:07:41] qa workers: 5/5 running on the machine (5 here): holding
[20:07:41] qa workers: 5/5 running on the machine (5 here): holding
[20:08:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:08:45] 💀 zombie qa worker on #316 (pid=72184) — card moved to 'Review'; killing
[20:08:52] tick — Ready=8 Building=2 QA=1 Review=2 Blocked=6 lanes: b_idle=0(#226 +47645:320) b_workers=2/5 q_idle=0(#_ +8065:318) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:09:04] dispatch lane=review issue=#316 pid=33322 claim=ToanMobile
[20:09:04] qa workers: 5/5 running on the machine (5 here): holding
[20:09:04] qa workers: 5/5 running on the machine (5 here): holding
[20:09:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 226: live build lane (pid 80078) holds it
[20:10:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:10:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:11:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:11:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:12:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:12:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:13:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:13:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:14:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:14:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:15:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:15:57] worker of #316 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=396s
[20:16:01] reaped stale lock + swept assignee on #316 (pid=33322)
[20:16:05] tick — Ready=9 Building=2 QA=1 Review=1 Blocked=6 lanes: b_idle=0(#226 +47645:320) b_workers=2/5 q_idle=0(#_ +8065:318) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:16:26] dispatch lane=build issue=#316 pid=61010 claim=ToanMobile
[20:16:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:17:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:18:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:18:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:19:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:19:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:20:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 316: live build lane (pid 61010) holds it
kept card 226: live build lane (pid 80078) holds it
kept card 318: live qa lane (pid 8065) holds it
[20:20:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:21:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:21:38] worker of #320 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2413s
[20:21:41] reaped stale lock + swept assignee on #320 (pid=47645)
[20:21:43] tick — Ready=8 Building=2 QA=2 Review=1 Blocked=6 lanes: b_idle=0(#226 +61010:316) b_workers=2/5 q_idle=0(#_ +8065:318) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:21:50] dispatch lane=qa issue=#320 pid=12382 claim=ToanMobile
[20:22:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:22:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:23:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:23:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:24:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:24:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:25:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:25:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:26:27] worker of #318 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1199s
[20:26:30] reaped stale lock + swept assignee on #318 (pid=8065)
[20:26:34] tick — Ready=8 Building=2 QA=1 Review=2 Blocked=6 lanes: b_idle=0(#226 +61010:316) b_workers=2/5 q_idle=0(#320) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:26:46] dispatch lane=review issue=#318 pid=19933 claim=ToanMobile
[20:26:46] qa workers: 5/5 running on the machine (5 here): holding
[20:26:46] qa workers: 5/5 running on the machine (5 here): holding
[20:27:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:27:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:28:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:28:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:29:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:30:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:30:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 316: live build lane (pid 61010) holds it
kept card 320: live qa lane (pid 12382) holds it
[20:31:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:31:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:32:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:32:39] worker of #316 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=955s
[20:32:42] reaped stale lock + swept assignee on #316 (pid=61010)
[20:32:48] tick — Ready=8 Building=1 QA=2 Review=2 Blocked=6 lanes: b_idle=0(#226) b_workers=1/5 q_idle=0(#320) q_workers=1/5 r_idle=0(#321 +19933:318) r_workers=2/5 waiting_on_you=0
[20:32:56] dispatch lane=qa issue=#316 pid=75499 claim=ToanMobile
[20:33:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:34:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:34:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:35:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:35:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:36:05] worker of #316 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=177s
[20:36:08] reaped stale lock + swept assignee on #316 (pid=75499)
[20:36:09] worker of #318 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=535s
[20:36:12] reaped stale lock + swept assignee on #318 (pid=19933)
[20:36:19] tick — Ready=8 Building=1 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#226) b_workers=1/5 q_idle=0(#320) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:36:38] dispatch lane=build issue=#323 pid=82772 claim=ToanMobile
[20:37:12] tick — Ready=7 Building=2 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#226 +82772:323) b_workers=2/5 q_idle=0(#320) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:37:27] preflight #325: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[20:37:35] dispatch lane=build issue=#325 pid=51760 claim=ToanMobile
[20:37:55] STOP 📋 5 in-flight worker(s) to wrap up
[20:37:55] STOP 
[20:37:55] STOP ─── #226 (lane=build, pid=80078) ───
[20:37:58] STOP   💬 issue comment posted on #226
[20:37:59] STOP   💬 PR comment posted on #340
[20:38:05] 🛑 stop marker .claude/super-board/runner/agent-workbench.stopped — board stopped by the user; runner exits (super-board run agent-workbench clears it)
[20:38:05] super-board run finished. manifest: docs/super-board/runs/2026-10-23-agent-workbench.md
[20:38:06] STOP   🔓 released assignee + lane labels on #226
[20:38:07] STOP   ☠ worker(build/#226) pid=80078 SIGTERMed
[20:38:07] STOP 
[20:38:07] STOP ─── #320 (lane=qa, pid=12382) ───
[20:38:09] STOP   💬 issue comment posted on #320
[20:38:11] STOP   💬 PR comment posted on #345
[20:38:18] STOP   🔓 released assignee + lane labels on #320
[20:38:19] STOP   ☠ worker(qa/#320) pid=12382 SIGTERMed
[20:38:19] STOP 
[20:38:19] STOP ─── #321 (lane=review, pid=98554) ───
[20:38:21] STOP   💬 issue comment posted on #321
[20:38:23] STOP   💬 PR comment posted on #342
[20:38:29] STOP   🔓 released assignee + lane labels on #321
[20:38:30] STOP   ☠ worker(review/#321) pid=98554 SIGTERMed
[20:38:30] STOP 
[20:38:30] STOP ─── #323 (lane=build, pid=82772) ───
[20:38:33] STOP   💬 issue comment posted on #323
[20:38:39] STOP   🔓 released assignee + lane labels on #323
[20:38:40] STOP   ☠ worker(build/#323) pid=82772 SIGTERMed
[20:38:40] STOP 
[20:38:40] STOP ─── #325 (lane=build, pid=51760) ───
[20:38:42] STOP   💬 issue comment posted on #325
[20:38:48] STOP   🔓 released assignee + lane labels on #325
[20:38:49] STOP   ☠ worker(build/#325) pid=51760 SIGTERMed
[20:38:49] STOP 
[20:38:49] STOP 🛑 stopping dispatcher loop
[20:38:49] STOP   ⊘ dispatcher pid=28913 already dead
[20:38:49] STOP 
[20:38:49] STOP 🧽 cleared .claude/super-board/inflight
[20:51:30] ▶ explicit start: cleared the stop marker (STOPPED_AT=2026-10-23T13:38:49Z BY=alex via super-board-stop.sh PID=68457 )
[20:51:30] super-board run started — config=agent-workbench base=main tick=30s max_workers=5 no_progress_cycles=240 max_dispatches=0
[20:51:37] ℹ stranded #325: keeping existing worktree .claude/worktrees/issue-325-build (branch issue-325-ocr-six-findings) for Builder to resume
[20:51:47] ↩ stranded #325: Building → Ready (branch none)
[20:51:51] ℹ stranded #323: keeping existing worktree .claude/worktrees/issue-323-build (branch issue-323-worktree-merge-umbrella) for Builder to resume
[20:51:58] ↩ stranded #323: Building → Ready (branch none)
[20:52:10] ↩ stranded #226: Building → Ready (branch issue-226-merge-gate-skip-verified-tree)
[20:52:11] initial Ready count: 9
[20:52:19] tick — Ready=9 Building=0 QA=1 Review=1 Blocked=7 lanes: b_idle=1(#_) b_workers=0/5 q_idle=1(#_) q_workers=0/5 r_idle=1(#_) r_workers=0/5 waiting_on_you=0
[20:52:19] ⚠ block-rate alert: 7/9 (77%)
[20:52:29] dispatch lane=review issue=#321 pid=36406 claim=ToanMobile
kept card 321: live review lane (pid 36406) holds it
[20:52:34] dispatch lane=qa issue=#320 pid=37338 claim=ToanMobile
[20:52:50] dispatch lane=build issue=#226 pid=40773 claim=ToanMobile
[20:53:23] tick — Ready=8 Building=1 QA=1 Review=1 Blocked=7 lanes: b_idle=0(#226) b_workers=1/5 q_idle=0(#320) q_workers=1/5 r_idle=0(#321) r_workers=1/5 waiting_on_you=0
[20:53:40] dispatch lane=build issue=#323 pid=63852 claim=ToanMobile
[20:54:20] tick — Ready=7 Building=2 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#226 +63852:323) b_workers=2/5 q_idle=0(#320) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[20:54:31] preflight #325: open PRs touch the same files — build after them — proceeding (merge gate rebases)
[20:54:39] dispatch lane=build issue=#325 pid=93930 claim=ToanMobile
[20:55:11] worker of #321 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=102s
[20:55:14] reaped stale lock + swept assignee on #321 (pid=36406)
[20:55:19] tick — Ready=6 Building=3 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#226 +63852:323 93930:325) b_workers=3/5 q_idle=0(#320) q_workers=1/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[20:55:40] dispatch lane=build issue=#327 pid=62915 claim=ToanMobile
[20:56:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:56:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:57:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:57:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:58:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:58:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[20:59:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:00:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:00:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:01:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:01:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:02:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:02:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 325: live build lane (pid 93930) holds it
kept card 327: live build lane (pid 62915) holds it
kept card 320: live qa lane (pid 37338) holds it
kept card 323: live build lane (pid 63852) holds it
kept card 226: live build lane (pid 40773) holds it
[21:03:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:03:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:04:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:04:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:05:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:05:53] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:06:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:06:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:07:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:08:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:08:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:09:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:09:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:10:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:10:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:11:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:11:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:12:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:12:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 327: live build lane (pid 62915) holds it
kept card 320: live qa lane (pid 37338) holds it
kept card 323: live build lane (pid 63852) holds it
[21:13:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:13:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:14:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:14:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:15:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:15:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:16:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:16:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:17:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:18:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:18:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:19:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:19:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:20:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:21:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:21:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:22:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:22:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 323: live build lane (pid 63852) holds it
kept card 325: live build lane (pid 93930) holds it
kept card 226: live build lane (pid 40773) holds it
[21:23:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:23:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:24:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:24:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:25:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:26:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:26:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:27:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:27:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:28:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:28:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:29:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:29:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:30:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:30:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:31:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:31:54] worker of #320 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=2340s
[21:31:57] reaped stale lock + swept assignee on #320 (pid=37338)
[21:32:03] tick — Ready=5 Building=4 QA=0 Review=1 Blocked=8 lanes: b_idle=0(#226 +63852:323 93930:325 62915:327) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#321) r_workers=0/5 waiting_on_you=0
[21:32:17] dispatch lane=review issue=#320 pid=20531 claim=ToanMobile
[21:32:17] qa workers: 5/5 running on the machine (5 here): holding
[21:32:51] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 325: live build lane (pid 93930) holds it
kept card 323: live build lane (pid 63852) holds it
kept card 327: live build lane (pid 62915) holds it
[21:33:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:33:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:34:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:35:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:35:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:36:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:36:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:37:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:37:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:38:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:38:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:39:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:39:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:40:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:41:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:41:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:42:02] worker of #320 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=580s
[21:42:05] reaped stale lock + swept assignee on #320 (pid=20531)
[21:42:10] tick — Ready=6 Building=4 QA=0 Review=0 Blocked=8 lanes: b_idle=0(#226 +63852:323 93930:325 62915:327) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[21:42:30] dispatch lane=build issue=#320 pid=45267 claim=ToanMobile
[21:43:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 320: live build lane (pid 45267) holds it
kept card 323: live build lane (pid 63852) holds it
kept card 226: live build lane (pid 40773) holds it
kept card 325: live build lane (pid 93930) holds it
[21:43:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:44:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:44:35] worker of #327 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=2906s
[21:44:38] reaped stale lock + swept assignee on #327 (pid=62915)
[21:44:46] ℹ stranded #327: keeping existing worktree .claude/worktrees/issue-327-build (branch issue-327-kept-lock-orphan-report) for Builder to resume
[21:44:53] ↩ stranded #327: Building → Ready (branch none)
[21:44:55] tick — Ready=6 Building=4 QA=0 Review=0 Blocked=8 lanes: b_idle=0(#226 +63852:323 93930:325 45267:320) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[21:45:14] dispatch lane=build issue=#327 pid=90864 claim=ToanMobile
[21:45:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:46:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:46:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:47:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:47:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:48:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:48:54] worker of #325 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=3245s
[21:48:58] reaped stale lock + swept assignee on #325 (pid=93930)
[21:49:03] tick — Ready=5 Building=4 QA=1 Review=0 Blocked=8 lanes: b_idle=0(#226 +63852:323 45267:320 90864:327) b_workers=4/5 q_idle=1(#320) q_workers=0/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[21:49:12] dispatch lane=qa issue=#325 pid=24129 claim=ToanMobile
[21:49:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:50:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:50:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:51:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:51:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:52:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:52:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:53:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 325: live qa lane (pid 24129) holds it
kept card 320: live build lane (pid 45267) holds it
kept card 226: live build lane (pid 40773) holds it
kept card 327: live build lane (pid 90864) holds it
[21:54:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:54:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:55:02] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:55:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:56:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:56:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:57:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:57:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:58:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:58:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:59:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[21:59:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:00:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:00:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:01:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:02:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:02:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:03:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:03:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 325: live qa lane (pid 24129) holds it
kept card 323: live build lane (pid 63852) holds it
[22:04:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:04:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:05:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:05:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:06:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:06:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:07:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:07:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:08:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:08:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:09:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:09:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:10:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:10:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:11:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:11:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:12:29] worker of #323 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4727s
[22:12:32] reaped stale lock + swept assignee on #323 (pid=63852)
[22:12:40] tick — Ready=6 Building=3 QA=3 Review=1 Blocked=2 lanes: b_idle=0(#226 +45267:320 90864:327) b_workers=3/5 q_idle=0(#325) q_workers=1/5 r_idle=1(#320) r_workers=0/5 waiting_on_you=0
[22:12:49] dispatch lane=review issue=#291 pid=86646 claim=ToanMobile
[22:12:49] qa workers: 5/5 running on the machine (5 here): holding
[22:12:49] qa workers: 5/5 running on the machine (5 here): holding
[22:13:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:13:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 327: live build lane (pid 90864) holds it
kept card 291: live review lane (pid 86646) holds it
kept card 226: live build lane (pid 40773) holds it
kept card 325: live qa lane (pid 24129) holds it
[22:14:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:14:51] worker of #291 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=96s
[22:14:51] ⚠ worker of #291 (lane review) ended 96s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: {"type":"system","subtype":"task_summary","detail":null,"uuid":"f9069de5-8d79-4f3f-85fe-975a0746699c","session_id":"2d611ce5-d991-469d-aafb-b55f62d75373"}
[22:14:54] reaped stale lock + swept assignee on #291 (pid=86646)
[22:14:57] tick — Ready=7 Building=3 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#226 +45267:320 90864:327) b_workers=3/5 q_idle=0(#325) q_workers=1/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[22:15:03] dispatch lane=qa issue=#316 pid=75911 claim=ToanMobile
[22:15:21] dispatch lane=build issue=#240 pid=81043 claim=ToanMobile
[22:15:51] worker of #325 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1545s
[22:15:54] reaped stale lock + swept assignee on #325 (pid=24129)
[22:15:54] worker of #327 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1816s
[22:15:58] reaped stale lock + swept assignee on #327 (pid=90864)
[22:16:00] tick — Ready=6 Building=3 QA=3 Review=1 Blocked=2 lanes: b_idle=0(#226 +45267:320 81043:240) b_workers=3/5 q_idle=0(#316) q_workers=1/5 r_idle=1(#291) r_workers=0/5 waiting_on_you=0
[22:16:13] dispatch lane=review issue=#325 pid=38397 claim=ToanMobile
[22:16:13] qa workers: 5/5 running on the machine (5 here): holding
[22:16:13] qa workers: 5/5 running on the machine (5 here): holding
[22:16:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:17:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:17:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:18:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:18:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:19:19] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:19:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:20:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:20:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:21:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:22:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:22:33] worker of #325 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=361s
[22:22:37] reaped stale lock + swept assignee on #325 (pid=38397)
[22:22:52] tick — Ready=6 Building=3 QA=3 Review=0 Blocked=2 lanes: b_idle=0(#226 +45267:320 81043:240) b_workers=3/5 q_idle=0(#316) q_workers=1/5 r_idle=1(#325) r_workers=0/5 waiting_on_you=0
[22:23:02] dispatch lane=qa issue=#307 pid=65772 claim=ToanMobile
[22:23:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:24:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 240: live build lane (pid 81043) holds it
kept card 320: live build lane (pid 45267) holds it
kept card 316: live qa lane (pid 75911) holds it
[22:24:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:25:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:25:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:26:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:26:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:27:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:27:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:28:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:28:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:29:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:30:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:30:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:31:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:31:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:32:16] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:32:47] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:33:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:33:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:34:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 316: live qa lane (pid 75911) holds it
kept card 240: live build lane (pid 81043) holds it
kept card 307: live qa lane (pid 65772) holds it
kept card 320: live build lane (pid 45267) holds it
[22:34:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:35:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:36:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:36:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:37:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:37:35] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:38:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:38:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:39:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:39:39] worker of #316 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1466s
[22:39:43] reaped stale lock + swept assignee on #316 (pid=75911)
[22:39:47] tick — Ready=6 Building=3 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#226 +45267:320 81043:240) b_workers=3/5 q_idle=0(#316 +65772:307) q_workers=1/5 r_idle=1(#325) r_workers=0/5 waiting_on_you=0
[22:39:58] dispatch lane=review issue=#316 pid=63264 claim=ToanMobile
[22:39:58] qa workers: 5/5 running on the machine (5 here): holding
[22:39:58] qa workers: 5/5 running on the machine (5 here): holding
[22:40:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:41:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:41:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:42:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:42:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:43:09] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:43:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:44:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:44:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 240: live build lane (pid 81043) holds it
kept card 307: live qa lane (pid 65772) holds it
kept card 316: live review lane (pid 63264) holds it
[22:45:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:45:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:46:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:46:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:47:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:47:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:48:30] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:49:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:49:39] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:50:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:50:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:51:18] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:51:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:52:25] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:52:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:53:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:54:06] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:54:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:55:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 226: live build lane (pid 40773) holds it
kept card 320: live build lane (pid 45267) holds it
kept card 307: live qa lane (pid 65772) holds it
[22:55:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:56:21] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:56:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:57:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:58:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:58:37] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:59:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[22:59:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:00:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:00:48] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:01:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:01:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:02:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:02:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:03:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:03:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:04:28] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=7873s
[23:04:31] reaped stale lock + swept assignee on #226 (pid=40773)
[23:04:31] worker of #320 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=4911s
[23:04:34] reaped stale lock + swept assignee on #320 (pid=45267)
[23:04:48] ↩ stranded #320: Building → Ready (branch issue-320-hooks-settings-gom)
[23:04:49] tick — Ready=7 Building=1 QA=3 Review=1 Blocked=2 lanes: b_idle=0(#226 +81043:240) b_workers=1/5 q_idle=0(#316 +65772:307) q_workers=1/5 r_idle=0(#316) r_workers=1/5 waiting_on_you=0
[23:04:55] dispatch lane=qa issue=#226 pid=74472 claim=ToanMobile
[23:05:11] dispatch lane=build issue=#319 pid=87478 claim=ToanMobile
[23:05:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 316: live review lane (pid 63264) holds it
kept card 226: live qa lane (pid 74472) holds it
kept card 240: live build lane (pid 81043) holds it
[23:06:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:06:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:07:14] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:07:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:08:15] worker of #226 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=198s
[23:08:18] reaped stale lock + swept assignee on #226 (pid=74472)
[23:08:22] tick — Ready=6 Building=2 QA=2 Review=2 Blocked=2 lanes: b_idle=0(#319 +81043:240) b_workers=2/5 q_idle=0(#226 +65772:307) q_workers=1/5 r_idle=0(#316) r_workers=1/5 waiting_on_you=0
[23:08:34] dispatch lane=review issue=#226 pid=92714 claim=ToanMobile
[23:08:34] qa workers: 5/5 running on the machine (5 here): holding
[23:08:34] qa workers: 5/5 running on the machine (5 here): holding
[23:09:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:09:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:10:07] worker of #316 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=1806s
[23:10:10] reaped stale lock + swept assignee on #316 (pid=63264)
[23:10:18] tick — Ready=6 Building=2 QA=2 Review=1 Blocked=2 lanes: b_idle=0(#319 +81043:240) b_workers=2/5 q_idle=0(#226 +65772:307) q_workers=1/5 r_idle=0(#316 +92714:226) r_workers=1/5 waiting_on_you=0
[23:10:24] dispatch lane=qa issue=#327 pid=92041 claim=ToanMobile
[23:10:55] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:11:26] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:11:57] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:12:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:13:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:13:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:14:05] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:14:38] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:15:10] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:15:41] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:16:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 327: live qa lane (pid 92041) holds it
kept card 319: live build lane (pid 87478) holds it
kept card 307: live qa lane (pid 65772) holds it
kept card 226: live review lane (pid 92714) holds it
[23:16:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:17:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:17:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:18:22] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:18:54] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:19:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:19:59] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:20:31] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:21:03] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:21:34] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:22:07] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:22:37] worker of #226 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=819s
[23:22:42] reaped stale lock + swept assignee on #226 (pid=92714)
[23:22:47] tick — Ready=7 Building=2 QA=2 Review=0 Blocked=2 lanes: b_idle=0(#319 +81043:240) b_workers=2/5 q_idle=0(#327 +65772:307) q_workers=2/5 r_idle=1(#316) r_workers=0/5 waiting_on_you=0
[23:23:16] dispatch lane=build issue=#226 pid=26986 claim=ToanMobile
[23:23:50] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:24:23] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:24:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:25:29] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:26:01] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:26:33] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 319: live build lane (pid 87478) holds it
kept card 240: live build lane (pid 81043) holds it
kept card 327: live qa lane (pid 92041) holds it
kept card 307: live qa lane (pid 65772) holds it
[23:27:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:27:36] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:28:08] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:28:40] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:29:11] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:29:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:30:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:30:46] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:31:17] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:31:49] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:32:20] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:32:52] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:33:24] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:33:56] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:34:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:34:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:35:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:35:59] worker of #327 (lane qa) exit record: worker_exit: exit=0 signal=none elapsed=1522s
[23:36:01] reaped stale lock + swept assignee on #327 (pid=92041)
[23:36:04] tick — Ready=6 Building=3 QA=1 Review=1 Blocked=2 lanes: b_idle=0(#319 +81043:240 26986:226) b_workers=3/5 q_idle=0(#327 +65772:307) q_workers=1/5 r_idle=1(#316) r_workers=0/5 waiting_on_you=0
[23:36:13] dispatch lane=review issue=#327 pid=69857 claim=ToanMobile
[23:36:13] qa workers: 5/5 running on the machine (5 here): holding
[23:36:13] qa workers: 5/5 running on the machine (5 here): holding
[23:36:44] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
kept card 307: live qa lane (pid 65772) holds it
kept card 327: live review lane (pid 69857) holds it
kept card 240: live build lane (pid 81043) holds it
kept card 226: live build lane (pid 26986) holds it
[23:37:15] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:37:45] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:38:16] worker of #319 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1974s
[23:38:18] reaped stale lock + swept assignee on #319 (pid=87478)
[23:38:27] tick — Ready=6 Building=2 QA=1 Review=1 Blocked=3 lanes: b_idle=0(#319 +81043:240 26986:226) b_workers=2/5 q_idle=0(#327 +65772:307) q_workers=1/5 r_idle=0(#327) r_workers=1/5 waiting_on_you=0
[23:38:42] dispatch lane=build issue=#320 pid=4777 claim=ToanMobile
[23:39:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:39:43] worker of #327 (lane review) exit record: worker_exit: exit=0 signal=none elapsed=196s
[23:39:46] reaped stale lock + swept assignee on #327 (pid=69857)
[23:39:55] tick — Ready=5 Building=3 QA=1 Review=0 Blocked=3 lanes: b_idle=0(#320 +81043:240 26986:226) b_workers=3/5 q_idle=0(#327 +65772:307) q_workers=1/5 r_idle=1(#327) r_workers=0/5 waiting_on_you=0
[23:40:11] dispatch lane=build issue=#323 pid=44909 claim=ToanMobile
[23:40:42] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:41:12] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:41:43] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:42:13] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:42:44] worker of #226 (lane build) exit record: worker_exit: exit=0 signal=none elapsed=1157s
[23:42:47] reaped stale lock + swept assignee on #226 (pid=26986)
[23:42:50] tick — Ready=4 Building=3 QA=2 Review=0 Blocked=3 lanes: b_idle=0(#320 +81043:240 44909:323) b_workers=3/5 q_idle=0(#327 +65772:307) q_workers=1/5 r_idle=1(#327) r_workers=0/5 waiting_on_you=0
[23:42:55] dispatch lane=qa issue=#226 pid=19501 claim=ToanMobile
[23:43:27] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:43:58] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:44:28] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:45:00] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:45:32] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
[23:46:04] tick — cap reached (machine at 5 workers, 5 here) — skipping GraphQL fetch, sleeping 30s
