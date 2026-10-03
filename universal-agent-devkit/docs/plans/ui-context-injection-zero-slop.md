# Plan — UI Context Injection Zero-Slop

Ngày: 2026-10-03. Đã audit với source thật và thực thi cùng ngày; các điểm lệch so với bản plan này nằm ở mục "Audit và thực thi" cuối file.

Bộ Zero-Slop chưa được gắn vào ngữ cảnh tự động. Prompt chạm UI và profile `android` / `game` / `ios` / `web` vẫn không bị buộc áp dụng chuẩn Impeccable. Phần chữ trong skill và một nửa bảng Compose đã có sẵn. Phần còn lại là lỗ hổng thật.

## Đánh giá hiện trạng

| Hạng mục | Đã có | Còn thiếu |
|---|---|---|
| `enrich_context.py` | `UI_INTERACTION` khi có `nút`, `click`, `bấm`, `giao diện`, `ui`, `màn hình`, `layout`, `button`, `tap`. Kèm debounce, touch 48dp/44px, token `DESIGN.md`. | Không có `screen`, `card`, `panel`, `compose`, `ugui`, `canvas`, `theme`, `palette`, `view`, `widget`, `dialog`, `popup`, `animation`, `font`. Profile app không tự bật. Không inject đoạn ZERO-SLOP. |
| Cùng file, `VISUAL_DESIGN` | Đứng cuối, skill `ui-ux-pro-max` được thêm sau cùng. Game/Unity mới có NFR Anti-Phèn (juice, 60-30-10). | Hai intent không đi cùng nhau. Crash "xoay màn hình" cố ý không nạp skill thiết kế. |
| `compact()` | In NFR cụ thể (bỏ 3 NFR chung cuối) và 5 skill đầu. | Skill thứ 6 bị cắt khỏi dòng hook dù dossier vẫn có. |
| `rules/essentials.md` dòng 172 và `core-rules.md` §6 | Token `DESIGN.md`, touch, feedback, debounce. | Chưa nói Zero-Slop, chưa nêu đuôi file UI. |
| `android-rules.md` §15 | 48dp, font scale, contrast, cấm `Color(0x)` rải. | Chưa cấm card lồng card, icon tile, xám `#808080`, gradient tím-xanh, spacing đều 16dp. |
| `game-rules.md` §3 | Juice 0.92/1.08, 3 canvas, 9-slice, TMP, 48dp. | Chưa cấm panel lồng panel, icon tile, xám trần, spacing đều, nút phẳng, `LiberationSans SDF`, pressed scale 0.95 lún 2–4px. |
| `ui-ux-pro-max/SKILL.md` dòng 222 | Đủ 6 verb và 6 điều cấm. | Nhãn đang là `distill` … `polish`, chưa có dạng `/distill` … `/polish`. |
| `jetpack-compose.csv` dòng 53–57 | Cardocalypse, icon tile, tinted neutral, spacing 4–8 / 24–32, touch 48dp. | Chưa ghi dải nội dung 12–16dp và lệnh cấm gradient tím-xanh. |
| `unity-ugui.csv` (27 dòng) | 9-slice, TMP, touch, juice scale 0.92. | Chưa có hàng Zero-Slop. |

`compact()` giả định 3 NFR cuối là luật chung (chống placeholder, log, nuốt lỗi). Mandate phải được chèn trước 3 dòng đó thì hook mới in ra.

## Cách làm

### 1. `scripts/context/enrich_context.py`

Một cửa duy nhất, sau khi đã có `p_route` (đã gỡ `docker compose`, `thẩm mỹ viện`, `lựa chọn tối ưu`):

Bật khi `mentions(p_route, UI_KEYWORDS)` hoặc profile là `android`, `game`, `ios`, `web`.

Khi bật, mỗi thứ chỉ thêm một lần:

- Intent `UI_INTERACTION` và `VISUAL_DESIGN`.
- Ba NFR tương tác đang có (debounce, touch, token).
- Đúng khối chữ ZERO-SLOP bên dưới (6 gạch đầu dòng).
- `android-real-device-qa` chỉ khi profile là `android` và prompt đã khớp từ khóa UI. Profile một mình không kéo skill máy thật vào prompt thuần database.
- `ui-ux-pro-max` append cuối, sau `qa-visual`.

`UI_KEYWORDS`: `giao diện`, `màn hình`, `screen`, `nút`, `button`, `tap`, `click`, `layout`, `card`, `panel`, `hud`, `compose`, `ugui`, `canvas`, `theme`, `palette`, `widget`, `dialog`, `popup`, `popup túi đồ`, `animation`, `typography`, `font`, cộng `ui` và `bấm` để không thu hẹp luật cũ.

`view` khớp cả từ. `view` dài 4 ký tự nên matcher hiện tại coi là tiền tố và sẽ dính `ViewModel`. Prompt sửa ViewModel thuần không phải task vẽ UI.

`compose` chỉ xét trên `p_route`, nên `docker compose` không thành Jetpack Compose.

Khối `VISUAL_DESIGN` cũ giữ từ khóa thẩm mỹ (`phèn`, `typography`, `hud`, …). Cửa mới gom lại, không tạo intent trùng.

`compact()`: vẫn in tối đa 5 skill. Nếu `ui-ux-pro-max` bị rơi khỏi 5, in 4 skill đầu rồi skill này ở vị trí cuối. Nếu vị trí thứ 4 đang là `qa-visual`, `compose-recomp-audit` hoặc `unity-gc-audit` thì giữ skill đó và thay skill áp chót. `qa-visual` vẫn đứng ngay trước `ui-ux-pro-max`.

Hệ quả cố ý: mọi prompt trên profile app, kể cả câu không nói UI, đều tốn vài dòng ngữ cảnh. Đó là điều khoản "HOẶC khi active profile là android, game, ios, web".

Việc enrich nhìn prompt và profile, không nhìn file sắp sửa. Luật đuôi file nằm ở mục 2, để agent đọc khi đụng file. Lượt này không thêm Stop hook mới.

Khối NFR bắt buộc, nguyên văn:

```text
ZERO-SLOP UI MANDATE (Impeccable Standard):
• Cấm Cardocalypse: Cấm Card lồng Card (Compose/Flutter) và Panel lồng Panel (Unity). Dùng whitespace và subtle divider để làm phẳng layout.
• Cấm Icon Tile trên Heading: Không bọc icon vào ô vuông bo góc màu nhạt đặt trên tiêu đề.
• Cấm Màu xám trần & Gradient tím-xanh: Cấm Color.Gray trần (#808080); bắt buộc dùng Tinted Neutrals (pha 3-5% tông chủ đạo).
• Nhịp điệu Spacing: Cấm 16dp đều chằn chặn; 4-8dp cho item cùng nhóm, 12-16dp nội dung, 24-32dp phân cách section.
• Game UI Tactile Depth (Unity): Cấm nút phẳng lì kiểu web; bắt buộc có độ dày 3D (9-slice bevel), pressed state scale 0.95 lún 2-4px, cấm font mặc định LiberationSans SDF.
• Touch Target: Bắt buộc >= 48dp (Mobile) / >= 44px (Web) kèm immediate visual feedback (Ripple/Scale).
```

### 2. Luật đứng

`rules/essentials.md`, bullet UI trong Engineering musts, và `rules/core-rules.md` §6, thêm cùng một ý:

Mọi sửa file giao diện (`*.kt` Compose, `*.xml` layout, `*.prefab`, `*UI*.cs`, `*.tsx`, `*.vue`, `*.css`) tuân thủ Zero-Slop và token `DESIGN.md`: cấm card/panel lồng nhau, cấm icon tile trên heading, cấm `Color.Gray` / `#808080` và gradient tím-xanh, spacing 4–8 / 12–16 / 24–32, game thì bevel 9-slice, pressed scale 0.95 lún 2–4px, cấm `LiberationSans SDF`, touch ≥ 48dp (mobile) / ≥ 44px (web) kèm ripple hoặc scale.

Sau đó chạy `scripts/governance/context_sync.py` để khối essentials trong `AGENTS.md` khớp file nguồn. Health đối chiếu bản sinh này.

### 3. Data `ui-ux-pro-max`

`SKILL.md`: đổi 6 nhãn hiện có thành `/distill`, `/bolder`, `/quieter`, `/harden`, `/typeset`, `/polish`. Không thêm mục thứ hai.

`jetpack-compose.csv`: sửa hàng spacing 56 để có dải 12–16dp; thêm một hàng cấm gradient tím-xanh. Giữ số hàng cũ.

`unity-ugui.csv`: thêm hàng tiếp theo (từ 28), không đánh lại số 1–27:

- Cấm Panel lồng Panel; dùng khoảng trắng và divider.
- Cấm icon tile trên heading.
- Cấm xám `#808080` và gradient tím-xanh; neutral pha 3–5% tông chính.
- Spacing 4–8 / 12–16 / 24–32, cấm 16 đều.
- Nút có bevel 9-slice; pressed scale 0.95, lún 2–4px; cấm nút phẳng kiểu web.
- Cấm font `LiberationSans SDF`.

Đủ 13 cột, `Status=active`, `Applies To` và `Verified At` cùng kiểu hàng anh em. `validate_data.py` từ chối trùng cột `No`.

### 4. Profile

`profiles/android/rules/android-rules.md` §15 và `profiles/game/rules/game-rules.md` §3: thêm đoạn Zero-Slop ngắn, cùng nội dung mục 2, phần game nhấn bevel / pressed / `LiberationSans SDF`. Không viết lại cả mục juice.

### 5. Test

Sửa `tests/context_memory/test_prompt_context.sh`:

- `app crash khi xoay màn hình` phải ra `ui-ux-pro-max` và chữ `ZERO-SLOP`. Từ `màn hình` nằm trong danh sách mới; assertion cũ (cấm skill thiết kế) sẽ đỏ và được đổi theo spec.
- Prompt đúng chữ `sửa lại nút bấm trong màn hình inventory` ra skill `ui-ux-pro-max` và mandate.
- Profile `android`, `game`, `ios`, `web` với prompt không có từ UI (ví dụ sửa null trong repository) vẫn ra hai intent, skill và mandate.
- Giữ nguyên các ca âm: `ui` trong `build`, `hiệu ứng phụ`, `docker compose`, `thẩm mỹ viện`, `lựa chọn tối ưu`.
- `sửa lỗi hud bị vỡ layout`: `qa-visual` ngay trước `ui-ux-pro-max` trong 5 skill.
- Game + GC vẫn thấy `unity-gc-audit`. Android + recomposition vẫn thấy `compose-recomp-audit`.
- `ViewModel` không kéo `ui-ux-pro-max` trên profile `backend`.

Oracle: chạy suite này trước khi sửa `enrich_context.py` để thấy đỏ ở ca màn hình và ca inventory, rồi xanh sau khi sửa.

### 6. Nghiệm thu và git

Từ gốc `agent-workbench`:

```bash
python3 universal-agent-devkit/scripts/context/enrich_context.py --compact "sửa lại nút bấm trong màn hình inventory"
bash universal-agent-devkit/bin/agent-kit health -t .
python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --auto-approve-tests
```

Profile repo này là `backend`, nên lệnh compact kiểm đường từ khóa, không kiểm đường profile. Ca profile nằm trong suite.

Health 100/100 là điểm nối dây, không phải điểm hoàn thiện sản phẩm.

Ảnh: không cần. Chỉ đụng kit, profile backend, không có màn hình app.

Commit đúng path kit, subject tiếng Anh, trailer `No-Guard: host wiring, not a checklist bug`. Không stage `.agents/CHECKLIST.md`, `regression_status.json`, `instincts-index.md`. Không đụng checkout Geely, Office Reader, Goods đang khóa, không push `devkit/host-hooks`. Push `main` khi `origin/main` vẫn là cha của HEAD.

## Ngoài phạm vi

Không thêm hook chặn theo đuôi file. Không đổi `bin/install.sh`, proof capture, hay bridge Cursor/Gemini/Codex. Không gọi Antigravity review: spec đã chốt, diff là luật và data, không đổi kiến trúc runtime.

## Audit và thực thi (2026-10-03)

Mỗi khẳng định "hiện trạng" của plan được đối chiếu với source thật trước khi sửa; đã đúng gần hết. Phần dưới là những chỗ plan thiếu hoặc mâu thuẫn với source, và cách đã xử lý. Thứ tự thực thi: test đỏ trước (31 ca đỏ ở `test_prompt_context.sh`, 2 ở `test_prompt_dedupe.sh`), sửa mã trên bản sao rồi cài nguyên tử vào `enrich_context.py` (file này là hook đang chạy của mọi phiên: INSTINCT-012/016), xanh sau đó.

| # | Plan | Source thật | Xử lý |
|---|---|---|---|
| 1 | Mandate là một NFR nhiều dòng, chèn trước 3 NFR chung | `dedupe_session` bỏ lặp **từng dòng** (`ONCE_PER_SESSION`). Mandate dính vào dòng `Yêu cầu ngầm định` sẽ bị gửi lại mỗi khi tập NFR đổi; gạch đầu dòng đứng riêng không có tiền tố sẽ bị gửi lại mãi trong khi dòng tiêu đề bị bỏ (gạch mồ côi) | Giữ nguyên văn nhưng `compact()` in thành khối riêng (tiêu đề + 6 gạch); `ONCE_PER_SESSION` thêm `ZERO-SLOP UI MANDATE` và `• `. Mandate gửi một lần mỗi phiên, sau compaction gửi lại. Test: `hooks/tests/test_prompt_dedupe.sh` |
| 2 | Profile app bật UI cho mọi prompt | `INTENT_TERMS["UI_INTERACTION"]` (click, debounce, 48dp) cộng vào từ khóa khớp bẫy cho mọi intent, và `shown_refs` hạ ngưỡng 3→2 khi có intent. Bẫy 002/005 sẽ chiếm 2 trong 4 slot của prompt không nói UI, rồi dedupe giấu chúng | Intent chỉ do profile bật vào `dossier["profile_intents"]`: không nạp `INTENT_TERMS`, không hạ ngưỡng. Test: bẫy F48 vs F07 trên profile android, `shown_refs` |
| 3 | `view` khớp cả từ (nhưng không có trong danh sách), `card`/`compose` như từ khóa thường | `mentions()` coi từ ≥4 ký tự là tiền tố: `card` bắt `cardinality`/`cardholder`, `compose` bắt `composer` (PHP), `view` bắt `ViewModel` | Các từ mơ hồ (`view`, `card`, `compose`, và sau review `screen`, `panel`, `dialog`, `theme`, `font`) đi qua regex nguyên từ `UI_WHOLE_WORDS`; `NON_TECHNICAL_PHRASES` gỡ thêm nghĩa backend (`compose.yaml`, `sql view`, `Django views`, `Grafana panel`, `credit card`, `card number`, `dialog state`…); bỏ `popup túi đồ` (thừa vì đã có `popup`). Còn lại, ghi `ponytail:`: class CamelCase (`ScreenState`) ngoài profile app, `layout`/`click` như ở HEAD |
| 4 | `compact()`: "vị trí thứ 4 … thay skill áp chót" | Tự mâu thuẫn nếu đếm từ 1: vị trí 4 chính là áp chót | Lấy 5 skill đầu; nếu `ui-ux-pro-max` bị cắt thì nó thế chỗ skill cuối cùng không thuộc {`qa-visual`, `compose-recomp-audit`, `unity-gc-audit`}. Ca `Compose UI bị lag`, game + GC và hud trên android ghim hành vi này |
| 5 | `VISUAL_DESIGN` luôn bật theo cửa mới | Bốn NFR juice của game gắn với khối `VISUAL_DESIGN`: bật theo profile thì mọi prompt game mang thêm 4 dòng dài | Bốn dòng đó giữ theo từ khóa thẩm mỹ cũ |
| 6 | Data: sửa hàng 56, thêm một hàng | `validate_data.py` đã đỏ trước khi sửa: hàng 55 (High) trỏ `m3.material.io`, validator chỉ nhận `developer.android.com`; `catalog-summary.json` `stackGuidelines` lệch (đỏ cả ở HEAD). Plan không nhắc `catalog-summary.json` | Hàng 55 → trang Material 3 của developer.android.com (đã kiểm HTTP 200); `stackGuidelines` = 1310 (số hàng thật). `validate_data.py` exit 0. Test `test_threshold_exemption_is_declared_per_stack_not_by_row_count` đỏ sẵn ở HEAD, không liên quan, không đụng |
| 7 | Đuôi file: `*.kt *.xml *.prefab *UI*.cs *.tsx *.vue *.css` | Gate có `UI_EXTENSIONS` = `.kt .java .tsx .jsx .dart .vue .swift .xml`; profile `ios` thuộc phạm vi mà không có `.swift` | Luật đứng dùng hợp của hai danh sách |
| 8 | Commit "đúng path kit" | `context_sync.py` ghi lại khối essentials trong `AGENTS.md` gốc (file tracked); health đối chiếu nó | Commit cả `AGENTS.md` gốc |
| 9 | Chỉ đổi assertion `app crash khi xoay màn hình` | Hai test khác hết đúng theo spec mà gate của plan không chạy (chúng không nêu tên `enrich_context`): `test_prompt_dedupe.sh` ca "partly new" (prompt không có "màn hình" nay khác dòng skill), `hook_contract_test.sh` "chit-chat adds nothing" (fixture profile `web`) | Ca 1: prompt thứ ba thêm "màn hình" và từ khóa mạng. Ca 2: "im lặng" chỉ còn cho profile không phải app; profile app có ca riêng (đúng điều khoản "Hệ quả cố ý") |
| 10 | Nhãn `/distill` … `/polish` | Không có slash command nào được cài | Tiêu đề mục nói rõ đó là từ chỉ đạo viết trong prompt |

### Review ngữ cảnh sạch (`principal-code-reviewer`, sau bản đầu)

Không blocker; 3 should-fix, 5 nit, đều có số đo. Xử lý:

| # | Phát hiện | Xử lý |
|---|---|---|
| 1 | `hooks/agent_bridge.sh` nhánh `prompt` không chuyển `session_id` nên Gemini/Codex/Cursor không dedupe: mandate (~1,1 KB) lặp ở mọi prompt trên profile app | Ban đầu để lại vì plan loại trừ bridge; sửa sau theo yêu cầu (04/10): nhánh `prompt` chuyển `session_id` / `conversation_id` như nhánh `stop`, test `test_agent_bridge.sh` (3 ca đỏ → xanh) |
| 2 | Từ UI mới bắt nhầm từ vựng backend (`sql view`, `Django views`, `compose.yaml`, `compose up`, `Grafana panel`, `screening`, `Dialogflow`, `theme_id`, `card` trong log thanh toán); replay prompt thật: cửa UI mở 3 → 5 lần | Sửa: 5 từ prefix thành nguyên từ, thêm cụm vào `NON_TECHNICAL_PHRASES`, 11 ca âm mới. Replay lại 319 prompt: HEAD 4, bản đầu 8, bản sửa 7; 3 lần tăng đều là văn bản dài (2 bản tóm tắt phiên tự sinh, 1 prompt vai trò dán vào) |
| 3 | 0.92 (squash lúc chạm) và 0.95 (pressed của mandate) cùng được tiêm cho một sự kiện | Giữ số của plan. Bản đầu gọi 0.92 là tween thoáng qua: sai, vì uGUI #22 giữ squash tới lúc nhả. Nay: tween squash kết thúc ở tư thế Pressed 0.95 + lún, trả lại khi nhả; sửa graphic con của nút (LayoutGroup điều khiển vị trí nút); ghi ở `game-rules.md`, uGUI #32 và dòng NFR juice. **Cần chủ quy chuẩn xác nhận**: hàng #22 và #3 (có sẵn) vẫn mô tả squash giữ tới lúc nhả |
| 4 | Prompt chỉ có từ thẩm mỹ (`bảng màu`, `phèn`) được skill nhưng không có mandate, trong khi `palette` mở cửa | Từ thẩm mỹ cũng mở cửa; điều kiện `VISUAL_DESIGN` rút gọn thành `ui_door` |
| 5 | `/distill …` ở đầu prompt bị hook bỏ qua (prompt bắt đầu bằng `/`) | Tiêu đề mục trong `SKILL.md` dặn viết giữa câu |
| 6 | `SKILL.md` ghi 3 trạng thái nút, thiếu Disabled | Sửa thành 4 trạng thái |
| 7 | Phạm vi cấm gradient tím-xanh lệch giữa mandate (tuyệt đối, nguyên văn plan) và data (chỉ bản template); `styles.csv` (Aurora UI, Vaporwave) lại gợi ý gradient xanh→tím | **Để nguyên, cần người quyết**: hai bên mâu thuẫn về chính sách, không phải lỗi mã |
| 8 | Test: ca game+GC không bắt được đột biến "thay skill cuối"; ca dedupe mandate chưa có trường hợp chỉ-do-profile; ca âm pass giả nếu helper crash | Thêm ca dedupe chỉ-do-profile và dấu `HELPER-CRASH` cho ca âm. Ca game+GC giữ nguyên: trên profile game `unity-gc-audit` luôn là skill thứ 4 nên không có input nào phân biệt được |

### Review delta của `756c2e9` (cùng reviewer, sau bản sửa vòng 1)

Bản sửa vòng 1 gây 2 hồi quy; reviewer bắt cả hai bằng reproducer, đã sửa ở commit sau:

| # | Phát hiện | Xử lý |
|---|---|---|
| 1 | Từ thẩm mỹ mở cửa nên `UI_INTERACTION` thành intent thật và nạp lại bẫy click/debounce/48dp (F07 đứng đầu ở prompt `vfx`, `shading`, `đồ họa`), trái đúng luật INSTINCT-026 | Tách `ui_terms` (từ UI tương tác) khỏi `ui_words` (cộng từ thẩm mỹ): intent UI chỉ nạp bẫy khi có `ui_terms`; prompt thẩm mỹ vẫn có mandate. Ngưỡng bẫy yếu giữ như HEAD nhờ `VISUAL_DESIGN` |
| 2 | `compose(?:\.ya?ml\| up)` không có ranh giới từ nên ăn `recompose up to`, `Compose update/upgrade`: mất `compose-recomp-audit` và `PERFORMANCE` (hồi quy so với HEAD) | `(?<!\w)compose(?:\.ya?ml\|\s+up)(?!\w)` |
| 3 | Câu "0.92 chỉ là tween" sai so với uGUI #22 (squash giữ tới lúc nhả); làm theo cả hai thì tư thế giữ ra (1.05, 0.92), không bao giờ 0.95; sink bằng `anchoredPosition` của nút bị LayoutGroup ghi đè | Xem hàng 3 của bảng trên: đổi câu chữ, #32 áp lên graphic con. **Cần chủ quy chuẩn xác nhận** |
| 4 | Test không bắt hai hồi quy đầu | Thêm 12 ca (4 compose/PERFORMANCE, 8 từ thẩm mỹ không kéo F07), mutation J và K |
| 5 | Lệnh kiểm tra của INSTINCT-026 kết thúc bằng `\| tail -2` nên nuốt exit code | Bỏ `\| tail -2` |
| 6 | Header `hooks/prompt_context.sh` vẫn nói chit-chat không tốn context và chỉ kể 3 loại dòng dedupe | Sửa comment (4 dòng) qua cài nguyên tử: ghi ngoại lệ profile app và bridge |

Không lỗi theo reviewer: regex (mọi nhánh có nhóm, không backtracking: 1,8 MB ≤ 0,07 s), thứ tự intent/NFR/skill khi `aesthetic` lên trước (với prompt thẩm mỹ `UI_INTERACTION` chen ngay sau `BUG_FIX`; android + từ thẩm mỹ thêm `android-real-device-qa`), bash 3.2, CSV 13 cột, `validate_data.py`.

Mutation check (12 đột biến: bỏ loại intent-profile khỏi bẫy hoặc khỏi ngưỡng, mandate dính dòng NFR, bỏ tiền tố `ONCE_PER_SESSION`, skill line 5 đầu thuần, profile kéo `android-real-device-qa`, từ nguyên từ thành prefix, bỏ cụm backend, từ thẩm mỹ không mở cửa, NFR juice theo profile, từ thẩm mỹ nạp lại bẫy UI, `compose up` không ranh giới): cả 12 đều làm ít nhất một ca đỏ.

Kết quả đo (bản cuối): `test_prompt_context.sh` 118/118 (cả bash 3.2), `test_prompt_dedupe.sh` 30/30, `hook_contract_test.sh` 687 ok / 0 deviating, `validate_data.py` exit 0, health 100/100; replay 319 prompt đã gõ: cửa UI mở 4 lần ở HEAD, 7 lần nay (3 lần tăng là văn bản dài). Còn đỏ sẵn ở HEAD, không thuộc thay đổi này: `contract_facts_test.sh` F2 (`user_project_bridge.sh` thiếu header OPT-IN HELPER, từ commit `18f4591`) và `test_threshold_exemption…` nói trên.

Điểm cần biết: `tests/run_impacted.sh` chọn test theo tên file đổi; `hook_contract_test.sh` chỉ nêu `prompt_context` nên một lần sửa `enrich_context.py` thuần không kéo nó vào gate. Chưa sửa (ngoài phạm vi); nếu sửa tiếp `enrich_context.py`, chạy tay `bash universal-agent-devkit/hooks/tests/hook_contract_test.sh`.
