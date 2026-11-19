# QA v4 · PR #1309 · issue #1308
Base head 2b54a8c7 + merge origin/main (c8427d5b).
- test_dexscan.sh rc=0 (có ca XXE DOCTYPE/ENTITY -> exit 2)
- test_dump_view_hierarchy.sh rc=0 (serial bị deny -> exit 2)
- test_agent_bridge_antigravity.sh rc=0 (có agent-kit health exit 0)
- test_collect_file_not_planned.sh rc=0
- agent_bridge.sh: ROOT chỉ lấy từ payload `cwd`/$PWD, không từ toolCall.args.Cwd
Không có ảnh: không đụng UI.
