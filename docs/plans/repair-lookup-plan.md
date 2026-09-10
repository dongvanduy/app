# Kế hoạch triển khai Tra cứu sửa chữa

Ngày: 08/09/2026. Phạm vi hiện tại: lập kế hoạch; chưa triển khai chức năng.

Căn cứ: hai ảnh và ba response JSON do người dùng cung cấp, đối chiếu mã nguồn hiện tại. Chưa gọi xác minh API thật. Dữ liệu minh họa trong ảnh không phải quy tắc nghiệp vụ.

## 1. Phạm vi và điểm tích hợp

- Đề xuất đặt RepairLookupScreen vào tab **Chi tiết**, thay placeholder `Bookmarks Page` trong NavigationRailPage; đây là giả định về vị trí, có thể đổi theo phản hồi người dùng.
- Giữ thanh Trang chủ / Chi tiết / Cài đặt và navigation rail hiện có. Nút quay lại của màn Chi tiết chuyển về Trang chủ; khi camera mở, Back chỉ đóng camera.
- Nhập SN bằng bàn phím/máy quét gửi Enter hoặc camera, xem thông tin sản phẩm, chuyển giữa hai lịch sử và mở toàn bộ log lỗi.
- Hai nút “Lịch sử xóa R_” và “Lịch sử sửa chữa SmartFA” chỉ chuyển nội dung tra cứu. Phạm vi gồm ba GET API được cung cấp.

| Thành phần hiện có | Cách tích hợp |
| --- | --- |
| `lib/core/config/api_config.dart` | Dùng `ApiConfig.scanBaseUrl`, đã trỏ đúng `/api/Scan/` và hỗ trợ `SCAN_API_BASE_URL`. |
| `lib/core/network/api_client.dart` | Tái sử dụng GET, query parameters, timeout, phân loại lỗi và token/refresh. |
| `lib/features/pe_system/presentation/screens/qr_scan_page.dart` | Tái sử dụng callback `onCodeScanned`; màn camera hiện đã chặn mã lặp và đóng trước khi gọi callback. |
| `dashboard_theme.dart`, `business_widgets.dart` | Dùng theme, card, trạng thái trống/lỗi; điều chỉnh màu trong phạm vi màn mới để gần ảnh. |
| `business_translations.dart` | Bổ sung nhãn Việt / Anh / Trung theo cơ chế hiện hành. |
| `navigation_rail_page.dart` | Thay placeholder index 1; IndexedStack giữ trạng thái khi chuyển tab. |

Lưu ý: PESystemScreen hiện phục vụ danh sách tìm kiếm và gọi POST scanSN để ghi nhận quét. Luồng mới cần repository riêng; callback camera gọi lookup mới, không gọi CodeProvider.handleScanCode.

## 2. Ánh xạ API

Base URL dùng cấu hình hiện hành, truyền SN qua `queryParameters: {'sn': sn}`.

| GET endpoint | Dữ liệu | Giao diện |
| --- | --- | --- |
| `sn-info` | `sn`, `wip_group`, `model_name`, `error_flag` | Thông tin sản phẩm và badge tìm thấy SN. |
| `test-history` | `sn`, `total`, `histories[]` | Tab Lịch sử xóa R_ theo ảnh. |
| `repair-history` | `sn`, `total`, `histories[]` | Tab Lịch sử sửa chữa SmartFA. |

Thông tin sản phẩm:

- Giữ bốn ô WIP Group / Product Line / Model Name / Error Flag như ảnh.
- Product Line chưa có trong sn-info: hiển thị `—` đến khi backend cung cấp nguồn chính thức; không suy từ model hoặc lấy MacBook từ ảnh.
- Error Flag hiển thị mã `7`; chỉ thêm mô tả khi có bảng mã xác nhận, không tự quy đổi thành No Power.
- Badge Đã tìm thấy chỉ xuất hiện khi sn-info thành công và dữ liệu hợp lệ; badge không nói rằng sản phẩm đã sửa xong.

Lịch sử test:

- Mỗi card hiển thị `test_group`, `test_code`, `error_desc`, `error_code_item`, `test_time`, `reason_code`, `reason_desc`, `memo`.
- `test_code` và `error_desc` có nhiều Step và rất dài: xem trước 3–4 dòng, có Xem đầy đủ mở vùng cuộn/chọn/sao chép được, giữ nguyên xuống dòng.
- Hiển thị reason_code cùng reason_desc khi có; nếu thiếu mô tả vẫn giữ mã RC53/RC35.
- Trường null/rỗng hiển thị `—`; giữ nguyên giá trị `N/A` do API cung cấp.

Lịch sử sửa chữa:

- Mỗi card hiển thị `test_group`, `test_time`, `date3`, `repairer`, `repair_action`.
- Giữ mã người sửa `V4100523`; chưa có dữ liệu để chuyển thành tên người như ảnh.
- Tạm giữ nhãn DATE3 theo ảnh, chờ xác nhận nghĩa nghiệp vụ trước khi đổi thành Thời gian sửa/Hoàn tất.
- Hành động sửa dài có Xem đầy đủ, giữ nguyên nội dung trả về.

Quy tắc chung:

- Test sắp xếp cũ → mới theo test_time; sửa chữa tạm theo date3, thiếu thì dùng test_time. Vẫn hiển thị cả hai thời gian.
- So sánh theo timestamp đã parse offset; thời gian bằng nhau giữ thứ tự API. Ngày không hợp lệ đặt cuối và hiển thị `—`.
- Hiển thị `dd/MM/yyyy HH:mm:ss`, theo GMT+7 và ghi rõ múi giờ; không ngầm phụ thuộc múi giờ thiết bị.
- Số thứ tự là thứ tự hiển thị; giữ id bản ghi. Lưu cả total và danh sách; nếu chúng lệch nhau, hiển thị số đã tải/tổng từ API. Chưa giả định endpoint phân trang.
- Tên Lịch sử xóa R_ đang theo ảnh: cần đối chiếu backend xem test-history có đúng nghĩa lịch sử xóa R_ hay là toàn bộ lịch sử test.
- Điểm cuối timeline dùng biểu tượng trung tính. API chưa có trạng thái đủ để hiển thị PASS/hoàn tất như dấu tick trong ảnh.

## 3. Luồng và trạng thái

1. Mở màn: hiển thị hướng dẫn nhập SN, chưa gọi API.
2. Enter, nút tìm và QR cùng gọi lookup(sn). Trim khoảng trắng đầu/cuối và ký tự kết thúc máy quét; chặn SN rỗng. Chưa áp chiều dài/regex hoặc đổi ký tự khi thiếu quy tắc backend.
3. Ghi nhận SN đang tra, tăng request ID, xóa kết quả của SN trước; chuyển ba vùng sang loading.
4. Gọi ba GET đồng thời; mỗi request xử lý kết quả và lỗi riêng, vùng nào hoàn tất cập nhật vùng đó. Một API lỗi không che hai vùng thành công.
5. Kiểm tra success, cấu trúc data/histories và SN response khớp SN yêu cầu. HTTP 200 với success:false là lỗi nghiệp vụ.
6. Chỉ nhận response nếu request ID vẫn hiện hành và provider chưa dispose. Request A hoàn tất sau khi quét B không được sửa dữ liệu/trạng thái của B, kể cả nhánh catch/finally.
7. Chặn submit trùng SN đang tải. Submit lại SN đã tải hoặc Làm mới thì tải lại; Thử lại ở một vùng chỉ tải endpoint tương ứng và cũng có cơ chế bỏ qua response cũ.
8. Đổi hai tab lịch sử dùng dữ liệu đã tải, giữ vị trí cuộn riêng, không gọi lại API. Chuyển tab điều hướng giữ SN trong vòng đời trang.

Mỗi vùng có idle/loading/success/empty/error riêng. Phân biệt chưa có lịch sử với lỗi mạng, timeout, quyền truy cập và response sai cấu trúc. Chỉ báo Không tìm thấy SN khi backend trả kết quả không tìm thấy rõ ràng; chưa quy mọi success:false hoặc 404 thành SN không tồn tại khi thiếu hợp đồng lỗi.

Repository nhận ApiClient có auth từ cấu hình hiện tại. Provider tạo trong phạm vi màn Chi tiết, được IndexedStack giữ khi đổi tab, dispose khi trang điều hướng bị hủy lúc đăng xuất. Màn hình không tự đóng client dùng chung.

## 4. Giao diện

- Tiêu đề TRA CỨU SỬA CHỮA, nền mint nhạt, card bo góc, viền mảnh, màu nhấn teal; dùng token phạm vi màn hình khi cần khớp ảnh.
- Ô SN có tìm kiếm và camera, hỗ trợ action tìm kiếm của bàn phím.
- Card thông tin có badge trạng thái và bốn ô, giá trị dài tự xuống dòng.
- Hai nút lịch sử: nút chọn tô teal, nút còn lại viền teal; thêm số bản ghi khi đã tải. Mặc định chọn Lịch sử xóa R_.
- Timeline có trục dọc, node và nhánh nối card trái/phải luân phiên. Card cao theo nội dung, nhánh bám theo layout thực tế.
- Đề xuất hai cột khi vùng nội dung từ 720 logical pixels và cỡ chữ phù hợp. Điện thoại hẹp/cỡ chữ lớn dùng trục bên trái, card một cột để đọc log; kiểm tra lại ngưỡng trên thiết bị mục tiêu.
- Card sản phẩm đổi thành một cột khi thiếu chỗ; nút lịch sử cho phép xuống dòng/xếp dọc. Dùng danh sách dựng theo nhu cầu cho nhiều sự kiện và chỉ mở log đầy đủ khi cần.
- Timeline dùng widget/painter nội bộ, chưa cần thư viện mới. Có loading, empty và lỗi kèm Thử lại trong từng vùng.
- Kiểm tra theme tối và cỡ chữ lớn theo khả năng app hiện tại. Nhãn giao diện được dịch, dữ liệu API giữ nguyên.

## 5. File dự kiến

Tạo feature riêng theo cấu trúc hiện hành:

```text
lib/features/repair_lookup/
  data/
    datasources/repair_lookup_remote_data_source.dart
    models/repair_lookup_dtos.dart
    repositories/repair_lookup_repository_impl.dart
  domain/
    entities/repair_lookup_models.dart
    repositories/repair_lookup_repository.dart
  presentation/
    providers/repair_lookup_provider.dart
    screens/repair_lookup_screen.dart
    widgets/sn_search_section.dart
    widgets/product_info_card.dart
    widgets/history_tabs.dart
    widgets/history_timeline.dart
    widgets/test_history_card.dart
    widgets/repair_history_card.dart
    widgets/history_detail_sheet.dart
```

- Model: SnInfo, TestHistoryEntry, RepairHistoryEntry và kết quả lịch sử có sn/total/histories; trường tùy chọn nullable và giữ log gốc.
- Repository: getSnInfo(sn), getTestHistory(sn), getRepairHistory(sn), có thể thay bằng fake khi test.
- `lib/main.dart`: tạo/inject datasource và repository bằng Provider cùng dependencies hiện có.
- `navigation_rail_page.dart`: thay placeholder bằng màn mới, giữ một bộ thanh điều hướng.
- `business_translations.dart`: bổ sung nhãn/thông báo ba ngôn ngữ.
- `test/features/pe_system/presentation/dashboard_test.dart`: cập nhật test placeholder và fake repository trong harness.
- ApiConfig hiện đủ cho ba endpoint, chưa cần đổi host hoặc thêm base URL.

## 6. Thứ tự thực hiện

| Bước | Công việc | Đầu ra |
| --- | --- | --- |
| 1 | Models, datasource, repository, fixtures từ ba JSON mẫu. | Parse đúng trường, null, log nhiều dòng và lỗi API. |
| 2 | Provider và tìm SN. | Ba vùng tải độc lập, retry được, không bị response cũ ghi đè. |
| 3 | Màn nhập, thông tin và chuyển lịch sử. | Dữ liệu mẫu đúng, đầy đủ loading/empty/error. |
| 4 | Timeline, card, xem log và responsive. | Không tràn màn hẹp/chữ lớn; hai cột theo ảnh khi đủ rộng. |
| 5 | Điều hướng, QR, DI, bản dịch. | Nhập/quét cùng luồng, đổi tab giữ trạng thái, đăng xuất hủy dữ liệu màn hình. |
| 6 | Kiểm thử và đối chiếu thiết bị/API thật. | Đạt tiêu chí nghiệm thu; ghi rõ hạn chế nếu môi trường thật chưa truy cập được. |

## 7. Kiểm thử và nghiệm thu

- Datasource/model: đúng GET/path/query sn, ba JSON mẫu, null, log nhiều dòng, GMT+7, envelope lỗi và kiểu dữ liệu không hợp lệ.
- Provider: A/B trả đảo thứ tự; một API lỗi trong khi hai API thành công; retry từng vùng; danh sách rỗng; submit lặp; callback sau dispose.
- Widget: nhập SN, đổi lịch sử, mở/sao chép log, giữ SN khi đổi tab điều hướng, badge đúng; không hiện PASS giả.
- Navigation/QR: thay assertion placeholder, callback camera tra cứu một lần, hủy camera giữ trang, không gọi POST scanSN.
- Kiểm tra tổ hợp đại diện ở rộng 320/390/720/1024, text scale 1.0/1.5/2.0, theme sáng/tối; cả hai tab, log dài và nhiều bản ghi.
- Khi triển khai chạy flutter analyze, test feature mới và test dashboard/QR bị ảnh hưởng; mở rộng khi có lỗi hoặc thay đổi liên quan.

Với SN `2616V762559401` và dữ liệu mẫu:

| Nội dung | Kết quả mong đợi |
| --- | --- |
| WIP Group | BLOCK-R_ICT |
| Model Name | 699-9X9OE-0301EBAN |
| Error Flag / Product Line | 7 / — |
| Lịch sử test | 3 bản ghi R001 → R002 → R003 |
| Log test | Xem đầy đủ U190 ở R001 và C1850/C1961 ở R002/R003, giữ xuống dòng |
| Mã lý do | RC53, RC35, — theo thứ tự bản ghi |
| Lịch sử sửa chữa | 1 bản ghi FA001, người sửa V4100523 |
| Hành động sửa | retets fail đúng lỗi chờ FA TIP |
| Thời gian FA001 | TEST_TIME 06/09/2026 05:01:40; DATE3 06/09/2026 14:45:57, GMT+7 |

Cần đối chiếu backend khi tích hợp thật: nguồn Product Line, bảng mã error_flag, nghĩa test-history/xóa R_, nghĩa date3 và response khi SN không tồn tại. Các trường chưa rõ có cách hiển thị dự phòng để triển khai theo dữ liệu mẫu.
