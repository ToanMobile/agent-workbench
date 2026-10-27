#!/usr/bin/env bash
# Chạy một lệnh worker và ghi `worker_exit: exit=<mã> signal=<tên|none> elapsed=<s>s` vào stdout (log của worker) khi nó kết thúc.
# #237: worker chết im lặng sau hơn 1 giờ, log không có mã thoát hay tín hiệu nên không biết vì sao. Dùng: wrap.sh <lệnh> [đối số…].
# TERM/INT/HUP gửi tới wrapper được chuyển cho worker (check_lane_zombie vẫn dừng được worker); wrapper thoát với mã của worker.
start=$(date +%s)
child=
# #489: TERM tới con trước lúc nó exec bị trap kế thừa bắt rồi mất khi exec, con chạy tiếp và wrapper chờ mãi (kill + wait treo 900 s).
# Ba chỗ chặn: con bỏ trap trước exec (TERM giết ngay, không bị nuốt); TERM tới trước `child=$!` chỉ ghi cờ term rồi gửi sau khi có pid
# (không `exit` bỏ con mồ côi); gửi lại một lần sau 1 s nếu wrapper còn sống (còn sống = con chưa bị thu, pid chưa tái dùng).
term=
trap 'term=1; [ -z "$child" ] || { kill -TERM "$child" 2>/dev/null; ( sleep 1; kill -0 "$$" 2>/dev/null && kill -TERM "$child" 2>/dev/null ) >/dev/null 2>&1 & }' TERM INT HUP
# Vòng sửa 1 (F4): mọi worker runner phóng (build/qa/review/merge, mọi engine) đi qua wrapper này, nên cờ worker board đặt ở đây;
# gate / merge-train dựa vào nó để từ chối đường lách hàng đợi. Không export trong runner để môi trường của runner không đổi sau lượt giao đầu.
export SB_BOARD_WORKER=1
( trap - TERM INT HUP; exec "$@" ) &
child=$!
[ -z "$term" ] || kill -TERM "$child" 2>/dev/null
# ponytail: wrapper bị SIGKILL (OOM, kill -9) không chạy được trap nên không ghi exit record và con thành orphan; startup_orphan_workers dọn con ở lần khởi động runner sau.
wait "$child"; rc=$?
while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
sig=none
[ "$rc" -le 128 ] || sig=$(kill -l $((rc - 128)) 2>/dev/null || echo "$((rc - 128))")
printf '\nworker_exit: exit=%s signal=%s elapsed=%ss\n' "$rc" "$sig" "$(($(date +%s) - start))"
exit "$rc"
