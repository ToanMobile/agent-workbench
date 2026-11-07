---
name: gate-full
description: "Dùng khi cần kiểm cả bộ suite trên main, khi hỏi 'đêm qua main xanh không', 'chạy full', 'gate-full', khi thẻ P1 'gate-full đêm' xuất hiện, hoặc khi cài lịch đêm. Bỏ qua khi chỉ cần biên nhận task (`post-fix-gate.py --run-tests --brief`)."
---

# gate-full — lượt --full trên main (#644)

Gate mặc định là **scoped**: task, merge và push không còn chạy `--full`; từ gate speed v26 chỉ test kit trực tiếp chặn, phần còn lại
`deferred_to_heavy`. Heavy gate (lượt full) chạy ở đây — tay, hoặc 00:00 thứ Hai + thứ Năm (giờ máy, Asia/Ho_Chi_Minh).

## Phạm vi

Chạy post-fix-gate --full THẬT SỰ trên origin/main (hoặc ref chỉ định) trong scratch tách rời, đọc tóm tắt lượt đêm, cài/gỡ/xem lịch 00:00. Merge/push giờ chỉ chạy gate scoped, nên cả bộ suite trên main chỉ được kiểm ở đây.

## Chạy tay

```bash
python3 .agents/devkit/bin/gate_full.py run                       # origin/main của repo đang đứng
python3 .agents/devkit/bin/gate_full.py run --ref origin/main --repo <repo> --max-wait-s 0
python3 .agents/devkit/bin/gate_full.py run --dry-run             # chỉ in kế hoạch: sha, khoá, scratch, tải
python3 .agents/devkit/bin/gate_full.py run --force               # chạy dù không có gì mới; trước phát hành chạy lệnh này (không cổng nào ép)
```

Không có gì mới (fetch thành công VÀ sha của ref == `last_full_green_sha` VÀ hash cây kit HEAD == `last_full_green_kit`) ⇒ `skip`, exit 0,
một dòng history `skip_reason: no-new-commit`; fetch lỗi hoặc thiếu một bên ⇒ chạy. Khoá bận cũng ghi dòng history (`skip_reason: lock` /
`global-lock`). `--force`: luôn chạy, mất khoá ⇒ exit 3. Nút "Chạy gate full" của Agent Office luôn thêm `--force`.

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

## Đỏ: chỉ đỏ MỚI có thẻ (v26 mục 6)

Mốc = dòng `nightly/history.jsonl` cuối có result `green` / `red` / `red-env` mà sha là tổ tiên của sha hiện tại (không bao giờ skip,
inconclusive, aborted, error). Đỏ mới = suite không có trong `red_tests` của mốc, đường test mới, hoặc dòng `✖` mới (đã chuẩn hoá pid, đường
tạm, số đứng riêng, sha hex). Đỏ kinh niên: không chia đôi, không thẻ, không comment, không tính lọt lưới. Mỗi đỏ mới (tối đa 5) chia đôi
riêng từ sha của mốc (≤ 128 commit first-parent; ca mới trong file kinh niên chỉ "đỏ" khi output có đúng dòng đó; mốc == đỉnh ⇒ không nghi
ai, ghi kit đổi / flaky) — `suspects` trong history. Suite mới ⇒ thẻ riêng tiêu đề mang tên nó (đã có thẻ mở ⇒ comment); ca mới của suite
kinh niên ⇒ comment vào thẻ mở nêu đúng ca. gh lỗi khi tìm thẻ trùng / comment lỗi / tạo thẻ lỗi ⇒ `unreported`, suite không vào mốc, lượt
sau báo lại. Mốc dạng cũ (dòng red không có `red_tests`) chỉ gieo mốc, không thẻ. Lọt lưới (`escape`): chỉ đỏ mới; test gate scoped chọn
mà hoãn tới heavy gate (`scoped_gate.cap_selection`) ⇒ `deferred`, không phải lọt lưới. Không có mốc history: hành vi cũ bên dưới.

## Đỏ: chia đôi + thẻ P1 (không có mốc history)

0. Nhóm b (#700): suite đỏ có nhãn `"timing": true` trong ma trận; suite runner kit (run_impacted / `agent-kit test`) khi MỌI đường
   `✖ tests/…` đỏ có nhãn ở khoá gốc ma trận `"timing_paths": {"tests/…": "<bằng chứng>"}` (bằng chứng rỗng không tính); hoặc trong toàn văn log của suite MỌI khối hỏng lá (`✖/✗ …` + dòng thụt
   sâu hơn; khối có khối con chỉ xét khối con) có dấu hiệu thời gian thực / môi trường (watchdog "quá lớn / quá phức tạp…", `killed after
   …s (deadline)`, `Killed: 9`), hoặc không có khối hỏng nào mà có dòng tổng kết hook contract `ENV-BLOCKED: hook watchdog fired under
   load, no verdict` (và không có Traceback / dòng `FAIL` trần). Không bao giờ nhóm b (#749): lần đầu đỏ thật dù lần chạy lại (FLAKY_RETRY)
   dính watchdog, dòng `FAIL …` trần không dấu hiệu trong khối (trừ dòng tổng đếm cuối file: `FAIL: 2 case(s)`, `FAIL (2)`,
   `FAIL test_x (2)`), log bằng chứng bị cắt đầu. Mọi suite đỏ đều nhóm b ⇒
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
bash .agents/devkit/bin/gate-full-schedule.sh install --repo "$(pwd)"    # 00:00 thứ Hai + thứ Năm (--weekdays 1,4 --hour/--minute để đổi)
bash .agents/devkit/bin/gate-full-schedule.sh status                     # launchctl print rút gọn + summary-latest.md
bash .agents/devkit/bin/gate-full-schedule.sh uninstall                  # status / uninstall: --repo mặc định gốc git của thư mục hiện tại
```

Mỗi repo một LaunchAgent `com.toanmobile.devkit.gate-full.<slug>` (`~/Library/LaunchAgents/<label>.plist`, `bootstrap gui/<uid>`, không sudo):
cài repo B không gỡ lịch repo A. `/usr/bin/nice -n 10 <python3 tuyệt đối> gate_full.py run --repo <repo>`, PATH chứa thư mục của python3/git/gh
lấy lúc cài, `TZ=Asia/Ho_Chi_Minh`, `DEVKIT_GATE_FULL_LOG_DIR=~/Library/Logs/devkit-gate-full/<slug>`, `RunAtLoad` false, stdout/stderr vào
thư mục log đó. `StartCalendarInterval` là mảng `{Weekday, Hour, Minute}` (launchd: 1 = thứ Hai, 0/7 = Chủ nhật). Máy ngủ lúc 00:00 thì launchd chạy bù khi thức dậy; đêm trùng do khoá pid bỏ qua. Label cũ chung `com.toanmobile.devkit.gate-full`
(trước lịch theo repo) script không đụng tới; việc chuyển nó sang label theo repo làm riêng, không phải việc của agent.
