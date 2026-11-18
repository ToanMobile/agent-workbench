# QA #1222 v2 (PR #1223, head 68947163, vòng 2 sau khi sửa thân PR)
- Code không đổi từ v1; chỉ thân PR được viết lại đủ khối sb:ac (merge gate ac-check exit 11)
- Lệnh: bash tests/super-board/<test>.sh (5 file) trên head đã merge origin/main (Already up to date): rc=0 cả 5
- AC1 = ca A (CLOSED + ac-open: move Done thành công), AC2 = ca B (thẻ MỞ vẫn bị từ chối exit 5), AC3 = ca D (dispatch_lane bỏ qua issue CLOSED)
- ĐỎ trên main: ca A, C, D (bằng chứng v1)
