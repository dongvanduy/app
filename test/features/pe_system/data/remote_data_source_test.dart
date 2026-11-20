import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/pe_system/data/datasources/remote_datasource.dart';

void main() {
  group('RemoteDataSource.scanSerialNumber', () {
    test('maps the published ScanSN response envelope', () async {
      final dataSource = _dataSource((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://example.test/api/Scan/scanSN');
        expect(jsonDecode(request.body), <String, dynamic>{
          'searchListId': 359,
          'serialNumber': '2626V704003402',
        });
        return _jsonResponse(<String, dynamic>{
          'success': true,
          'message': 'Serial number saved successfully.',
          'data': <String, dynamic>{
            'eventId': 616,
            'searchListId': 359,
            'serialNumber': '2626V704003402',
            'isFound': true,
            'scannedAt': '2026-09-19T11:24:58.7636675+00:00',
            'scannedBy': 'V3201425',
            'foundAt': '2026-09-19T09:21:22.11+00:00',
          },
          'statusCode': 200,
        });
      });

      final result = await dataSource.scanSerialNumber(
        '2626V704003402',
        searchListId: 359,
      );

      expect(result.eventId, 616);
      expect(result.searchListId, 359);
      expect(result.serialNumber, '2626V704003402');
      expect(result.isFound, isTrue);
      expect(
        result.scannedAt,
        DateTime.parse('2026-09-19T11:24:58.7636675+00:00'),
      );
      expect(result.scannedBy, 'V3201425');
      expect(result.foundAt, DateTime.parse('2026-09-19T09:21:22.11+00:00'));
    });

    test('accepts a null foundAt for legacy found items', () async {
      final dataSource = _successfulDataSource(foundAt: null);

      final result = await dataSource.scanSerialNumber(
        'SN1234567890',
        searchListId: 10,
      );

      expect(result.foundAt, isNull);
    });

    test(
      'records a non-matching SN as success without marking it found',
      () async {
        var calls = 0;
        final dataSource = _dataSource((request) async {
          calls++;
          return _jsonResponse({
            'success': true,
            'data': {..._scanData(foundAt: null), 'isFound': false},
          });
        });
        final result = await dataSource.scanSerialNumber(
          'SN1234567890',
          searchListId: 10,
        );
        expect(result.isFound, isFalse);
        expect(result.eventId, 1);
        expect(result.foundAt, isNull);
        expect(calls, 1);
      },
    );

    test(
      'ScanSN sends JWT but never refreshes and replays its POST on 401',
      () async {
        var calls = 0;
        final tokens = _RefreshingTokenProvider();
        final dataSource = _dataSource((request) async {
          calls++;
          expect(request.headers['Authorization'], 'Bearer access-token');
          return _jsonResponse({'message': 'Expired'}, statusCode: 401);
        }, authTokenProvider: tokens);
        await expectLater(
          dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
          throwsA(
            isA<ServerException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(calls, 1);
        expect(tokens.refreshCalls, 0);
      },
    );

    test('other POST endpoints retain token refresh behavior', () async {
      var calls = 0;
      final tokens = _RefreshingTokenProvider();
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        authTokenProvider: tokens,
        client: MockClient((request) async {
          calls++;
          return calls == 1
              ? _jsonResponse({'message': 'Expired'}, statusCode: 401)
              : _jsonResponse({'success': true});
        }),
      );
      await client.post('other', {});
      expect(calls, 2);
      expect(tokens.refreshCalls, 1);
    });

    test('invalid successful response is not replayed', () async {
      var calls = 0;
      final dataSource = _dataSource((_) async {
        calls++;
        return _jsonResponse({'success': true, 'data': {}});
      });
      await expectLater(
        dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
        throwsA(
          isA<ServerException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('rejects missing or malformed response envelopes', () async {
      for (final response in <Object?>[
        null,
        <String, dynamic>{},
        <String, dynamic>{'success': true},
        <String, dynamic>{'success': true, 'data': <Object>[]},
      ]) {
        final dataSource = _dataSource((_) async => _jsonResponse(response));

        await expectLater(
          dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
          throwsA(
            isA<ServerException>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.invalidResponse,
            ),
          ),
        );
      }
    });

    test('uses the API message when a 200 response reports failure', () async {
      final dataSource = _dataSource(
        (_) async => _jsonResponse(<String, dynamic>{
          'success': false,
          'message': 'SN is locked.',
          'statusCode': 200,
        }),
      );

      await expectLater(
        dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
        throwsA(
          isA<ServerException>()
              .having((error) => error.message, 'message', 'SN is locked.')
              .having((error) => error.kind, 'kind', ApiFailureKind.business),
        ),
      );
    });

    test('rejects a response for another list or serial number', () async {
      for (final data in <Map<String, dynamic>>[
        _scanData(searchListId: 20),
        _scanData(serialNumber: 'SN1234567891'),
      ]) {
        final dataSource = _dataSource(
          (_) async => _jsonResponse(<String, dynamic>{
            'success': true,
            'data': data,
            'statusCode': 200,
          }),
        );

        await expectLater(
          dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
          throwsA(
            isA<ServerException>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.invalidResponse,
            ),
          ),
        );
      }
    });

    test('preserves HTTP authentication and not-found failures', () async {
      final cases = <(int, ApiFailureKind)>[
        (401, ApiFailureKind.unauthorized),
        (403, ApiFailureKind.forbidden),
        (404, ApiFailureKind.notFound),
      ];

      for (final testCase in cases) {
        final dataSource = _dataSource(
          (_) async => _jsonResponse(<String, dynamic>{
            'success': false,
            'code': 'REQUEST_FAILED',
            'message': 'Request failed.',
          }, statusCode: testCase.$1),
        );

        await expectLater(
          dataSource.scanSerialNumber('SN1234567890', searchListId: 10),
          throwsA(
            isA<ServerException>()
                .having((error) => error.statusCode, 'statusCode', testCase.$1)
                .having((error) => error.kind, 'kind', testCase.$2),
          ),
        );
      }
    });

    test('sends every rescan with the currently selected list ID', () async {
      final requests = <Map<String, dynamic>>[];
      var eventId = 700;
      final dataSource = _dataSource((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return _jsonResponse(<String, dynamic>{
          'success': true,
          'data': _scanData(
            eventId: eventId++,
            searchListId: body['searchListId'] as int,
            serialNumber: body['serialNumber'] as String,
          ),
          'statusCode': 200,
        });
      });

      final first = await dataSource.scanSerialNumber(
        'SN1234567890',
        searchListId: 10,
      );
      final rescan = await dataSource.scanSerialNumber(
        'SN1234567890',
        searchListId: 10,
      );
      final otherList = await dataSource.scanSerialNumber(
        'SN1234567890',
        searchListId: 20,
      );

      expect(requests.map((request) => request['searchListId']), <int>[
        10,
        10,
        20,
      ]);
      expect(<int>{first.eventId, rescan.eventId, otherList.eventId}.length, 3);
    });
  });

  group('RemoteDataSource.searchLists', () {
    test(
      'keeps paged summaries as incomplete until detail is requested',
      () async {
        final dataSource = _dataSource((request) async {
          expect(request.url.path, '/api/Scan/search-lists/details');
          expect(request.url.queryParameters, {'page': '1', 'pageSize': '20'});
          return _jsonResponse({
            'success': true,
            'data': {
              'page': 1,
              'pageSize': 20,
              'totalLists': 1,
              'totalPages': 1,
              'lists': [
                {
                  'searchListId': 318,
                  'listName': 'List',
                  'createdAt': '2026-09-18T08:37:28.247',
                  'createdBy': 'user',
                  'totalItems': 1,
                  'foundItems': 1,
                  'items': [],
                },
              ],
            },
          });
        });
        final page = await dataSource.getSearchListPage();
        expect(page.lists.single.hasDetails, isFalse);
        expect(page.lists.single.items, isEmpty);
      },
    );

    test('loads all selected items and maps scanTime to foundAt', () async {
      final dataSource = _dataSource((request) async {
        expect(request.url.path, '/api/Scan/search-lists/318/details');
        return _jsonResponse({
          'success': true,
          'data': {
            'searchListId': 318,
            'listName': 'List',
            'createdAt': '2026-09-18T08:37:28.247',
            'createdBy': 'user',
            'totalItems': 1,
            'foundItems': 1,
            'items': [
              {
                'id': 1,
                'serialNumber': 'SN1234567890',
                'isFound': true,
                'scanTime': '2026-09-18T01:56:43.048+00:00',
              },
            ],
          },
        });
      });
      final list = await dataSource.getSearchListDetails(318);
      expect(list.hasDetails, isTrue);
      expect(
        list.items.single.foundAt,
        DateTime.parse('2026-09-18T01:56:43.048+00:00'),
      );
    });
  });

  test('FindLocations maps the Product location to the requested FG', () async {
    final dataSource = _inventoryDataSource((request) async {
      expect(request.url.path, '/api/Inventory/FindLocations');
      expect(jsonDecode(request.body), ['FG-123']);
      return _jsonResponse({
        'success': true,
        'data': [
          {'serialNumber': ' fg-123 ', 'warehouse': 'Product', 'location': 'A2'},
        ],
      });
    });
    expect(await dataSource.findLocations(['FG-123']), {'FG-123': 'A2'});
  });

  group('RemoteDataSource.borrowRepair', () {
    test(
      'sends only serial numbers with JWT and maps item-level results',
      () async {
        final dataSource = _inventoryDataSource((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://inventory.example.test/api/Inventory/inventory-borrow-repair',
          );
          expect(request.headers['authorization'], 'Bearer access-token');
          expect(jsonDecode(request.body), <String, dynamic>{
            'serialNumbers': <String>['SN-OK', 'SN-MISSING', 'SN-FAILED'],
            'borrower': 'borrower',
          });
          return _jsonResponse(<String, dynamic>{
            'success': true,
            'totalBorrowed': 1,
            'totalNotFound': 1,
            'totalFailed': 1,
            'borrowedResults': <Map<String, dynamic>>[
              <String, dynamic>{
                'serialNumber': 'SN-OK',
                'borrowStatus': 'Borrowed',
                'borrowDate': '2026-09-21T08:30:00',
                'borrowPerson': 'jwt-user',
              },
            ],
            'notFoundSerials': <String>['SN-MISSING'],
            'failedSerials': <String>['SN-FAILED'],
            'warnings': <String>['Receiving-status synchronization failed.'],
          });
        });

        final result = await dataSource.borrowRepair(
          serialNumbers: <String>['SN-OK', 'SN-MISSING', 'SN-FAILED'],
          borrower: 'borrower',
        );

        expect(result.totalBorrowed, 1);
        expect(result.borrowed.single.requestedSerialNumber, 'SN-OK');
        expect(result.borrowed.single.borrowPerson, 'jwt-user');
        expect(result.notFoundSerials, <String>['SN-MISSING']);
        expect(result.failedSerials, <String>['SN-FAILED']);
        expect(result.warnings, <String>[
          'Receiving-status synchronization failed.',
        ]);
      },
    );

    test('preserves authorization failures', () async {
      final dataSource = _inventoryDataSource(
        (_) async => _jsonResponse(<String, dynamic>{
          'success': false,
          'message': 'Forbidden.',
        }, statusCode: 403),
      );

      await expectLater(
        dataSource.borrowRepair(
          serialNumbers: <String>['SN'],
          borrower: 'borrower',
        ),
        throwsA(
          isA<ServerException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.kind, 'kind', ApiFailureKind.forbidden),
        ),
      );
    });
  });
}

RemoteDataSource _successfulDataSource({required Object? foundAt}) {
  return _dataSource(
    (_) async => _jsonResponse(<String, dynamic>{
      'success': true,
      'data': _scanData(foundAt: foundAt),
      'statusCode': 200,
    }),
  );
}

RemoteDataSource _dataSource(
  Future<http.Response> Function(http.Request request) handler, {
  AuthTokenProvider? authTokenProvider,
}) {
  final scanClient = MockClient(handler);
  final unusedInventoryClient = MockClient(
    (_) async => throw StateError('Inventory API must not be called.'),
  );
  return RemoteDataSource(
    apiClient: ApiClient(
      baseUrl: 'https://example.test/api/Scan/',
      client: scanClient,
      authTokenProvider: authTokenProvider,
    ),
    inventoryApiClient: ApiClient(
      baseUrl: 'https://inventory.example.test/api/',
      client: unusedInventoryClient,
    ),
  );
}

RemoteDataSource _inventoryDataSource(
  Future<http.Response> Function(http.Request request) handler,
) {
  final unusedScanClient = MockClient(
    (_) async => throw StateError('Scan API must not be called.'),
  );
  return RemoteDataSource(
    apiClient: ApiClient(
      baseUrl: 'https://example.test/api/Scan/',
      client: unusedScanClient,
    ),
    inventoryApiClient: ApiClient(
      baseUrl: 'https://inventory.example.test/api/',
      client: MockClient(handler),
      authTokenProvider: _TokenProvider(),
    ),
  );
}

class _RefreshingTokenProvider extends _TokenProvider {
  int refreshCalls = 0;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    return 'refreshed-token';
  }
}

class _TokenProvider implements AuthTokenProvider {
  @override
  String? get accessToken => 'access-token';

  @override
  Future<String?> refreshAccessToken() async => null;
}

Map<String, dynamic> _scanData({
  int eventId = 1,
  int searchListId = 10,
  String serialNumber = 'SN1234567890',
  Object? foundAt = '2026-09-19T09:21:22.11+00:00',
}) {
  return <String, dynamic>{
    'eventId': eventId,
    'searchListId': searchListId,
    'serialNumber': serialNumber,
    'isFound': true,
    'scannedAt': '2026-09-19T11:24:58.7636675+00:00',
    'scannedBy': 'V3201425',
    'foundAt': foundAt,
  };
}

http.Response _jsonResponse(Object? body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
