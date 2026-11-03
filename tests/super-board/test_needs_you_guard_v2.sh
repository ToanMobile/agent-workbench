#!/usr/bin/env bash
# Rào chắn needs-you v2 (cờ needs_you_guard_v2, mặc định tắt).
# Dữ liệu: nguyên văn các lời `🙋 Cần bạn:` thật trên 6 board (cache gh 03/11/2026) mà bản v1 cho lọt.
#   R = việc nhắm đúng thứ agent sở hữu (AUTO-APPROVE/duyệt test đã sửa, AC hay nội dung thẻ #N, đóng thẻ đã có PR, cây dirty, --full + merge gate)
#   H = mọi lời còn lại: việc của người (xe, khoá/secret, Play Console, PII, danh tính) và lời mở đầu bằng "quyết định / chọn hướng" (thuộc ai tuỳ việc được quyết)
#   (WB#124 nối hai chữ drop và table bằng gạch dưới: merge_policy coi cụm có dấu cách là đổi schema; câu thuộc H nên kết quả không đổi.)
# Cờ tắt: mọi câu được nhận như v1. Cờ bật: R, M exit 64; H exit 0. Cờ đọc từ env SB_NEEDS_YOU_GUARD_V2
# hoặc <checkout chính>/.agents/local/flags.json.
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR  # cờ đọc qua git: không để biến git của gate trỏ vào repo thật

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NEEDS_YOU="$REPO_ROOT/.claude/bin/super-board-needs-you.py"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"labels/needs-you"* ]]; then
  echo '{"color":"D93F0B","description":"🙋 Cần người thực hiện bước chỉ con người được làm"}'
elif [[ "$*" == *"/comments"* ]]; then
  echo '[]'
else
  echo '{"labels":[],"body":""}'
fi
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
# Chạy trong một repo git tạm không có flags.json: cờ thật của checkout chính không lọt vào test.
mkdir -p "$TMP/repo"
git -C "$TMP/repo" init -q

mark_rc() {   # mark_rc <action> -> exit code của mark --dry-run, chạy trong $TMP/repo
  local rc
  set +e
  (cd "$TMP/repo" && python3 "$NEEDS_YOU" mark --repo ToanMobile/agent-workbench --issue 1 --action "$1" --dry-run >/dev/null 2>&1)
  rc=$?
  set -e
  echo "$rc"
}

FIXTURE="$TMP/fixture.tsv"
cat > "$FIXTURE" <<'NY_FIXTURE_END'
H	agent-workbench#747	chọn đường cho PR #742: (a) cấu hình merge_policy.machine_gate.verify_commands + review đủ 4 bên (Grok + OCR), hoặc (b) duyệt sửa bộ phân loại để fixture test của chính nó không kích hoạt machine gate
H	agent-workbench#657	Đăng [decision] coi AC4 (--full 00:00) là kiểm sau merge cho PR #673, hoặc tách AC4 sang thẻ riêng
H	agent-workbench#632	chọn hướng A (bot GitHub) hoặc B (khoá ký Keychain) và cấp danh tính ngoài vùng agent ghi được
R	agent-workbench#601	gõ tay AUTO-APPROVE cho tests/super-board/test_runner_preflight_swept.sh (sha256 b210511c…) trên PR #606
R	agent-workbench#570	Gõ tay trên PR #585 dòng duyệt cho 3 test merge-gate đã sửa (đường dẫn + sha256 ở comment chặn)
R	agent-workbench#531	duyệt chéo diff test_runner_merge_queue.sh bằng audit Antigravity, hoặc thu hẹp AC1
H	agent-workbench#529	xem PR #551 (merge gate gate-exit-8) rồi tự merge, hoặc duyệt theo comment 🙋 trên thẻ
H	agent-workbench#525	vá copy_file trong repo gói super-board (~/.local/share/super-board/install.sh) hoặc cho builder quyền làm ở đó
R	agent-workbench#499	Cung cấp log merge gate dùng lại biên nhận cây ở GeelyEx2, Humans-vs.-UFOs, Goods (khi PR thật kế tiếp merge) hoặc chạy --full + merge gate thủ công
H	agent-workbench#337	Chọn nguồn >=100 prompt thật (transcript nào) và đồng ý mask PII
H	agent-workbench#321	review PR #342 và merge, hoặc comment done để duyệt
H	agent-workbench#248	quyết định: mở card riêng sửa test_gate_stop_reuse_race.sh (đỏ ngẫu nhiên theo tải, cũng đỏ trên main) hoặc chấp nhận PR #276 khi gate xanh
H	agent-workbench#240	Quyết định cách kiểm AC1/AC2 cho PR #279
H	agent-workbench#231	Chọn nguồn 100 prompt thật (transcript phiên nào) để đo parallel_split
R	agent-workbench#201	Phiên chủ main dọn cây dirty và khôi phục checklist; sửa thẻ 201 chỉ còn phần có diff, bỏ 151 152 180
R	agent-workbench#200	Sửa AC thẻ #200 (5 nhánh đều có PR mở #182 #164 #174 #160 #176) hoặc chỉ định PR nào bị bỏ
R	agent-workbench#184	viết lại thẻ #184: chạy lại lane build trong worktree, lưu tên hook + lệnh + text chặn vào thẻ cùng AC mới
H	agent-workbench#180	Đóng #180 vì cả 5 repo đã đồng bộ (context_sync --check thoát 0), không còn gì để build
H	agent-workbench#124	Review PR #174 (merge_policy: từ khoá drop_table trong test)
H	agent-workbench#123	Review PR #164
R	agent-workbench#81	Đóng #81 vì đã sửa ở PR #113, hoặc đưa kịch bản còn tái hiện
H	agent-workbench#35	Chốt Goal + AC cho #35: tự merge vào trunk rồi xoá worktree sau Done, hay chỉ dọn worktree sau merge gate; xử lý ca dirty/conflict. Nếu PR #65 đã đủ thì đóng thẻ.
H	agent-workbench#28	chọn hướng rút essentials hoặc chuyển luật riêng từng repo, tách card theo repo
H	geelyex2#134	chủ xe thử 2 lượt trên màn xe (A: video đang phát ở trang xem mở rộng rồi bấm Home; B: thu miniplayer rồi bấm Home) và chụp YouTube > Cài đặt > Chung > Hình trong hình, hoặc bật ADB Wi-Fi của xe để agent tự đo
H	geelyex2#42	Thu hồi token bot Telegram cũ ở @BotFather (viết lại lịch sử git chỉ khi đồng ý force-push); dán supabase/schema.sql vào SQL Editor; chọn phương án auth/billing và quyết câu trần 'đóng ứng dụng' từ #110; lấy số đo vhal_binder_time
H	geelyex2#39	Đăng nhập VietMap trên xe rồi đo dẫn đường ≥10 lượt (AC 1)
H	geelyex2#38	Trên xe thật bản 1.3.0 (online qua adb): chia đôi Maps + YouTube ≥3 lượt để ghi timeline am stack list lúc lỗi; báo giờ lúc thấy app biến mất (an_ca_hai)
H	geelyex2#35	Sau khi #111 dán số đếm: quyết có sửa isWakeGap và thiết kế ping phone→xe riêng; đo lặp ≥3 lượt trên xe cho relay 4G
H	geelyex2#30	Chọn nguyên văn câu đáp điều hoà từ đề xuất ở #112; đo công tắc camera 540 trên xe rồi chốt câu gợi ý (hoặc bỏ); sửa AC bỏ 2 câu đã xong; duyệt phát hành gói giọng trước APK
H	geelyex2#29	Trên xe thật: đo SelfCompile (SELinux, thời gian dex2oat), nói ≥3 lượt PTT xem rụng đầu câu, nói các ca VOICE-1014/1016, NHÀ RIÊNG; báo số lần nói đợt 21:04-21:08 10/10
H	geelyex2#28	chủ xe chốt: (1) thêm clip giọng thật cho câu báo 'chưa có toạ độ' và nghe duyệt clip trên xe thật, hay (2) giữ giọng 'Đã mở' và sửa dòng AC 'Xe đọc đúng câu thông báo' thành 'popup đọc đúng câu' (đã đạt ở PR #77)
H	geelyex2#27	Trên xe thật bản 1.3.1: đo ≥3 lượt Waze tự bấm OK, overlay hoãn khi xe chạy, hoàn tác HVAC (ECO, sấy kính, sấy gương); tắt cờ debug.geely.wavtest sau đo
H	geelyex2#23	Chuẩn bị thiết bị ELM327 BLE và cho xe online để đo khả thi DashCam AVM và OBD2; sau khi có kết luận, comment quyết làm hay bỏ
H	geelyex2#22	Trên xe thật (online qua adb): lấy log 'InputFilter THẬT active' và đọc HEADLIGHTS_SWITCH 0x214020a3 khi bật rồi tắt đèn pha
H	geelyex2#21	Trên xe: so 0x2140a6f8 với kWh/100 km trên đồng hồ; xác nhận dung lượng pin (đề xuất ở #116); nhập giá điện, giá xăng, mức tiêu hao xe xăng
H	geelyex2#20	Trên xe thật: giữ 3 giây từng phím vô-lăng (PTT, Next, Prev, Vol), ghi phím nào mở nghe lệnh rồi comment kết quả lên issue
H	geelyex2#15	Đo Bước 0 trên xe (plan-fix-9-viec-24-09-2026.md §0), điền bảng và ghi GO/NO-GO VhalEventHub; Phần B bão refresh đã tách sang #113
H	geelyex2#13	Ngồi xe và lái một buổi đo theo checklist bảng A trong plan.html (đỗ, lăn bánh, ngủ sâu, ODO 20/40/60 km/h), ghi đạt/hỏng từng dòng; tắt cờ debug.geely.wavtest
H	geelyex2#9	Cho xe online (192.168.100.202:5555, sáng máy, số P) và cho phép quay bằng bản debug; xin đồng ý giọng người dùng hoặc thu giọng chủ xe trước khi đăng
H	geelyex2#5	Bật xe nối adb ghim serial; ghi âm MIC thô ~5 phút lúc đỗ, lúc chạy, lúc bật xi-nhan kèm 'Hi Geely' ~20 lần; dò VHAL xi-nhan; nghe 9 clip mơ hồ chốt nhãn (trường engine ở #114)
H	geelyex2#2	Ngồi xe hỏi thời tiết/ETA ≥3 lượt, nghe giọng đọc tên nơi, thử mất 4G; đo thanh PIP YouTube/SmartTube và thẻ phân bổ năng lượng; duyệt phát hành gói clip v11 cùng APK (test + nút Bài trước ở #115)
H	goods-triple-shelf-match-3d#15	Đưa key/app-id AdMob hoặc MAX + file cấu hình Firebase (không commit), chọn nhà mạng quảng cáo, rồi chia thẻ thành 4 lát dọc dưới 400 dòng
H	goods-triple-shelf-match-3d#14	Xác nhận keystore/key_store_goods.jks là upload key cho Play Console (hoặc tạo mới); chốt tên launcher + version, tạo app trên Play Console, đưa URL chính sách thật vào legal_links.json
H	goods-triple-shelf-match-3d#13	Nghe game liên tục 15 phút, ghi chỗ chói tai/chồng tiếng/nhạc lặp vào issue; hoặc comment chấp nhận số đo thay cho nghe
H	goods-triple-shelf-match-3d#12	Tìm 5 người chơi thật, cho chơi APK từ HEAD theo production/qa/playtest-2026-10.md, ghi chép; chốt HARD-5, FUN-5, hệ số ngân sách, độ khó màn mục tiêu, bàn tay màn 6
H	humans-vs-ufos#20	Quay video 30 s và đo frame time trên máy Android tầm trung, đính vào PR #72
H	idle-plaza-3d#10	main đã có (PR #16, profile game); 3 AC còn lại nói về WebGL/Three.js (npm test, provider web 844x390, luật 01-webgl-threejs) trong khi repo đang chạy Unity (unity-batch.sh): chọn bỏ 3 AC WebGL hay giữ hướng WebGL — đổi phạm vi là
H	officereader#154	Đổi Gemini API key (khóa cũ lộ 18/10), supabase secrets set GEMINI_API_KEY; sau đó db push, deploy ai-assist, thử BYOK trên máy thật, làm Play Console
H	officereader#102	Tạo 3 product ID Play Billing trên Play Console (1 tháng, 1 năm, trọn đời) và ghi tên ID vào thẻ #102
H	officereader#97	Quyết định AC2 "có thể làm phẳng" đã đạt với thiết kế ghi chữ vào nội dung trang chưa; đạt thì đóng #97 là trùng (834229ccf, dfe18b959), chưa thì viết AC mới
H	officereader#89	Deploy ai-assist trên Supabase; thử BYOK bằng khóa Gemini thật trên máy thật; Play Console: khai báo MANAGE_EXTERNAL_STORAGE và tạo 3 product ID
H	officereader#76	Chạy supabase login, supabase link --project-ref <ref>, rồi supabase db pull vào supabase/migrations; soát không có secret
NY_FIXTURE_END

n=0
while IFS=$'\t' read -r cls key act; do
  [ -n "$cls" ] || continue
  n=$((n + 1))
  off="$(SB_NEEDS_YOU_GUARD_V2=0 mark_rc "$act")"
  [ "$off" = 0 ] && pass || fail "T1 cờ tắt phải nhận như v1 (exit $off): $key"
  on="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  case "$cls" in
    R|M) [ "$on" = 64 ] && pass || fail "T2 cờ bật phải từ chối việc agent (exit $on, cần 64): $key: ${act:0:80}" ;;
    H) [ "$on" = 0 ] && pass || fail "T3 cờ bật chặn nhầm việc của người (exit $on, cần 0): $key: ${act:0:80}" ;;
  esac
done < "$FIXTURE"
[ "$n" -eq 52 ] && pass || fail "fixture phải có 52 câu, có $n"

# T3a: câu human-gate mà super-board-merge-queue.sh (gate-exit-7/8) tự gắn phải luôn được nhận: chặn nó là làm yếu human-gate.
rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "xem PR #999 (merge gate gate-exit-8) rồi tự merge, hoặc duyệt theo comment 🙋 trên thẻ")"
[ "$rc" = 0 ] && pass || fail "T3a câu human-gate của merge-queue bị chặn (exit $rc)"
grep -q 'xem PR #${p} (merge gate ${res}) rồi tự merge, hoặc duyệt theo comment 🙋 trên thẻ' "$REPO_ROOT/.claude/bin/super-board-merge-queue.sh" \
  && pass || fail "T3a câu --action của merge-queue đã đổi: cập nhật T3a"

# T2b: phần trên xe của câu trộn geelyex2#30, đứng riêng, vẫn là việc của người.
rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "Chọn nguyên văn câu đáp điều hoà từ đề xuất ở #112; đo công tắc camera 540 trên xe rồi chốt câu gợi ý (hoặc bỏ); duyệt phát hành gói giọng trước APK")"
[ "$rc" = 0 ] && pass || fail "T2b phần trên xe của geelyex2#30 phải được nhận (exit $rc)"

# T3b: danh sách việc của người trong test_needs_you_autonomous_guard.sh vẫn được nhận khi cờ bật.
for act in \
  "Đổi Gemini API key (khóa cũ lộ 18/10), supabase secrets set GEMINI_API_KEY; làm Play Console" \
  "Tạo 3 product ID Play Billing trên Play Console (1 tháng, 1 năm, trọn đời)" \
  "Tìm 5 người chơi thật, cho chơi APK từ HEAD theo production/qa/playtest-2026-10.md" \
  "Tạo/xác nhận tài khoản Google Play và Apple Developer, nộp hồ sơ phát hành VN theo NĐ 147/2024" \
  "Nâng giới hạn chi tiêu (spending limit) tài khoản OpenAI trong trang billing" \
  "Raise the Lambda timeout in the AWS console" \
  "Xác nhận bằng chứng chuyển khoản của khách hàng" \
  "Nâng giới hạn kết nối Postgres production để test suite tải chạy được"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "T3b cờ bật chặn nhầm (exit $rc): $act"
done

# T2c: cờ bật không được nới v1 — câu v1 đang từ chối vẫn bị từ chối dù có từ người của v2 (phát hành, trên xe, PII).
for act in \
  "Chạy lại gate --full trước khi phát hành" \
  "Thử PR #12 trên máy ảo trước khi phát hành bản 1.4" \
  "Chạy lại gate --full trên xe giả lập AAOS" \
  "Gỡ worktree .claude/worktrees/issue-9-build chứa log PII"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=0 mark_rc "$act")"
  [ "$rc" = 64 ] && pass || fail "T2c v1 phải từ chối (exit $rc): $act"
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 64 ] && pass || fail "T2c cờ bật nới v1 (exit $rc, cần 64): $act"
done

# T3c: việc trong danh sách phải hỏi người (force-push, deploy production, thanh toán, đăng nhập) vẫn được nhận khi cờ bật.
for act in \
  "Quyết định có force-push để xoá token lộ khỏi lịch sử không" \
  "Quyết định có deploy ai-assist lên production không" \
  "Quyết định có bật thanh toán trả phí cho OpenAI không" \
  "Gõ tay mã thiết bị cho gh auth login trên máy build" \
  "Quyết định có xoá dữ liệu người dùng thật trên LIVE không" \
  "Quyết định có xoay secret GEMINI đang dùng không" \
  "Quyết định cấp quyền camera và location cho app không" \
  "Quyết định có merge PR #12 phá API công khai không" \
  "Chọn hướng: release bản 2.0 lên App Store hay đợi" \
  "Quyết định có rewrite history để xoá token lộ không" \
  "Gõ tay mã OTP 2FA trên điện thoại chủ repo" \
  "Gõ tay mật khẩu sudo trên máy build" \
  "Quyết định có ký hợp đồng NDA với đối tác không" \
  "Quyết định có chi 200 USD/tháng cho Sentry không" \
  "Quyết định có chấp nhận điều khoản dịch vụ OpenAI không" \
  "Đo frame time trên máy Android của tester ngoài" \
  "Quyết định AC2: có xoay secret Supabase service_role đang dùng không" \
  "Quyết định AC3: có xoá dữ liệu người dùng thật trên LIVE không" \
  "Chọn hướng rút app khỏi App Store hay giữ" \
  "Chọn đường cho PR #12: merge bản phá API công khai v1 hay giữ tương thích" \
  "Chọn hướng tách lịch sử git: rewrite history xoá file khách" \
  "Chốt Goal ngân sách quảng cáo tháng 12 (chi 500 USD)" \
  "Chọn hướng sửa quyền camera và location trong App Store Connect" \
  "Quyết định AC1: có gửi mã OTP thật tới số điện thoại khách không" \
  "Chọn hướng sửa hợp đồng NDA với đối tác trước khi ký" \
  "Dọn cây thư mục upload của khách trên server LIVE" \
  "Sửa AC của hợp đồng NDA với đối tác" \
  "Đăng [decision] chấp nhận điều khoản dịch vụ của OpenAI" \
  "Quay video 30 s và đo frame time trên máy Android tầm trung của tester"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "T3c cờ bật chặn nhầm việc phải hỏi người (exit $rc): $act"
done

# T4: cờ trong flags.json của checkout chính (không env) bật v2; thiếu file hoặc JSON hỏng là tắt.
probe="Sửa AC thẻ #200 cho khớp 5 PR đang mở"
mkdir -p "$TMP/repo/.agents/local"
rc="$(env -u SB_NEEDS_YOU_GUARD_V2 bash -c "$(declare -f mark_rc); TMP='$TMP'; NEEDS_YOU='$NEEDS_YOU'; mark_rc '$probe'")"
[ "$rc" = 0 ] && pass || fail "T4 không có flags.json phải là tắt (exit $rc)"
echo '{"needs_you_guard_v2": true}' > "$TMP/repo/.agents/local/flags.json"
rc="$(env -u SB_NEEDS_YOU_GUARD_V2 bash -c "$(declare -f mark_rc); TMP='$TMP'; NEEDS_YOU='$NEEDS_YOU'; mark_rc '$probe'")"
[ "$rc" = 64 ] && pass || fail "T4 flags.json bật phải từ chối (exit $rc, cần 64)"
# worktree của thẻ đọc cờ của checkout chính
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP/repo" worktree add -q "$TMP/wt" >/dev/null 2>&1
rc="$(set +e; cd "$TMP/wt" && env -u SB_NEEDS_YOU_GUARD_V2 python3 "$NEEDS_YOU" mark --repo ToanMobile/agent-workbench --issue 1 --action "$probe" --dry-run >/dev/null 2>&1; echo $?)"
[ "$rc" = 64 ] && pass || fail "T4 worktree phải dùng cờ của checkout chính (exit $rc, cần 64)"
echo '{"needs_you_guard_v2": tru' > "$TMP/repo/.agents/local/flags.json"
rc="$(env -u SB_NEEDS_YOU_GUARD_V2 bash -c "$(declare -f mark_rc); TMP='$TMP'; NEEDS_YOU='$NEEDS_YOU'; mark_rc '$probe'")"
[ "$rc" = 0 ] && pass || fail "T4 flags.json hỏng phải là tắt (exit $rc)"

echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
