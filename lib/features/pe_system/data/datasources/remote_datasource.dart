import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/code_model.dart';
import '../models/pe_inventory_mapper.dart';
import '../../domain/entities/borrow_repair_result.dart';
import '../../domain/entities/scan_result.dart';

class RemoteDataSource {
  final ApiClient apiClient;

  final ApiClient inventoryApiClient;

  RemoteDataSource({required this.apiClient, required this.inventoryApiClient});

  Future<Map<String, String>> findLocations(List<String> serialNumbers) async {
    final serials =
        serialNumbers
            .map((sn) => sn.trim())
            .where((sn) => sn.isNotEmpty)
            .toSet()
            .toList();
    if (serials.isEmpty) return {};
    return PeInventoryMapper.locations(
      await inventoryApiClient.post('Inventory/FindLocations', serials),
    );
  }

  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
  }) async {
    const endpoint = 'Inventory/inventory-borrow-repair';
    final body = {'serialNumbers': serialNumbers, 'borrower': borrower.trim()};
    if (kDebugMode) {
      final base = inventoryApiClient.baseUrl;
      final uri = Uri.parse(
        base.endsWith('/') ? base : '$base/',
      ).resolve(endpoint);
      debugPrint('PE borrow request: POST $uri');
      debugPrint('PE borrow body: ${jsonEncode(body)}');
    }
    try {
      final response = await inventoryApiClient.post(endpoint, body);
      if (kDebugMode) debugPrint('PE borrow response: ${jsonEncode(response)}');
      return PeInventoryMapper.borrow(response);
    } on ServerException catch (error) {
      if (kDebugMode) {
        debugPrint(
          'PE borrow error: status=${error.statusCode}, '
          'message=${error.message}, response=${error.responseData}',
        );
      }
      rethrow;
    }
  }

  Future<List<SearchListModel>> getSearchList() async {
    final response = await _getSearchListResponse('search-lists/details');
    return _parseSearchLists(() {
      final data = response['data'];
      if (data is! Map<String, dynamic> ||
          data['lists'] is! List ||
          ['page', 'pageSize', 'totalPages'].any(data.containsKey)) {
        throw const FormatException('Expected full legacy search lists');
      }
      final lists =
          (data['lists'] as List)
              .map(
                (item) =>
                    SearchListModel.fromJson(item as Map<String, dynamic>),
              )
              .toList();
      if (data['totalLists'] != lists.length) {
        throw const FormatException('Incomplete legacy search lists');
      }
      return lists;
    });
  }

  Future<SearchListPageModel> getSearchListPage({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _getSearchListResponse(
      'search-lists/details',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return _parseSearchLists(
      () => SearchListPageModel.fromJson(
        response,
        requestedPage: page,
        requestedPageSize: pageSize,
      ),
    );
  }

  Future<SearchListModel> getSearchListDetails(int searchListId) async {
    Map<String, dynamic> response;
    try {
      response = await _getSearchListResponse(
        'search-lists/$searchListId/details',
        listId: searchListId,
      );
    } on ServerException catch (error) {
      final body = error.responseData;
      if (error.statusCode != 404 ||
          (body is Map && body['code'] == 'SEARCH_LIST_NOT_FOUND')) {
        rethrow;
      }
      // An older server may not have the per-list route. Never fall back on
      // authentication failures or an explicit deleted-list response.
      final lists = await getSearchList();
      for (final list in lists) {
        if (list.id == searchListId.toString()) return list;
      }
      throw const ServerException(
        'Không tìm thấy SearchList.',
        statusCode: 404,
        kind: ApiFailureKind.notFound,
        responseData: {'code': 'SEARCH_LIST_NOT_FOUND'},
      );
    }
    return _parseSearchLists(() {
      final data = response['data'];
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid search list detail response');
      }
      final list = SearchListModel.fromJson(data);
      if (list.id != searchListId.toString()) {
        throw const FormatException('Search list ID does not match request');
      }
      return list;
    });
  }

  Future<Map<String, dynamic>> _getSearchListResponse(
    String endpoint, {
    Map<String, Object?>? queryParameters,
    int? listId,
  }) async {
    final response = await apiClient.get(
      endpoint,
      queryParameters: queryParameters,
      debugLabel: 'PE SearchList listId=${listId ?? '-'}',
    );
    if (response is! Map<String, dynamic> || response['success'] is! bool) {
      throw const ServerException(
        'Dữ liệu danh sách tìm kiếm không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    if (response['success'] != true) {
      throw ServerException(
        response['message'] is String
            ? response['message']
            : 'Không thể tải danh sách tìm kiếm.',
        statusCode:
            response['statusCode'] is int ? response['statusCode'] : null,
        kind: ApiFailureKind.business,
        responseData: response,
      );
    }
    return response;
  }

  T _parseSearchLists<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw const ServerException(
        'Dữ liệu danh sách tìm kiếm không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
      );
    } on TypeError {
      throw const ServerException(
        'Dữ liệu danh sách tìm kiếm không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
    String? clientScanId,
    DateTime? scannedAt,
  }) async {
    try {
      final body = <String, Object?>{
        'searchListId': searchListId,
        'serialNumber': serialNumber,
        if (clientScanId != null) 'clientScanId': clientScanId,
        if (scannedAt != null) 'scannedAt': scannedAt.toUtc().toIso8601String(),
      };
      if (kDebugMode) debugPrint('PE scan body: ${jsonEncode(body)}');
      final response = await apiClient.post(
        'scanSN',
        body,
        retryAfterTokenRefresh: false,
      );
      print('API ScanSN Response: $response');
      return _parseScanResult(
        response,
        expectedSearchListId: searchListId,
        expectedSerialNumber: serialNumber,
        expectedClientScanId: clientScanId,
        expectedScannedAt: scannedAt,
      );
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

  ScanResult _parseScanResult(
    Object? response, {
    required int expectedSearchListId,
    required String expectedSerialNumber,
    String? expectedClientScanId,
    DateTime? expectedScannedAt,
  }) {
    if (response is! Map<String, dynamic>) {
      throw ServerException(
        'Dữ liệu phản hồi scan không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
        responseData: response,
      );
    }

    final success = response['success'];
    if (success == false) {
      final message = response['message'];
      final statusCode = response['statusCode'];
      throw ServerException(
        message is String && message.trim().isNotEmpty
            ? message.trim()
            : 'Không thể ghi nhận mã đã quét.',
        statusCode: statusCode is int ? statusCode : null,
        kind: ApiFailureKind.business,
        responseData: response,
      );
    }

    final data = response['data'];
    if (success != true || data is! Map<String, dynamic>) {
      throw ServerException(
        'Dữ liệu phản hồi scan không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
        responseData: response,
      );
    }

    final eventId = data['eventId'];
    final searchListId = data['searchListId'];
    final serialNumber = data['serialNumber'];
    final isFound = data['isFound'];
    final scannedAtValue = data['scannedAt'];
    final scannedBy = data['scannedBy'];
    final hasFoundAt = data.containsKey('foundAt');
    final foundAtValue = data['foundAt'];
    final scannedAt =
        scannedAtValue is String ? DateTime.tryParse(scannedAtValue) : null;
    final foundAt =
        foundAtValue is String ? DateTime.tryParse(foundAtValue) : null;
    final validFoundAt =
        hasFoundAt &&
        (foundAtValue == null || (foundAtValue is String && foundAt != null));
    final normalizedExpected = expectedSerialNumber.trim().toUpperCase();

    if (eventId is! int ||
        eventId <= 0 ||
        (expectedClientScanId != null &&
            data['clientScanId'] != expectedClientScanId) ||
        (expectedScannedAt != null && scannedAt != expectedScannedAt) ||
        searchListId is! int ||
        serialNumber is! String ||
        isFound is! bool ||
        scannedAt == null ||
        scannedBy is! String ||
        scannedBy.trim().isEmpty ||
        !validFoundAt ||
        searchListId != expectedSearchListId ||
        serialNumber.trim().toUpperCase() != normalizedExpected ||
        (!isFound && foundAtValue != null)) {
      throw ServerException(
        'Dữ liệu phản hồi scan không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
        responseData: response,
      );
    }

    return ScanResult(
      clientScanId: data['clientScanId'] as String?,
      eventId: eventId,
      searchListId: searchListId,
      serialNumber: normalizedExpected,
      isFound: isFound,
      scannedAt: scannedAt,
      scannedBy: scannedBy.trim(),
      foundAt: foundAt,
    );
  }

  Future<bool> supportsScanSync() async {
    if (kDebugMode)
      debugPrint('PE scan sync capability: GET sync-capabilities');
    final response = await apiClient.get('sync-capabilities');
    final supported =
        response is Map &&
        response['success'] == true &&
        response['data'] is Map &&
        response['data']['scanSyncVersion'] == 1;
    if (kDebugMode) debugPrint('PE scan sync capability: supported=$supported');
    return supported;
  }
}
