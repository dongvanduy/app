import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import '../models/bga_status_model.dart';

class BgaReplaceApiService {
  BgaReplaceApiService({ApiClient? apiClient})
      : _apiClient = apiClient ??
            ApiClient(
              baseUrl: 'https://pembd-adapter.cns.myfiinet.com/api/bga-replace/',
            );

  final ApiClient _apiClient;

  static const int defaultTimeoutSeconds = 15;

  Future<List<BgaStatusModel>> fetchStatuses(List<String> sns) async {
    if (sns.isEmpty) {
      throw ServerException('Danh sách SN không được để trống.');
    }

    final response = await _postWithTimeout(
      'status/bulk',
      {'sns': sns},
    );

    if (response is List) {
      return response
          .map((item) => BgaStatusModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw ServerException('Dữ liệu trả về không hợp lệ.');
  }

  Future<Map<String, dynamic>> updateStatus({
    required String sn,
    required int currentStatus,
    required String remark,
  }) async {
    final response = await _postWithTimeout(
      'update-status',
      {
        'sns': [sn],
        'currentStatus': currentStatus,
        'remark': remark,
      },
    );

    if (response is Map<String, dynamic>) {
      return response;
    }
    throw ServerException('Không nhận được phản hồi phù hợp từ máy chủ.');
  }

  Future<dynamic> _postWithTimeout(String endpoint, Map<String, dynamic> body) {
    return _apiClient
        .post(endpoint, body)
        .timeout(const Duration(seconds: defaultTimeoutSeconds), onTimeout: () {
      throw ServerException('Yêu cầu quá thời gian, vui lòng thử lại.');
    });
  }
}
