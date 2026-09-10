# Tra cứu sửa chữa

Chức năng nằm trong tab **Chi tiết**. Nhập SN rồi nhấn Enter/tìm kiếm, hoặc dùng camera để tra cứu. Sau khi nhấn Enter/tìm kiếm, ô nhập giữ focus và chọn toàn bộ SN để nhập mã tiếp theo. Đổi tab điều hướng giữ dữ liệu trong phiên; đăng xuất hủy trạng thái tra cứu.

Màu giao diện dùng chung DashboardColors với các màn hình khác. Hai nút lịch sử luôn nằm trên cùng một hàng, có chiều cao bằng nhau và cho phép nhãn xuống dòng bên trong nút.

Cập nhật giao diện ngày 09/09/2026: không chạy test hoặc gọi API theo yêu cầu người dùng; kết quả kiểm chứng bên dưới thuộc lần triển khai ngày 08/09/2026.

## API và dữ liệu

Dùng HTTP client có xác thực hiện có, với base URL từ ApiConfig.scanBaseUrl (có thể cấu hình bằng SCAN_API_BASE_URL). Chỉ gọi ba GET: sn-info, test-history, repair-history; query parameter là sn. Camera không gọi POST scanSN.

Ba khu vực tải độc lập và có retry riêng. Response đến muộn của lượt tra cứu trước bị bỏ qua. SN được trim, không tự đổi chữ hoặc ép định dạng.

- Product Line hiển thị —; Error Flag và mã người sửa giữ giá trị API.
- Test history dùng nhãn “Lịch sử xóa R_”, hiển thị tất cả bản ghi.
- Test sắp theo test_time; sửa chữa theo date3, thiếu thì dùng test_time. Thời gian hiển thị GMT+7.
- Trường thiếu hiển thị —, giữ nguyên N/A. Log xem trước bốn dòng; “Xem đầy đủ” hỗ trợ chọn và sao chép toàn bộ nội dung.
- Số bản ghi hiện số đã tải/tổng API nếu hai số khác nhau. Không giả định có phân trang hoặc trạng thái PASS.

Timeline hai cột khi vùng nội dung từ 720 logical pixels và tỷ lệ chữ không quá 1,3; hai thẻ liên tiếp xếp lệch nhau trong mỗi cặp. Các trường hợp còn lại dùng một cột. Hỗ trợ theme sáng/tối và nhãn Việt/Anh/Trung.

## Kiểm chứng

Fixtures trong test/support/repair_lookup_fixtures.dart giữ ba response do người dùng cung cấp cho SN 2616V762559401: ba bản ghi R001–R003 và một bản ghi FA001.

Lệnh kiểm thử:

~~~sh
flutter test --no-pub test/features/repair_lookup test/features/pe_system/presentation/dashboard_test.dart test/features/pe_system/presentation/qr_scan_test.dart
flutter analyze --no-pub
flutter build apk --debug --no-pub
~~~

Kết quả kiểm chứng ngày 08/09/2026:

- 94 kiểm thử feature/dashboard/QR thành công; gồm request race, retry riêng, trạng thái rỗng/lỗi, full log/copy, quét/hủy camera, giữ vị trí cuộn, ba ngôn ngữ, 200 sự kiện, Back và hủy dữ liệu khi đăng xuất.
- Giao diện kiểm tra rộng 320/390/720/1024, cỡ chữ 1,0/1,5/2,0, theme sáng/tối.
- Phân tích tĩnh các file feature và tích hợp không có vấn đề. Phân tích toàn repo vẫn báo các cảnh báo/thông tin có sẵn ở phần khác.
- Build Android debug thành công, đầu ra build/app/outputs/flutter-apk/app-debug.apk.

Máy phát triển không phân giải được pembd-adapter.cns.myfiinet.com khi gọi cả ba endpoint. Cần kiểm tra lại bằng tài khoản và mạng truy cập được backend. Chưa kiểm tra camera trên điện thoại thật vì phiên này không có thiết bị Android/iOS kết nối.