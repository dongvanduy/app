import 'package:mobile_app/features/repair_lookup/data/models/repair_lookup_dtos.dart';
import 'package:mobile_app/features/repair_lookup/domain/entities/repair_lookup_models.dart';
import 'package:mobile_app/features/repair_lookup/domain/repositories/repair_lookup_repository.dart';

const sampleSn = '2616V762559401';
const snInfoFixture = <String, dynamic>{
  'success': true,
  'data': {
    'sn': sampleSn,
    'wip_group': 'BLOCK-R_ICT',
    'model_name': '699-9X9OE-0301EBAN',
    'error_flag': '7',
  },
};
const testHistoryFixture = <String, dynamic>{
  'success': true,
  'data': {
    'sn': sampleSn,
    'total': 3,
    'histories': [
      {
        'id': 'R001',
        'test_group': 'ICT',
        'test_code':
            'Step=2722\nName=TTL-U190(U190)\nDevice Name=U190\nFail Pin/s number =Pin ',
        'error_desc':
            'Step=2722\nName=TTL-U190(U190)\nDevice Name=U190\nFail Pin/s number =Pin 4\nPin Name/s= Y\nNail numbers =208\nPattern Number=4 Expected Low Measured High\n\nStep=2880\nName=CHECK_DIGITAL_TEST(CHECK_DIGITAL_TEST)\nLine 21 from TPG file which corresponds to the fail\n\n',
        'error_code_item': 'U190',
        'test_time': '2026-09-03T15:42:12+07:00',
        'reason_code': 'RC53',
        'reason_desc': null,
        'memo': null,
      },
      {
        'id': 'R002',
        'test_group': 'ICT',
        'test_code':
            'Step=703\nName=C1850\nMeasured=0.807uF\nNominal=4.700uF\nDev=82.82%\nLOLIM=',
        'error_desc':
            'Step=703\nName=C1850\nMeasured=0.807uF\nNominal=4.700uF\nDev=82.82%\nLOLIM=40%= 2.82uF\nHILIM=40%= 6.58uF\nHi-Pin=1\nLo-Pin=248\nDescription=032-0863-000 TOP\n\nStep=714\nName=C1961\nMeasured=0.810uF\nNominal=4.700uF\nDev=82.78%\nLOLIM=40%= 2.82uF\nHILIM=40%= 6.58uF\nHi-Pin=1\nLo-Pin=249\nDescription=032-0863-000 TOP,\n\n',
        'error_code_item': 'N/A',
        'test_time': '2026-09-06T05:01:40+07:00',
        'reason_code': 'RC35',
        'reason_desc': null,
        'memo': null,
      },
      {
        'id': 'R003',
        'test_group': 'ICT',
        'test_code':
            'Step=703\nName=C1850\nMeasured=0.778uF\nNominal=4.700uF\nDev=83.44%\nLOLIM=',
        'error_desc':
            'Step=703\nName=C1850\nMeasured=0.778uF\nNominal=4.700uF\nDev=83.44%\nLOLIM=40%= 2.82uF\nHILIM=40%= 6.58uF\nHi-Pin=1\nLo-Pin=248\nDescription=032-0863-000 TOP\n\nStep=714\nName=C1961\nMeasured=0.782uF\nNominal=4.700uF\nDev=83.37%\nLOLIM=40%= 2.82uF\nHILIM=40%= 6.58uF\nHi-Pin=1\nLo-Pin=249\nDescription=032-0863-000 TOP,\n\n',
        'error_code_item': null,
        'test_time': '2026-09-08T08:35:24+07:00',
        'reason_code': null,
        'reason_desc': null,
        'memo': null,
      },
    ],
  },
};
const repairHistoryFixture = <String, dynamic>{
  'success': true,
  'data': {
    'sn': sampleSn,
    'total': 1,
    'histories': [
      {
        'id': 'FA001',
        'test_group': 'ICT',
        'test_time': '2026-09-06T05:01:40+07:00',
        'date3': '2026-09-06T14:45:57+07:00',
        'repairer': 'V4100523',
        'repair_action': 'retets fail đúng lỗi chờ FA TIP',
      },
    ],
  },
};

SnInfo fixtureInfo(String sn) => RepairLookupDtos.snInfo({
  ...snInfoFixture['data'] as Map<String, dynamic>,
  'sn': sn,
});
HistoryResult<TestHistoryEntry> fixtureTests(String sn) =>
    RepairLookupDtos.history(
      {...testHistoryFixture['data'] as Map<String, dynamic>, 'sn': sn},
      RepairLookupDtos.testEntry,
      (entry) => entry.testTime,
    );
HistoryResult<RepairHistoryEntry> fixtureRepairs(String sn) =>
    RepairLookupDtos.history(
      {...repairHistoryFixture['data'] as Map<String, dynamic>, 'sn': sn},
      RepairLookupDtos.repairEntry,
      (entry) => entry.eventTime,
    );

class FixtureRepairRepository implements RepairLookupRepository {
  final calls = <String>[];
  Future<SnInfo> Function(String)? onInfo;
  Future<HistoryResult<TestHistoryEntry>> Function(String)? onTests;
  Future<HistoryResult<RepairHistoryEntry>> Function(String)? onRepairs;
  @override
  Future<SnInfo> getSnInfo(String sn) async {
    calls.add('info:$sn');
    return onInfo == null ? fixtureInfo(sn) : await onInfo!(sn);
  }

  @override
  Future<HistoryResult<TestHistoryEntry>> getTestHistory(String sn) async {
    calls.add('tests:$sn');
    return onTests == null ? fixtureTests(sn) : await onTests!(sn);
  }

  @override
  Future<HistoryResult<RepairHistoryEntry>> getRepairHistory(String sn) async {
    calls.add('repairs:$sn');
    return onRepairs == null ? fixtureRepairs(sn) : await onRepairs!(sn);
  }
}
