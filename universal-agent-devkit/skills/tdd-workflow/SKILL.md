---
name: tdd-workflow
description: Dùng khi thêm/sửa logic testable, viết regression test hoặc audit test quality cho Target Project / Codebase bằng RED→GREEN an toàn. Bỏ qua config/rendering thuần cần verification khác; không xóa hay revert user work để tạo RED.
---

# TDD Workflow cho Target Project / Codebase

## Contract

Tuân theo `AGENTS.md`, `/fix`, `/plan` và `rules/core-rules.md` §3. Skill này chỉ vận hành
RED→GREEN và chọn evidence; không tự đặt coverage, performance budget hay tỷ lệ test.

## Safety

- Bảo toàn pre-existing code và dirty work; không reset/restore/revert/xóa implementation để tạo RED.
- Bug fix/error correction bắt buộc **PAIRED EXECUTABLE ORACLE**: chạy cùng
  acceptance/scenario/oracle/execution identity RED trước production edit và GREEN sau edit.
- Unit không phù hợp thì dùng integration, instrumented/device hoặc runtime probe fresh; report/log/
  baseline/source cũ chỉ discovery, không thay pre-run và không có waiver.
- Implementation đã tồn tại chỉ được exercise/mutate trong artifact read-only hoặc isolated copy.
  Không có safe pre-run thì `BLOCKED` trước production edit.
- Test behavior/contract quan sát được, không khóa private method hay incidental call order.

## Chọn evidence nhỏ nhất đủ chứng minh

| Outcome | Ưu tiên |
|:---|:---|
| Domain/data transform | Unit test |
| ViewModel state/error | Unit test + coroutine scheduler |
| Flow/cancellation/order | Turbine + virtual time |
| Repository/Room/network boundary | Integration/contract test |
| Compose semantics | Compose UI test |
| Lifecycle/device/file/native | Instrumented/device repro + logcat |
| Performance/large input | Fixture/gate/benchmark hiện có |

Compile, mock-only test hoặc syntax lint không chứng minh runtime/device/security outcome.

## RED → GREEN → REFACTOR

### RED

1. Chốt một observable acceptance/symptom.
2. Viết test nhỏ nhất cho một failure mechanism; variant cùng mechanism dùng parameterized test.
3. Chạy targeted command fresh khi cache có thể che execution.
4. Xác nhận test thực sự chạy và fail tại assertion/symptom, không phải setup/compile error.
5. Bind receipt pre-edit với acceptance/scenario/oracle/execution identity sẽ chạy lại ở GREEN.

### GREEN

Sửa production tối thiểu trong task-owned scope. Chạy lại đúng RED command, kiểm test count/exit code,
rồi chạy regression lân cận theo blast radius thật.

### REFACTOR

Chỉ refactor phần task tạo hoặc bắt buộc cho correctness. Không mở public API/DI chỉ để test; nếu cần
seam, trace blast radius và review architecture tương xứng.

## Test quality

- Ưu tiên real nhẹ/deterministic → fake → stub → mock; mock khi interaction chính là contract.
- Dùng DAMP, tên condition→action→outcome, state/cleanup độc lập.
- Không `Thread.sleep`; dùng virtual time, idling resource hoặc deterministic signal.
- Threshold chỉ lấy từ repo/User; thiếu threshold thì map acceptance/failure mechanism tới evidence.
- **Surviving Mutant Guard (First-run Green):** Với test *mới* viết cho nhánh/feature mới mà chạy lần đầu đã PASS (`First-run Green`), bắt buộc thử làm hỏng dòng production được bảo vệ 1 lần (đảo `>` thành `>=`, đổi hằng số hoặc tạm bỏ guard), chạy test thấy **RED**, rồi hoàn nguyên ngay để thấy **GREEN** (không bao giờ commit bản mutate). Một test chưa từng thấy RED thì chưa chứng minh được nó bắt được bug.
- **Chống Tautology Test:** Cấm viết test chỉ assert trên giá trị trả về của chính mock do test dựng lên, hoặc tính `expected` bằng cách gọi/lặp lại công thức của hàm đang test.
- Mỗi flow kiểm đủ 5 kết quả khi liên quan: phản hồi, trạng thái lưu, lời gọi ra ngoài, thông điệp queue, tín hiệu quan sát. Test không dùng sleep cố định, đồng hồ/mạng thật hay dữ liệu chung; phải đúng khi đảo thứ tự và chạy song song. Chi tiết cho dự án JS/TS/Node (profile web, backend Node; không dùng cho Android, iOS, automotive, game): `references/testing-practices.md`.

## Terminal

Chỉ báo PASS khi command thật đã chạy trong conversation. Dùng verdict của workflow gọi skill:
`/fix` → `CLEAN|VERIFIED_WITH_RESIDUALS|BLOCKED|FAILED|ESCALATE`; `/plan` → `CLEAN|GAPS|BLOCKED`.
Không commit/push hoặc hỏi có muốn commit nếu User chưa yêu cầu rõ.
