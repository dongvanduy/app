import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/repair_lookup_models.dart';
import '../models/repair_lookup_dtos.dart';

class RepairLookupRemoteDataSource {
  const RepairLookupRemoteDataSource({required this.apiClient});
  final ApiClient apiClient;

  Future<T> _get<T>(
    String endpoint,
    String sn,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final response = await apiClient.get(endpoint, queryParameters: {'sn': sn});
    try {
      final json = RepairLookupDtos.object(response);
      if (json['success'] == false) {
        final message = json['message'];
        throw ServerException(
          message is String && message.trim().isNotEmpty
              ? message
              : 'lookup_business_error',
          kind: ApiFailureKind.business,
        );
      }
      if (json['success'] != true) {
        throw const FormatException('Missing success.');
      }
      final data = RepairLookupDtos.object(json['data']);
      if (RepairLookupDtos.requiredString(data, 'sn') != sn) {
        throw const FormatException('Response serial number does not match.');
      }
      return parse(data);
    } on FormatException {
      throw const ServerException(
        'lookup_invalid_response',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<SnInfo> getSnInfo(String sn) =>
      _get('sn-info', sn, RepairLookupDtos.snInfo);

  Future<HistoryResult<TestHistoryEntry>> getTestHistory(String sn) => _get(
    'test-history',
    sn,
    (json) => RepairLookupDtos.history(
      json,
      RepairLookupDtos.testEntry,
      (entry) => entry.testTime,
    ),
  );

  Future<HistoryResult<RepairHistoryEntry>> getRepairHistory(String sn) => _get(
    'repair-history',
    sn,
    (json) => RepairLookupDtos.history(
      json,
      RepairLookupDtos.repairEntry,
      (entry) => entry.eventTime,
    ),
  );
}
