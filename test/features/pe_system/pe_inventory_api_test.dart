import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/pe_system/data/datasources/remote_datasource.dart';
import 'package:mobile_app/features/pe_system/data/models/pe_inventory_mapper.dart';
import 'package:mobile_app/features/pe_system/data/repositories/code_repository_impl.dart';
import '../../support/pe_inventory_fixtures.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';

class _Tokens implements AuthTokenProvider {
  @override
  String? get accessToken => 'pe-token';
  @override
  Future<String?> refreshAccessToken() async => null;
}

void main() {
  test(
    'provided fixtures use inventory URLs, array/object bodies and auth',
    () async {
      final requests = <http.Request>[];
      final inventory = ApiClient(
        baseUrl: 'https://example.test/api/',
        authTokenProvider: _Tokens(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('FindLocations')
                  ? peLocationsFixture
                  : peBorrowFixture,
            ),
            200,
          );
        }),
      );
      final scan = ApiClient(baseUrl: 'https://example.test/api/Scan/');
      addTearDown(inventory.close);
      addTearDown(scan.close);
      final repository = CodeRepositoryImpl(
        remoteDataSource: RemoteDataSource(
          apiClient: scan,
          inventoryApiClient: inventory,
        ),
      );
      final locations = await repository.findLocations([
        ' 260F602619008 ',
        '12324343',
        '260F602619008',
        ' ',
      ]);
      expect(locations, {'260F602619008': 'PE3-4-K4-2'});
      expect(locations.containsKey('12324343'), isFalse);
      final result = await repository.borrowRepair(
        serialNumbers: ['Q3-1-K4'],
        borrower: 'Duy PE',
        admin: 'TEST001',
      );
      expect(result.borrowed.single.serialNumber, 'Q3-1-K4');
      expect(result.borrowed.single.borrowPerson, 'Duy PE');
      expect(result.totalBorrowed, 1);
      expect(result.totalNotFound, 0);
      expect(result.totalFailed, 0);
      expect(requests.map((r) => r.url.path), [
        '/api/Inventory/FindLocations',
        '/api/Inventory/inventory-borrow-repair',
      ]);
      expect(jsonDecode(requests[0].body), ['260F602619008', '12324343']);
      expect(jsonDecode(requests[1].body), {
        'serialNumbers': ['Q3-1-K4'],
        'borrower': 'Duy PE',
        'admin': 'TEST001',
      });
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer pe-token');
        expect(request.headers['content-type'], 'application/json');
      }
    },
  );

  test(
    'scanSN posts list-scoped data and maps the complete response',
    () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test/api/Scan/',
        authTokenProvider: _Tokens(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'eventId': 101,
              'searchListId': 42,
              'serialNumber': peSnA,
              'isFound': true,
              'scannedAt': '2026-09-17T08:05:00+00:00',
              'scannedBy': 'user.a',
              'foundAt': '2026-09-17T08:00:00+00:00',
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final useCase = ManageCodesUseCase(
        repository: CodeRepositoryImpl(
          remoteDataSource: RemoteDataSource(
            apiClient: client,
            inventoryApiClient: client,
          ),
        ),
      );
      final result = await useCase.scanSerialNumber(peSnA, searchListId: 42);
      expect(result.eventId, 101);
      expect(result.searchListId, 42);
      expect(result.serialNumber, peSnA);
      expect(result.isFound, isTrue);
      expect(result.scannedAt, DateTime.utc(2026, 9, 17, 8, 5));
      expect(result.scannedBy, 'user.a');
      expect(result.foundAt, DateTime.utc(2026, 9, 17, 8));
      expect(requests.single.url.path, '/api/Scan/scanSN');
      expect(requests.single.method, 'POST');
      expect(requests.single.headers['authorization'], 'Bearer pe-token');
      expect(jsonDecode(requests.single.body), {
        'searchListId': 42,
        'serialNumber': peSnA,
      });
    },
  );

  test('scanSN accepts legacy null foundAt', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/Scan/',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'eventId': 102,
            'searchListId': 42,
            'serialNumber': peSnA,
            'isFound': true,
            'scannedAt': '2026-09-17T08:05:00+00:00',
            'scannedBy': 'user.a',
            'foundAt': null,
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    final source = RemoteDataSource(
      apiClient: client,
      inventoryApiClient: client,
    );

    final result = await source.scanSerialNumber(peSnA, searchListId: 42);

    expect(result.foundAt, isNull);
  });

  test('scanSN rejects malformed or mismatched successful responses', () async {
    const valid = {
      'eventId': 101,
      'searchListId': 42,
      'serialNumber': peSnA,
      'isFound': true,
      'scannedAt': '2026-09-17T08:05:00+00:00',
      'scannedBy': 'user.a',
      'foundAt': '2026-09-17T08:00:00+00:00',
    };
    final responses = <Object?>[
      null,
      <String, Object?>{},
      {...valid}..remove('foundAt'),
      {...valid, 'searchListId': 41},
      {...valid, 'serialNumber': peSnB},
      {...valid, 'isFound': false},
      {...valid, 'scannedAt': 'invalid'},
      {...valid, 'scannedBy': ''},
      {...valid, 'foundAt': 'invalid'},
    ];

    for (final response in responses) {
      final client = ApiClient(
        baseUrl: 'https://example.test/api/Scan/',
        client: MockClient(
          (_) async => http.Response(jsonEncode(response), 200),
        ),
      );
      final source = RemoteDataSource(
        apiClient: client,
        inventoryApiClient: client,
      );
      await expectLater(
        source.scanSerialNumber(peSnA, searchListId: 42),
        throwsA(
          isA<ServerException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
      client.close();
    }
  });

  test(
    'scanSN propagates auth and timeout failures without retrying',
    () async {
      for (final scenario in [
        (status: 403, timeout: false, kind: ApiFailureKind.forbidden),
        (status: 0, timeout: true, kind: ApiFailureKind.timeout),
      ]) {
        var calls = 0;
        final client = ApiClient(
          baseUrl: 'https://example.test/api/Scan/',
          timeout: const Duration(milliseconds: 10),
          client: MockClient((_) {
            calls++;
            if (scenario.timeout) return Completer<http.Response>().future;
            return Future.value(
              http.Response('{"message":"Forbidden"}', scenario.status),
            );
          }),
        );
        final source = RemoteDataSource(
          apiClient: client,
          inventoryApiClient: client,
        );

        await expectLater(
          source.scanSerialNumber(peSnA, searchListId: 42),
          throwsA(
            isA<ServerException>().having(
              (error) => error.kind,
              'kind',
              scenario.kind,
            ),
          ),
        );
        expect(calls, 1);
        client.close();
      }
    },
  );

  test(
    'only explicit Borrowed rows count as confirmed, including partial results',
    () {
      final result = PeInventoryMapper.borrow({
        ...peBorrowFixture,
        'success': false,
        'totalNotFound': 1,
        'totalFailed': 1,
        'borrowedResults': [
          ...(peBorrowFixture['borrowedResults'] as List),
          {'serialNumber': 'B', 'borrowStatus': 'Failed', 'borrowPerson': null},
        ],
        'notFoundSerials': ['C'],
        'failedSerials': ['B'],
      });
      expect(result.borrowed.map((r) => r.serialNumber), ['Q3-1-K4']);
      expect(result.totalNotFound, 1);
      expect(result.totalFailed, 1);
      expect(
        PeInventoryMapper.borrow({
          ...peBorrowFixture,
          'borrowedResults': [],
          'totalBorrowed': 0,
        }).borrowed,
        isEmpty,
      );
    },
  );

  test('malformed inventory responses and business rejection are errors', () {
    for (final value in <Object?>[
      null,
      [],
      {'success': true},
      {...peBorrowFixture, 'totalBorrowed': '1'},
      {
        ...peBorrowFixture,
        'borrowedResults': [
          {'serialNumber': 'A'},
        ],
      },
    ]) {
      expect(
        () => PeInventoryMapper.borrow(value),
        throwsA(isA<ServerException>()),
      );
    }
    for (final value in <Object?>[
      null,
      {'success': true},
      {
        'success': true,
        'data': [
          {'serialNumber': 'A', 'location': 1},
        ],
      },
    ]) {
      expect(
        () => PeInventoryMapper.locations(value),
        throwsA(isA<ServerException>()),
      );
    }
    expect(
      () => PeInventoryMapper.borrow({'success': false, 'message': 'Rejected'}),
      throwsA(
        isA<ServerException>().having((e) => e.message, 'message', 'Rejected'),
      ),
    );
    expect(PeInventoryMapper.locations({'success': true, 'data': []}), isEmpty);
  });

  test('HTTP errors and timeouts do not retry a loan', () async {
    for (final timeout in [false, true]) {
      var calls = 0;
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) {
          calls++;
          if (timeout) return Completer<http.Response>().future;
          return Future.value(http.Response('{"message":"Rejected"}', 409));
        }),
      );
      addTearDown(client.close);
      final source = RemoteDataSource(
        apiClient: client,
        inventoryApiClient: client,
      );
      await expectLater(
        source.borrowRepair(
          serialNumbers: ['A'],
          borrower: 'Duy PE',
          admin: 'TEST001',
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.kind,
            'kind',
            timeout ? ApiFailureKind.timeout : ApiFailureKind.conflict,
          ),
        ),
      );
      expect(calls, 1);
    }
  });
}
