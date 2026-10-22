#!/usr/bin/env bash
# Chạy một lệnh worker và ghi `worker_exit: exit=<mã> signal=<tên|none> elapsed=<s>s` vào stdout (log của worker) khi nó kết thúc.
# #237: worker chết im lặng sau hơn 1 giờ, log không có mã thoát hay tín hiệu nên không biết vì sao. Dùng: wrap.sh <lệnh> [đối số…].
# TERM/INT/HUP gửi tới wrapper được chuyển cho worker (check_lane_zombie vẫn dừng được worker); wrapper thoát với mã của worker.
start=$(date +%s)
"$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP
wait "$child"; rc=$?
while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
sig=none
[ "$rc" -le 128 ] || sig=$(kill -l $((rc - 128)) 2>/dev/null || echo "$((rc - 128))")
printf '\nworker_exit: exit=%s signal=%s elapsed=%ss\n' "$rc" "$sig" "$(($(date +%s) - start))"
exit "$rc"
