# QA v1 #576 (head 0dd3bfd8 + merge origin/main)
- Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_super_board_no_main_merge.sh` -> exit 0, S1 (x2), S2, S3 XANH.
- ĐỎ: chép integrate.py + worktree.py của origin/main vào cây, chạy lại cùng test -> 3 ✖ (S1 status merged, S1 main đổi, S2 integrate chạy gate rc=1, không rc=2); S3 vẫn ✔. Khôi phục bằng `git show HEAD:<file>`.
- Gate impacted `post-fix-gate.py --run-tests --brief`: PASS 14/14 sau merge origin/main.
- Không UI, không ảnh. Không sửa test cũ.
