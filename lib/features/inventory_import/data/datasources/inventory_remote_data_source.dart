import 'dart:developer' as developer;

import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/export_inventory_request.dart';
import '../../domain/entities/import_inventory_request.dart';
import '../../domain/entities/inventory_location.dart';
import '../../domain/entities/inventory_models.dart';
import '../../domain/entities/stock_type.dart';
import '../models/inventory_dtos.dart';

class InventoryRemoteDataSource {
  final ApiClient inventoryApiClient;

  const InventoryRemoteDataSource({
    required this.inventoryApiClient,
  });

  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  ) async {
    final trayPath = stockType.trayPath;
    if (trayPath == null) {
      throw const ServerException(
        'This stock type does not use tray information.',
        kind: ApiFailureKind.business,
      );
    }

    final response = await inventoryApiClient.get(
      trayPath,
      queryParameters: location.toQueryParameters(),
    );
    final json = _requireJsonObject(response, endpoint: trayPath);
    if (json['success'] != true) {
      throw ServerException(
        _message(json, 'Unable to load tray information.'),
        kind: ApiFailureKind.business,
        responseData: json,
      );
    }

    try {
      return InventoryDtoMapper.trayInfoFromJson(json);
    } on FormatException catch (error) {
      throw ServerException(
        'Tray information has an invalid format.',
        kind: ApiFailureKind.invalidResponse,
        responseData: error,
      );
    }
  }

  Future<SerialInfo?> getSerialInfo(String serialNumber) async {
    const endpoint = 'Inventory/get-info-sn';
    final requestUri = _buildRequestUri(
      endpoint,
      <String, Object?>{'serialNumber': serialNumber},
    );
    developer.log(
      'GET $requestUri',
      name: 'InventoryApi.getSerialInfo',
    );

    try {
      final response = await inventoryApiClient.get(
        endpoint,
        queryParameters: <String, Object?>{'serialNumber': serialNumber},
      );
      developer.log(
        'Response from $requestUri: $response',
        name: 'InventoryApi.getSerialInfo',
      );
      final json = _requireJsonObject(response, endpoint: endpoint);
      if (json['success'] == false) {
        return null;
      }
      final rawData = json['data'];
      final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
      return InventoryDtoMapper.serialInfoFromJson(
        serialNumber,
        data,
      );
    } catch (error, stackTrace) {
      developer.log(
        error is ServerException
            ? 'Request to $requestUri failed '
                '(status: ${error.statusCode ?? 'n/a'}, '
                'response: ${error.responseData})'
            : 'Request to $requestUri failed',
        name: 'InventoryApi.getSerialInfo',
        error: error,
        stackTrace: stackTrace,
      );
      if (error is FormatException) {
        throw ServerException(
          'Serial information has an invalid format.',
          kind: ApiFailureKind.invalidResponse,
          responseData: error,
        );
      }
      rethrow;
    }
  }

  Uri _buildRequestUri(
    String endpoint,
    Map<String, Object?> queryParameters,
  ) {
    final base = Uri.parse(
      inventoryApiClient.baseUrl.endsWith('/')
          ? inventoryApiClient.baseUrl
          : '${inventoryApiClient.baseUrl}/',
    );
    final uri = endpoint.startsWith('http')
        ? Uri.parse(endpoint)
        : base.resolve(
            endpoint.startsWith('/') ? endpoint.substring(1) : endpoint,
          );
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        for (final entry in queryParameters.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
  }

  Future<InventoryImportResult> importInventory(
    StockType stockType,
    ImportInventoryRequest request,
  ) async {
    final response = await inventoryApiClient.post(
      stockType.importPath,
      request.toJson(),
    );
    final json = _requireJsonObject(
      response,
      endpoint: stockType.importPath,
    );
    try {
      return InventoryDtoMapper.importResultFromJson(json);
    } on FormatException catch (error) {
      throw ServerException(
        'Inventory import result has an invalid format.',
        kind: ApiFailureKind.invalidResponse,
        responseData: error,
      );
    }
  }

  Future<InventoryExportResult> exportInventory(
    StockType stockType,
    ExportInventoryRequest request,
  ) async {
    final exportPath = stockType.exportPath;
    final response = await inventoryApiClient.post(
      exportPath,
      request.toJson(),
    );
    final json = _requireJsonObject(
      response,
      endpoint: exportPath,
    );
    try {
      return InventoryDtoMapper.exportResultFromJson(json);
    } on FormatException catch (error) {
      throw ServerException(
        'Inventory export result has an invalid format.',
        kind: ApiFailureKind.invalidResponse,
        responseData: error,
      );
    }
  }

  Map<String, dynamic> _requireJsonObject(
    Object? response, {
    required String endpoint,
  }) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    throw ServerException(
      'The server returned an invalid response.',
      kind: ApiFailureKind.invalidResponse,
      responseData: <String, Object?>{
        'endpoint': endpoint,
        'response': response,
      },
    );
  }

  String _message(Map<String, dynamic> json, String fallback) {
    final message = json['message']?.toString().trim();
    return message == null || message.isEmpty ? fallback : message;
  }
}
