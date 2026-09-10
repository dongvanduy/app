import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/repair_lookup/data/datasources/repair_lookup_remote_data_source.dart';
import 'package:mobile_app/features/repair_lookup/data/models/repair_lookup_dtos.dart';
import 'package:mobile_app/features/repair_lookup/data/repositories/repair_lookup_repository_impl.dart';
import 'package:mobile_app/features/repair_lookup/presentation/widgets/lookup_widgets.dart';
import '../../support/repair_lookup_fixtures.dart';

void main() {
  test(
    'three sample responses preserve fields, log text, IDs and timezone',
    () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test/api/Scan/',
        client: MockClient((request) async {
          requests.add(request);
          final fixture = switch (request.url.pathSegments.last) {
            'sn-info' => snInfoFixture,
            'test-history' => testHistoryFixture,
            _ => repairHistoryFixture,
          };
          return http.Response(
            jsonEncode(fixture),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final repository = RepairLookupRepositoryImpl(
        remoteDataSource: RepairLookupRemoteDataSource(apiClient: client),
      );
      final info = await repository.getSnInfo(sampleSn);
      final tests = await repository.getTestHistory(sampleSn);
      final repairs = await repository.getRepairHistory(sampleSn);
      expect(info.sn, sampleSn);
      expect(info.wipGroup, 'BLOCK-R_ICT');
      expect(info.modelName, '699-9X9OE-0301EBAN');
      expect(info.errorFlag, '7');
      expect(tests.total, 3);
      expect(tests.histories.map((e) => e.id), ['R001', 'R002', 'R003']);
      expect(tests.histories[0].reasonCode, 'RC53');
      expect(tests.histories[1].reasonCode, 'RC35');
      expect(tests.histories[2].reasonCode, isNull);
      expect(tests.histories[1].errorCodeItem, 'N/A');
      expect(tests.histories[2].errorCodeItem, isNull);
      expect(
        tests.histories[0].errorDesc,
        (testHistoryFixture['data']['histories'][0])['error_desc'],
      );
      expect(tests.histories[1].errorDesc, contains('\nName=C1961\n'));
      expect(tests.histories[2].errorDesc, contains('Measured=0.782uF'));
      expect(repairs.histories.single.repairer, 'V4100523');
      expect(
        repairs.histories.single.repairAction,
        'retets fail đúng lỗi chờ FA TIP',
      );
      expect(
        formatLookupTime(repairs.histories.single.testTime),
        '06/09/2026 05:01:40',
      );
      expect(
        formatLookupTime(repairs.histories.single.date3),
        '06/09/2026 14:45:57',
      );
      expect(requests.map((r) => r.method), everyElement('GET'));
      expect(requests.map((r) => r.url.path), [
        '/api/Scan/sn-info',
        '/api/Scan/test-history',
        '/api/Scan/repair-history',
      ]);
      expect(
        requests.map((r) => r.url.queryParameters),
        everyElement({'sn': sampleSn}),
      );
    },
  );

  test(
    'query serial is encoded as one value and optional fields can be absent',
    () async {
      const sn = 'SN +/#?&';
      final client = ApiClient(
        baseUrl: 'https://example.test/api/Scan/',
        client: MockClient((request) async {
          expect(request.url.queryParameters, {'sn': sn});
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'sn': sn},
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final result = await RepairLookupRemoteDataSource(
        apiClient: client,
      ).getSnInfo(sn);
      expect(result.modelName, isNull);
      expect(lookupValue(result.modelName), '—');
      expect(lookupValue('N/A'), 'N/A');
    },
  );

  for (final response in [
    {
      'success': true,
      'data': {'sn': 'WRONG'},
    },
    {'success': true, 'data': null},
    {
      'data': {'sn': sampleSn},
    },
    {
      'success': true,
      'data': {'sn': sampleSn, 'total': 3, 'histories': null},
    },
    {
      'success': true,
      'data': {
        'sn': sampleSn,
        'total': 1,
        'histories': [
          {'id': 42},
        ],
      },
    },
  ]) {
    test('rejects malformed history or mismatched SN: $response', () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/',
        client: MockClient(
          (_) async => http.Response(jsonEncode(response), 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        RepairLookupRemoteDataSource(
          apiClient: client,
        ).getTestHistory(sampleSn),
        throwsA(
          isA<ServerException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test(
    'success false preserves business message instead of reporting empty',
    () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'message': 'SN unavailable'}),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        RepairLookupRemoteDataSource(apiClient: client).getSnInfo(sampleSn),
        throwsA(
          isA<ServerException>()
              .having((e) => e.kind, 'kind', ApiFailureKind.business)
              .having((e) => e.message, 'message', 'SN unavailable'),
        ),
      );
    },
  );

  test('sorting respects offsets, equal timestamps and missing dates', () {
    final result = RepairLookupDtos.history(
      {
        'sn': sampleSn,
        'total': 7,
        'histories': [
          {'id': 'invalid', 'test_time': 'invalid'},
          {'id': 'late', 'test_time': '2026-09-06T06:00:00Z'},
          {'id': 'equal-first', 'test_time': '2026-09-06T05:00:00+07:00'},
          {'id': 'early', 'test_time': '2026-09-05T21:00:00Z'},
          {'id': 'equal-second', 'test_time': '2026-09-05T22:00:00Z'},
          {'id': 'unzoned', 'test_time': '2026-09-06T05:00:00'},
        ],
      },
      RepairLookupDtos.testEntry,
      (entry) => entry.testTime,
    );
    expect(result.histories.map((e) => e.id), [
      'early',
      'equal-first',
      'equal-second',
      'late',
      'invalid',
      'unzoned',
    ]);
    expect(result.total, 7);
    expect(result.histories.length, 6);
    expect(formatLookupTime(result.histories.last.testTime), '—');
  });

  test('repairs use date3 then fall back to test time', () {
    final result = RepairLookupDtos.history(
      {
        'sn': sampleSn,
        'total': 3,
        'histories': [
          {
            'id': 'b',
            'test_time': '2026-09-01T01:00:00Z',
            'date3': '2026-09-03T01:00:00Z',
          },
          {'id': 'c'},
          {'id': 'a', 'test_time': '2026-09-02T01:00:00Z', 'date3': null},
        ],
      },
      RepairLookupDtos.repairEntry,
      (entry) => entry.eventTime,
    );
    expect(result.histories.map((e) => e.id), ['a', 'b', 'c']);
  });
}
