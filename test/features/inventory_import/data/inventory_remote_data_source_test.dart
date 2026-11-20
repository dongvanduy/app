import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/inventory_import/data/datasources/inventory_remote_data_source.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/export_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';

void main() {
  test('export sends the tray location and occupied SNs to the repair route',
      () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://example.test/api/Inventory/export-inventory-repair',
      );
      expect(
        jsonDecode(request.body),
        <String, dynamic>{
          'Shelf': 'A1',
          'Column': 2,
          'Level': 0,
          'Tray': 3,
          'SerialNumbers': <String>['SN-001', 'SN-002'],
        },
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'message': 'Export completed',
        }),
        200,
      );
    });
    final apiClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      client: httpClient,
    );
    final dataSource = InventoryRemoteDataSource(
      inventoryApiClient: apiClient,
    );

    final result = await dataSource.exportInventory(
      StockType.repair,
      const ExportInventoryRequest(
        shelf: 'A1',
        column: 2,
        level: 0,
        tray: 3,
        serialNumbers: <String>['SN-001', 'SN-002'],
      ),
    );

    expect(result.success, isTrue);
    expect(result.message, 'Export completed');
  });

  test('SN lookup maps the published get-info-sn response', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://example.test/api/get-info-sn?serialNumber=SN-001',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'wipGroup': 'B30M',
            'productLine': 'HAMILTON',
            'modelName': '699-9D4B4-0400QS1N',
          },
        }),
        200,
      );
    });
    final dataSource = InventoryRemoteDataSource(
      inventoryApiClient: ApiClient(
        baseUrl: 'https://example.test/api/',
        client: httpClient,
      ),
    );

    final result = await dataSource.getSerialInfo('SN-001');

    expect(result?.serialNumber, 'SN-001');
    expect(result?.wipGroup, 'B30M');
    expect(result?.modelName, '699-9D4B4-0400QS1N');
    expect(result?.productLine, 'HAMILTON');
  });

  test('SN lookup propagates HTTP errors instead of returning not found',
      () async {
    final dataSource = InventoryRemoteDataSource(
      inventoryApiClient: ApiClient(
        baseUrl: 'https://example.test/api/',
        client: MockClient((_) async => http.Response('', 404)),
      ),
    );

    await expectLater(
      dataSource.getSerialInfo('SN-001'),
      throwsA(
        isA<ServerException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.notFound,
            ),
      ),
    );
  });
}
