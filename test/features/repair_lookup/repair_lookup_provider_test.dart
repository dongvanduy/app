import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/repair_lookup/domain/entities/repair_lookup_models.dart';
import 'package:mobile_app/features/repair_lookup/presentation/providers/repair_lookup_provider.dart';
import '../../support/repair_lookup_fixtures.dart';

void main() {
  late FixtureRepairRepository repository;
  late RepairLookupProvider provider;
  setUp(() {
    repository = FixtureRepairRepository();
    provider = RepairLookupProvider(repository: repository);
  });
  tearDown(() => provider.dispose());

  test(
    'idle has no calls, trims serial and tab switching never refetches',
    () async {
      expect(repository.calls, isEmpty);
      expect(provider.info.status, LookupStatus.idle);
      await provider.lookup(' \r\n ');
      expect(repository.calls, isEmpty);
      await provider.lookup(' $sampleSn\r\n');
      expect(provider.sn, sampleSn);
      expect(repository.calls.length, 3);
      expect(provider.info.status, LookupStatus.success);
      provider.selectTab(HistoryTab.repair);
      expect(repository.calls.length, 3);
      await provider.lookup(sampleSn);
      expect(repository.calls.length, 6);
    },
  );

  test(
    'all requests start immediately and sections complete independently',
    () async {
      final info = Completer<SnInfo>();
      final tests = Completer<HistoryResult<TestHistoryEntry>>();
      final repairs = Completer<HistoryResult<RepairHistoryEntry>>();
      repository.onInfo = (_) => info.future;
      repository.onTests = (_) => tests.future;
      repository.onRepairs = (_) => repairs.future;
      final lookup = provider.lookup(sampleSn);
      expect(repository.calls.length, 3);
      await provider.lookup(sampleSn);
      expect(repository.calls.length, 3);
      info.complete(fixtureInfo(sampleSn));
      await Future<void>.delayed(Duration.zero);
      expect(provider.info.status, LookupStatus.success);
      expect(provider.tests.status, LookupStatus.loading);
      tests.completeError(
        const ServerException('timeout', kind: ApiFailureKind.timeout),
      );
      repairs.complete(fixtureRepairs(sampleSn));
      await lookup;
      expect(provider.tests.status, LookupStatus.error);
      expect(provider.repairs.data!.histories.single.id, 'FA001');
      repository.onTests = null;
      await provider.retryTests();
      expect(provider.tests.status, LookupStatus.success);
      expect(repository.calls, [
        'info:$sampleSn',
        'tests:$sampleSn',
        'repairs:$sampleSn',
        'tests:$sampleSn',
      ]);
    },
  );

  test('older success and failure cannot replace a newer lookup', () async {
    final oldInfo = Completer<SnInfo>();
    final oldTests = Completer<HistoryResult<TestHistoryEntry>>();
    final oldRepairs = Completer<HistoryResult<RepairHistoryEntry>>();
    repository.onInfo =
        (sn) => sn == 'A' ? oldInfo.future : Future.value(fixtureInfo(sn));
    repository.onTests =
        (sn) => sn == 'A' ? oldTests.future : Future.value(fixtureTests(sn));
    repository.onRepairs =
        (sn) =>
            sn == 'A' ? oldRepairs.future : Future.value(fixtureRepairs(sn));
    final old = provider.lookup('A');
    await provider.lookup('B');
    oldInfo.complete(fixtureInfo('A'));
    oldTests.completeError(const ServerException('old failure'));
    oldRepairs.complete(fixtureRepairs('A'));
    await old;
    expect(provider.sn, 'B');
    expect(provider.info.data!.sn, 'B');
    expect(provider.tests.data!.sn, 'B');
    expect(provider.tests.status, LookupStatus.success);
    expect(provider.repairs.data!.sn, 'B');
  });

  test('retry result is ignored after serial changes', () async {
    repository.onTests =
        (_) async => throw const ServerException('first failure');
    await provider.lookup('A');
    final retry = Completer<HistoryResult<TestHistoryEntry>>();
    repository.onTests =
        (sn) => sn == 'A' ? retry.future : Future.value(fixtureTests(sn));
    final loading = provider.retryTests();
    await provider.retryTests();
    expect(repository.calls.where((c) => c == 'tests:A').length, 2);
    await provider.lookup('B');
    retry.completeError(const ServerException('old retry'));
    await loading;
    expect(provider.tests.data!.sn, 'B');
  });

  test(
    'empty is successful history with no records, info error remains separate',
    () async {
      repository.onInfo =
          (_) async =>
              throw const ServerException(
                'forbidden',
                kind: ApiFailureKind.forbidden,
              );
      repository.onTests =
          (sn) async => HistoryResult(sn: sn, total: 0, histories: []);
      await provider.lookup(sampleSn);
      expect(provider.info.status, LookupStatus.error);
      expect(provider.tests.status, LookupStatus.empty);
      expect(provider.repairs.status, LookupStatus.success);
    },
  );

  test(
    'dispose prevents notifications from pending successes and failures',
    () async {
      final info = Completer<SnInfo>();
      final tests = Completer<HistoryResult<TestHistoryEntry>>();
      repository.onInfo = (_) => info.future;
      repository.onTests = (_) => tests.future;
      final detached = RepairLookupProvider(repository: repository);
      var notifications = 0;
      detached.addListener(() => notifications++);
      final lookup = detached.lookup(sampleSn);
      detached.dispose();
      final before = notifications;
      info.complete(fixtureInfo(sampleSn));
      tests.completeError(const ServerException('late error'));
      await lookup;
      expect(notifications, before);
    },
  );
}
