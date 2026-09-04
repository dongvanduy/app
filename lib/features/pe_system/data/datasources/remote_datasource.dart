import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/code_model.dart';

class RemoteDataSource {
  final ApiClient apiClient;

  RemoteDataSource({required this.apiClient});

  Future<List<SearchListModel>> getSearchList() async {
    try {
      final response = await apiClient.get('search-lists/details');
      print('API GetSearchList Response: $response');
      if (response is! Map<String, dynamic> || response['success'] != true) {
        throw ServerException(
            response['message'] ?? 'Không thể lấy danh sách mã');
      }

      final data = response['data'];
      if (data is! Map<String, dynamic> || data['lists'] is! List) {
        throw ServerException('Dữ liệu danh sách tìm kiếm không hợp lệ');
      }

      return (data['lists'] as List)
          .map((json) => SearchListModel.fromJson(json))
          .toList();
    } on ServerException catch (e) {
      print('API GetSearchList Error: $e');
      rethrow;
    } catch (e) {
      print('API GetSearchList Unexpected Error: $e');
      throw ServerException('Lỗi lấy danh sách mã: $e');
    }
  }

  Future<bool> scanSerialNumber(String serialNumber) async {
    try {
      final response = await apiClient.post('scanSN', {
        'serialNumber': serialNumber,
      });
      print('API ScanSN Request: {serialNumber: $serialNumber}');
      print('API ScanSN Response: $response');
      if (response is Map<String, dynamic> && response['success'] == false) {
        final errorMessage =
            response['message'] ?? 'Không thể ghi nhận mã đã quét';
        print('API ScanSN Failed: $errorMessage');
        throw ServerException(errorMessage);
      }
      return true;
    } on ServerException catch (e) {
      print('API ScanSN Exception: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    } catch (e) {
      print('API ScanSN Unexpected Exception: $e');
      print('Stack trace: ${StackTrace.current}');
      throw ServerException('Lỗi ghi nhận mã đã quét: $e');
    }
  }
}
