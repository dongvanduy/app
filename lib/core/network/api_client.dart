//Xử lý gọi API,...
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../error/exceptions.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({required this.baseUrl})
      : _client = IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) =>
                    host == 'pembd-adapter.cns.myfiinet.com',
        );

  Future<dynamic> get(String endpoint) async {
    final uri = _buildUri(endpoint);
    try {
      final response = await _client.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      return _handleResponse(response);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Lỗi lấy dữ liệu: $e');
    }
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    final uri = _buildUri(endpoint);
    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(data),
      );
      return _handleResponse(response);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Lỗi gửi dữ liệu: $e');
    }
  }

  Uri _buildUri(String endpoint) {
    if (endpoint.startsWith('http')) {
      return Uri.parse(endpoint);
    }
    final sanitizedEndpoint = endpoint.startsWith('/')
        ? endpoint.substring(1)
        : endpoint;
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return base.resolve(sanitizedEndpoint);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw ServerException('Lỗi server: ${response.statusCode}');
    }
  }
}
