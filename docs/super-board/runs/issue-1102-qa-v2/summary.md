# QA v2 · issue #1102 · PR #1173 head e79811b

- RED (hook cũ = session_lock.py của 982a9f0, test mới): rc 1, 8 ca "for-loop R1" rc 0 muốn rc 2.
- GREEN (head e79811b): test_session_lock_trunk_for_loop_1102.sh rc 0.
- 9 test session_lock cũ + test_runner_agy_cwd_1102.sh: rc 0.
- Probe thêm (hook thật): read -p, eval, t+=, (( )), let, printf -v "t", local, read "t"/'t', for lồng tái dùng tên, unset: đều rc 2; ca đối chứng rc 0.
