#!/usr/bin/env bash
# Test hồi quy #562: super-board-status.py đọc merge-train.state / merge-queue.labeled.
#  1. read_merge_train: pid sống -> train với thẻ lấy từ ref `issue-<N>-…`; pid chết hoặc file hỏng/thiếu -> None (file mồ côi bị bỏ qua).
#  2. train_line: `🚂 Merge train: #532 #538 #523 · gate --full · 12m`.
#  3. render_kanban: thẻ Review trong train mang nhãn gate merge; thẻ có PR trong hàng (merge-queue.labeled) mà chưa vào train: "chờ train";
#     thẻ khác không nhãn; không truyền review_tag_for thì đầu ra như cũ.
# Test nạp module rồi gọi hàm đọc file và hàm vẽ với dữ liệu trong thư mục tạm. Viết cho bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

OUT="$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" 2>&1 <<'PY'
import importlib.util, sys, tempfile, pathlib, os
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d = pathlib.Path(tempfile.mkdtemp()); (d / "super-board").mkdir()
state = d / "super-board" / "merge-train.state"
state.write_text("pid 4242\nstarted_at 1000\nstep gate\npr 550 " + "a" * 40 + " issue-532-x\npr 552 " + "b" * 40 + " issue-538-y\npr 539 " + "c" * 40 + " issue-523-z\n")
live = lambda pid: pid == 4242
t = m.read_merge_train(d, 1000 + 12 * 60 + 5, live)
print("cards=%s" % t["cards"])
print("elapsed=%s step=%s" % (t["elapsed_s"], t["step"]))
print("line=%s" % m.train_line(t))
print("dead_none=%s" % (m.read_merge_train(d, 2000, lambda pid: False) is None))
state.write_text("garbage\n")
print("corrupt_none=%s" % (m.read_merge_train(d, 2000, live) is None))
state.unlink()
print("missing_none=%s" % (m.read_merge_train(d, 2000, live) is None))
print("nodir_none=%s" % (m.read_merge_train(None, 2000, live) is None))
print("live_pid_real=%s" % m.pid_alive(os.getpid()))
state.write_text("pid 4242\nstarted_at 1000\nstep gate\npr 550 " + "a" * 40 + " issue-532-x\n")
t = m.read_merge_train(d, 1100, live)
(d / "super-board" / "merge-queue.labeled").write_text("550 " + "a" * 40 + " 1 issue-532-x\n560 " + "d" * 40 + " 2 issue-540-w\n570 " + "e" * 40 + " 3\n")
q = m.read_queued_cards(d)
print("queued=%s" % sorted(q))
tag = m.train_tag_for(t, q)
print("tags=%r|%r|%r" % (tag(532), tag(540), tag(999)))
items = [{"number": n, "title": "t%d" % n, "labels": [], "status": "Review"} for n in (532, 540, 999)]
by = m.group_by_status(items)
g = lambda n: "·"
box = m.render_kanban(by, g, g, tag)
print("box_tags=%s" % ("merge gate" in box and "wait train" in box))
print("plain_same=%s" % (m.render_kanban(by, g, g) == m.render_kanban(by, g, g, None) and "merge gate" not in m.render_kanban(by, g, g)))
PY
)"
chk() { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
chk "cards=[532, 538, 523]" && chk "elapsed=725 step=gate" && ok "read_merge_train: pid sống -> 3 thẻ từ ref, thời gian chạy" || fail "read_merge_train: $(echo "$OUT" | tr '\n' ' ')"
chk "line=🚂 Merge train: #532 #538 #523 · gate --full · 12m" && ok "train_line: dòng Workers đúng mẫu" || fail "train_line: $(echo "$OUT" | tr '\n' ' ')"
chk "dead_none=True" && chk "corrupt_none=True" && chk "missing_none=True" && chk "nodir_none=True" && ok "pid chết / file hỏng / thiếu: không hiện train" || fail "orphan: $(echo "$OUT" | tr '\n' ' ')"
chk "live_pid_real=True" && ok "pid_alive: tiến trình hiện tại sống" || fail "pid_alive: $(echo "$OUT" | tr '\n' ' ')"
chk "queued=[532, 540]" && ok "read_queued_cards: dòng thiếu ref bị bỏ qua" || fail "queued: $(echo "$OUT" | tr '\n' ' ')"
chk "tags=$(printf "'🚂 merge gate'|'⏳ wait train'|''")" && ok "train_tag_for: trong train / chờ train / không nhãn" || fail "tags: $(echo "$OUT" | tr '\n' ' ')"
chk "box_tags=True" && chk "plain_same=True" && ok "render_kanban: nhãn thẻ Review, không truyền thì như cũ" || fail "kanban: $(echo "$OUT" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "✅ test_status_merge_train: all passed" || { echo "❌ test_status_merge_train: $FAILS failed"; exit 1; }
