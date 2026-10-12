# Kiến trúc Android — android/architecture-samples (chỉ cho profile `android`)

Phạm vi: chỉ đọc khi profile đang hoạt động là `android`. Profile game, automotive, web, backend, ios không dùng file này.
Nguồn đã đọc 2026-10-12: README, cây thư mục và mã trên nhánh `main` của `android/architecture-samples`. Sample tự nhận không phải template hay app production: áp dụng theo quy mô (core §4 Lazy Senior). Rule ngắn: `profiles/android/rules/android-rules.md` §16.

- Hai tầng: presentation và data; không có tầng domain trên `main`. Một module `app` + `shared-test` (fake, `MainCoroutineRule`, Hilt test module).
- Package theo feature, mỗi feature một Screen + một ViewModel; `data/` có interface repository, `source/local` (Room), `source/network`.
- UDF: ViewModel kết hợp các `MutableStateFlow` private + `SavedStateHandle` bằng `combine`, lộ `StateFlow<UiState>` qua `stateIn(viewModelScope, …, initial)` (sample dùng helper riêng `WhileUiSubscribed`); lỗi vào state bằng `.catch` (`Async` sealed type); sự kiện UI → hàm ViewModel; thông báo một lần được xoá bằng hàm "đã hiển thị".
- Repository: Room là nguồn sự thật, ghi local trước rồi đồng bộ network, đọc là `Flow`; mapping model ở file riêng; qualifier cho dispatcher (`@IoDispatcher`, `@DefaultDispatcher`) và `@ApplicationScope`.
- Test: fake viết tay (`FakeTaskRepository`, `FakeTaskDao`, `FakeNetworkDataSource`), `@TestInstallIn(replaces = …)` thay module Hilt, Room in-memory cho test instrumented, test e2e ở `androidTest`.
- Kiểm: grep `Dispatchers\.` trong repository/ViewModel phải rỗng (trừ module cung cấp dispatcher); mỗi `@Module` trong `di/` có module test thay thế.
- CHƯA XÁC MINH từ README: nội dung nhánh `multimodule`; migration Room của sample.
