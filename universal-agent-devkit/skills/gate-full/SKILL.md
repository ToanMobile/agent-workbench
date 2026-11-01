---
name: gate-full
description: "Chạy post-fix-gate --full THẬT SỰ trên origin/main (hoặc ref chỉ định) trong scratch tách rời, đọc tóm tắt lượt đêm, cài/gỡ/xem lịch 00:00. Dùng khi cần kiểm cả bộ suite trên main (merge/push giờ chỉ chạy gate scoped), khi hỏi 'đêm qua main xanh không', 'chạy full', 'gate-full', khi thẻ P1 'gate-full đêm' xuất hiện, hoặc khi cài lịch đêm. Bỏ qua khi chỉ cần biên nhận task (`post-fix-gate.py --run-tests --brief`)."
---

# gate-full — lượt --full trên main (#644)

Gate mặc định là **scoped**: task, merge và push không còn chạy `--full`. Lượt full chạy ở đây — tay, hoặc 00:00 mỗi đêm (giờ máy, Asia/Ho_Chi_Minh).

## Chạy tay

```bash
python3 .agents/devkit/bin/gate_full.py run                       # origin/main của repo đang đứng
python3 .agents/devkit/bin/gate_full.py run --ref origin/main --repo <repo> --max-wait-s 0
python3 .agents/devkit/bin/gate_full.py run --dry-run             # chỉ in kế hoạch: sha, khoá, scratch, tải
```

Một lượt: khoá `<git common dir>/postfix-gate/gate-full.lock` (lượt trước còn sống ⇒ `skip`, exit 0) · chờ tải 1 phút ≤ `capacity.py hold_load`
(tối đa `--max-wait-s`, mặc định 2 h, rồi chạy luôn) · `git fetch` · scratch `postfix-gate/gate-full-scratch-<stamp>` tách rời ở sha của ref, cài
DevKit như merge train · `post-fix-gate.py --run-tests --tree HEAD --no-cache --brief --json` · `agent-kit test` (cả bộ test DevKit; REG-DK-ALL-01
trong gate chỉ chạy test impacted) · gỡ scratch, nhả khoá. Lượt đêm chạy nice 10 (đặt ở plist, không ở gate_full.py; plist không có ProcessType=Background).

`--tree HEAD` chỉ nhận cây đã có trên origin: `--ref` phải là commit origin đã có (mặc định `origin/main`), không phải nhánh chưa push.

Kết quả (exit): `0` xanh hoặc skip · `1` đỏ (có suite FAIL thật) · `3` chưa kết luận (gate exit 2/4/5, TIMEOUT, BUSY, đỏ do môi trường — không thẻ;
hoặc `red-env`: mọi suite đỏ đều nhóm b — có thẻ) · `2` lỗi chuẩn bị (ref, scratch).

## Đọc kết quả

Lượt của lịch đêm ghi vào `~/Library/Logs/devkit-gate-full/<slug>/` riêng từng repo (`<slug>` = tên thư mục repo + 8 ký tự sha1 đường dẫn,
`status` in đường dẫn); chạy tay không đặt `DEVKIT_GATE_FULL_LOG_DIR` thì ghi thẳng vào `~/Library/Logs/devkit-gate-full/`.

- `<thư mục log>/summary-latest.md` (và `summary-<yyyymmdd>.md`): kết quả, thời gian, tải lúc bắt đầu, có chờ tải không,
  suite đỏ, commit nghi vấn, link thẻ, đường dẫn log; lượt đỏ thêm mục "Truy vết" (#759): khoảng `last_full_green_sha..sha`, PR + thẻ của
  từng commit, với mỗi suite đỏ các commit đụng file test / nguồn nó chạm (đồ thị của `bin/scoped_gate.py`) / `watch_files` cụ thể,
  mức tin cậy `chắc` (commit nghi vấn của chia đôi và đụng file) · `nghi` · `không rõ`.
- `<thư mục log>/trace-latest.json`: cùng truy vết cho máy đọc (`result`, `sha`, `last_green`, `commits`, `tests[].candidates`); lượt
  không đỏ thì `tests` rỗng.
- `<thư mục log>/<yyyymmdd-HHMMSS>.log`: toàn văn gate, `agent-kit test`, từng bước chia đôi.
- `<git common dir>/postfix-gate/last_full_green_sha`, `nightly/full_pass.json`, `nightly/history.jsonl` (một dòng mỗi lượt).

## Đỏ: chia đôi + thẻ P1

0. Nhóm b (#700): suite đỏ có nhãn `"timing": true` trong ma trận, hoặc trong toàn văn log của suite MỌI khối hỏng lá (`✖/✗ …` + dòng thụt
   sâu hơn; khối có khối con chỉ xét khối con) có dấu hiệu thời gian thực / môi trường (watchdog "quá lớn / quá phức tạp…", `killed after
   …s (deadline)`, `Killed: 9`), hoặc không có khối hỏng nào mà có dòng tổng kết hook contract `ENV-BLOCKED: hook watchdog fired under
   load, no verdict` (và không có Traceback / dòng `FAIL` trần). Không bao giờ nhóm b (#749): lần đầu đỏ thật dù lần chạy lại (FLAKY_RETRY)
   dính watchdog, dòng `FAIL …` trần không dấu hiệu trong khối có khối con, log bằng chứng bị cắt đầu. Mọi suite đỏ đều nhóm b ⇒
   `red-env`: không chia đôi, không ghi `last_full_green_sha`, thẻ risk 🟡. `DEVKIT_GATE_FULL_BISECT=0` không bao giờ chia đôi, `=1` luôn chia đôi
   (ra commit nghi vấn và thấy commit trước nó xanh ở lượt này ⇒ `red`, exit 1, 🔴 — #748), `auto` (mặc định) như trên.
1. Chạy lại CHỈ suite/test đỏ ở đỉnh (đường dẫn `✖ tests/…` của run_impacted, hoặc lệnh của suite đỏ). Không tái hiện ⇒ ghi "flaky?", không nghi ai,
   result `red-env`.
2. Chia đôi các merge first-parent `last_full_green_sha..sha` (≤ 16; chưa có lượt xanh: 8 merge gần nhất) ⇒ merge đầu tiên làm đỏ.
3. Tạo thẻ qua `scripts/governance/create_task.py --new-card … --labels bug`, tiêu đề `🐛 [fix] P1 gate-full đêm <yyyy-mm-dd>: <suite> đỏ`,
   risk `🔴 High — main đỏ`. Đã có thẻ mở cùng suite đỏ (tiêu đề P1, hoặc mã REG-/BUG- trong tiêu đề/body) thì comment vào đó, không tạo trùng.

Thẻ đến tay: đọc summary + log, sửa hoặc revert commit nghi vấn qua luồng thường (task, biên nhận, merge), rồi chạy tay `gate_full.py run` để xác nhận xanh.

## Lịch đêm

```bash
bash .agents/devkit/bin/gate-full-schedule.sh install --repo "$(pwd)"    # 00:00 mỗi ngày (--hour/--minute để đổi)
bash .agents/devkit/bin/gate-full-schedule.sh status                     # launchctl print rút gọn + summary-latest.md
bash .agents/devkit/bin/gate-full-schedule.sh uninstall                  # status / uninstall: --repo mặc định gốc git của thư mục hiện tại
```

Mỗi repo một LaunchAgent `com.toanmobile.devkit.gate-full.<slug>` (`~/Library/LaunchAgents/<label>.plist`, `bootstrap gui/<uid>`, không sudo):
cài repo B không gỡ lịch repo A. `/usr/bin/nice -n 10 <python3 tuyệt đối> gate_full.py run --repo <repo>`, PATH chứa thư mục của python3/git/gh
lấy lúc cài, `TZ=Asia/Ho_Chi_Minh`, `DEVKIT_GATE_FULL_LOG_DIR=~/Library/Logs/devkit-gate-full/<slug>`, `RunAtLoad` false, stdout/stderr vào
thư mục log đó. Máy ngủ lúc 00:00 thì launchd chạy bù khi thức dậy; đêm trùng do khoá pid bỏ qua. Label cũ chung `com.toanmobile.devkit.gate-full`
(trước lịch theo repo) script không đụng tới; việc chuyển nó sang label theo repo làm riêng, không phải việc của agent.
