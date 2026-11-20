# Chat Android

Tab Chat nằm giữa Chi tiết và Cài đặt, có badge chưa đọc (tối đa 99+), danh bạ/tìm kiếm, hội thoại 1–1 và nhóm, lịch sử, gửi lại tin lỗi và trạng thái đã đọc. Mỗi tin có tối đa một JPEG/PNG/WebP 5 MiB, có thể gửi không chú thích. Chọn từ thư viện hoặc camera, xem trước/bỏ ảnh, xem ảnh lớn/phóng to. Bảng 40 emoji Unicode chèn ở con trỏ. Hỗ trợ theme sáng/tối và Việt/Anh/Trung.

## Cấu hình LAN

- `ApiConfig.chatBaseUrl` mặc định suy ra từ `inventoryBaseUrl` + `chat/`; hub là `inventoryBaseUrl` + `hubs/chat`. Với cấu hình hiện tại, app dùng cùng tên miền HTTPS nội bộ và `/api/chat/`, `/api/hubs/chat`.
- Có thể ghi đè bằng `--dart-define=CHAT_API_BASE_URL=https://your-internal-host/api/chat/` và `--dart-define=CHAT_HUB_URL=https://your-internal-host/api/hubs/chat`. Chat phải dùng cùng hệ thống tài khoản/JWT với app.
- Không có CDN, Firebase, push hoặc package SignalR mới. Dùng `http`, `uuid`, `image_picker` hiện có và adapter Dart IO cho SignalR JSON v1. Không bỏ qua xác minh TLS. Tên miền/chứng chỉ nội bộ phải hợp lệ trên thiết bị Android.
- API/IIS phải bật WebSocket. App dùng Bearer header khi upgrade WebSocket, không đưa JWT vào query string, không phụ thuộc thay đổi giới hạn query của IIS cho web.
- Chạy migration backend `001_CreateChatTables.sql` rồi `002_AddChatMessageImages.sql` trước nghiệm thu. Với hệ thống đã có chat văn bản chỉ cần chạy 002. App không tự sửa database. HTTP 500 được hiển thị là lỗi máy chủ, không giả làm danh sách rỗng.

## Đồng bộ và phiên đăng nhập

- REST gửi tin/ảnh; hub chỉ nhận MessageCreated/ReadStateChanged. Handshake JSON v1, tách record theo 0x1e kể cả frame bị chia/gộp; ping mỗi 15 giây, timeout handshake 15 giây, timeout server 45 giây. Retry 0/2/10/30 giây, tối đa 30 giây.
- Native WebSocket kết nối trực tiếp hub (không negotiate/không Azure SignalR). Reconcile REST mỗi 30 giây khi đã kết nối, mỗi 5 giây khi realtime không khả dụng. Các interval chỉ chạy foreground. Resume tải bù bằng afterSequence, merge ID và cursor liên tục để không mất tin đến sai thứ tự.
- API client dùng refresh dùng chung, retry tối đa một lần khi 401. Multipart được tạo lại từ cùng UUID/bytes/chú thích. Request cũ không retry sang phiên khác; refresh cũ không khôi phục phiên sau logout hoặc ghi đè tài khoản mới.
- Lịch sử/bản nháp/pending/cache ảnh chỉ ở bộ nhớ. Pending giữ UUID và bytes ảnh cho retry, không tự gửi lại với UUID mới sau timeout. Cache ảnh LRU tối đa 20 MiB; ảnh đang hiển thị có thể giữ thêm bytes trong widget. Logout xóa cache, trạng thái và bỏ các response thuộc phiên cũ.
- Chỉ gửi read cursor khi màn hình hội thoại là route hiện tại, app foreground, tin nằm trong vùng nhìn và ảnh đã giải mã/hiển thị. Không đánh dấu chỉ vì có sự kiện hoặc đổi tab.
- App xuống nền dừng hub và timer; quay lại tải bù. Không nhận push khi app đóng/chạy nền. Không ghi token/nội dung tin vào log. Không dùng kho lưu scan cho dữ liệu chat.

## Kiểm chứng

```powershell
flutter analyze --no-pub
flutter test --no-pub test/features/chat test/features/auth test/features/pe_system/presentation
flutter build apk --debug --no-pub
```

Tests mới: DTO/BIGINT/UTC, framing SignalR, WebSocket loopback với Authorization header và ping, timeout/stop, multipart refresh/retry, cache ảnh/response sau logout, provider merge/dedup/cursor, refresh race, lifecycle, emoji và widget 320px cho ba ngôn ngữ/sáng tối.

Máy triển khai hiện không có SDK ở đường dẫn cũ `C:\src\flutter`, và tải SDK chính thức qua proxy trả HTTP 407. Không nâng package hay sửa `local.properties` để che lỗi này. Cần cung cấp Flutter SDK tương thích (package_config hiện ghi Flutter 3.44.2 / Dart 3.12.2) và Android SDK/JDK phù hợp rồi chạy các lệnh trên. Không coi static review là kết quả Flutter test/build.

Kết quả hiện tại: đã kiểm tra tĩnh dấu ngoặc/chuỗi và đường dẫn import local của 25 file Dart mới/sửa. Chưa chạy được analyze, Flutter tests hoặc build APK vì thiếu SDK; chưa nghiệm thu trực tiếp Android–web. Không có APK mới được tạo trong lượt triển khai này.

Nghiệm thu Android–web với hai tài khoản: tìm/tạo chat, gửi văn bản/emoji/ảnh hai chiều, unread/read ở nhiều thiết bị, tắt LAN trong lúc gửi và thử lại, chuyển nền/resume, hết JWT, logout/đổi tài khoản, camera/thư viện bị từ chối quyền và ảnh quá 5 MiB. Kiểm tra màn PDA 320–360px với bàn phím. Chưa build iOS, chưa lưu offline bền vững. Chat nhóm: xem [chat-groups.md](chat-groups.md).
