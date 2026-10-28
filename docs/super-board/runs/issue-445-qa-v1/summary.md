# QA #445 — vòng 1 (head 0e161718)

Lệnh: `bash tests/super-board/test_runner_watchdog.sh`

| AC | Kết quả | Bằng chứng |
|---|---|---|
| Không còn dòng "command not found" | ✅ | exit 0; stderr harness ca 12 rỗng; ca harness mới PASS |
| Ca 12 ĐỎ khi raw_entry_ok luôn trả 1 | ✅ | đột biến `return 1` ở dòng 106: exit 1, `✖ safe_path let a repo path through`; khôi phục: exit 0 |

Ca symlink-trong-repo-trỏ-ra-ngoài: XANH với code thật. Không có UI nên không có ảnh.
