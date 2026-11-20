import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/presentation/models/scan_outcome.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pe_system/domain/entities/borrow_repair_result.dart';
import 'package:mobile_app/features/pe_system/domain/entities/code_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/scan_result.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/code_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (_) async => 'wifi');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  testWidgets(
    'rescan keeps one found item and sends the newly selected list ID',
    (tester) async {
      final repository = _CodeRepository();
      final provider = CodeProvider(
        useCase: ManageCodesUseCase(repository: repository),
        connectivity: Connectivity(),
      );
      addTearDown(provider.dispose);

      await provider.fetchSearchList();
      provider.setSelectedSearchListIndex(0);

      expect((await provider.handleScanCode(' sn1234567890 ')).isFound, isTrue);
      expect(provider.foundCount, 1);
      await tester.pump(const Duration(seconds: 2));

      expect((await provider.handleScanCode('SN1234567890')).isFound, isTrue);
      expect(provider.foundCount, 1);

      await tester.pump(const Duration(seconds: 2));
      provider.setSelectedSearchListIndex(1);
      expect((await provider.handleScanCode('SN1234567890')).isFound, isTrue);
      expect(provider.foundCount, 1);
      expect(repository.scanListIds, <int>[10, 10, 20]);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  Future<CodeProvider> readyProvider(_CodeRepository repository) async {
    final provider = CodeProvider(
      useCase: ManageCodesUseCase(repository: repository),
      connectivity: Connectivity(),
    );
    addTearDown(provider.dispose);
    await provider.fetchSearchList();
    provider.setSelectedSearchListIndex(0);
    return provider;
  }

  testWidgets('busy input rejects scans and cooldown starts after response', (
    tester,
  ) async {
    final repository = _CodeRepository();
    final provider = await readyProvider(repository);
    final gate = Completer<ScanResult>();
    repository.onScan = (_, _) => gate.future;
    final first = provider.handleScanCode('SN1234567890');
    expect(
      (await provider.handleScanCode('SN1234567891')).status,
      ScanOutcomeStatus.failed,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(provider.canSubmitScan, isFalse);
    provider.setSelectedSearchListIndex(1);
    expect(provider.selectedSearchListId, '10');
    gate.complete(_foundResult());
    expect((await first).isFound, isTrue);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(provider.canSubmitScan, isFalse);
    expect(provider.createBorrowBatch(), isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(provider.canSubmitScan, isTrue);
    expect(repository.scanListIds, [10]);
    expect(provider.createBorrowBatch(), isNotNull);
  });

  for (final status in [401, 403]) {
    testWidgets('$status blocks further scans after cooldown', (tester) async {
      final repository = _CodeRepository();
      final provider = await readyProvider(repository);
      repository.onScan =
          (_, _) async =>
              throw ServerException('Access denied', statusCode: status);
      expect((await provider.handleScanCode('SN1234567890')).isFound, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(provider.canSubmitScan, isFalse);
      expect(provider.foundCount, 0);
      expect(repository.scanListIds, [10]);
    });
  }

  for (final kind in [
    ApiFailureKind.network,
    ApiFailureKind.timeout,
    ApiFailureKind.invalidResponse,
    ApiFailureKind.server,
  ]) {
    testWidgets('$kind does not mark found or auto retry legacy request', (
      tester,
    ) async {
      final repository = _CodeRepository();
      final provider = await readyProvider(repository);
      repository.onScan =
          (_, _) async => throw ServerException('Failed', kind: kind);
      expect((await provider.handleScanCode('SN1234567890')).isFound, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(provider.canSubmitScan, isTrue);
      expect(provider.foundCount, 0);
      expect(repository.scanListIds, [10]);
    });
  }

  test('logout ignores the in-flight response', () async {
    final repository = _CodeRepository();
    final provider = await readyProvider(repository);
    final gate = Completer<ScanResult>();
    repository.onScan = (_, _) => gate.future;
    final first = provider.handleScanCode('SN1234567890');
    provider.resetSessionState();
    gate.complete(_foundResult());
    expect((await first).status, ScanOutcomeStatus.cancelled);
    expect(provider.foundCount, 0);
    expect(provider.isBusy, isFalse);
  });

  test('invalid SN is rejected without entering the queue', () async {
    final repository = _CodeRepository();
    final provider = await readyProvider(repository);
    expect(
      (await provider.handleScanCode('BAD')).status,
      ScanOutcomeStatus.failed,
    );
    expect(repository.scanListIds, isEmpty);
    expect(provider.isScanning, isFalse);
  });

  testWidgets('borrow confirms the requested FG when Product stores a different SFG', (
    tester,
  ) async {
    final repository = _CodeRepository();
    final provider = CodeProvider(
      useCase: ManageCodesUseCase(repository: repository),
      connectivity: Connectivity(),
    );
    addTearDown(provider.dispose);

    await provider.fetchSearchList();
    provider.setSelectedSearchListIndex(0);
    expect((await provider.handleScanCode('SN1234567890')).isFound, isTrue);
    await tester.pump(const Duration(seconds: 2));
    final batch = provider.createBorrowBatch();

    final result = await provider.borrowFoundCodes(
      batch: batch!,
      borrower: 'borrower',
    );

    expect(result?.totalBorrowed, 1);
    expect(repository.borrowRequests, <List<String>>[
      <String>['SN1234567890'],
    ]);
    expect(provider.borrowerFor('SN1234567890'), 'jwt-user');
    expect(provider.borrowableSerialNumbers, isEmpty);
  });
}

ScanResult _foundResult() => ScanResult(
  eventId: 900,
  searchListId: 10,
  serialNumber: 'SN1234567890',
  isFound: true,
  scannedAt: DateTime.utc(2026, 9, 22),
  scannedBy: 'scan.test',
  foundAt: DateTime.utc(2026, 9, 22),
);

class _CodeRepository implements CodeRepository {
  final scanListIds = <int>[];
  final scanSerials = <String>[];
  Future<ScanResult> Function(String, int)? onScan;
  final borrowRequests = <List<String>>[];
  var _eventId = 800;

  @override
  Future<List<SearchListEntity>> getSearchList() async {
    return <SearchListEntity>[_list('10', 'List 10'), _list('20', 'List 20')];
  }

  @override
  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) async {
    final lists = await getSearchList();
    return SearchListPage(
      page: page,
      pageSize: pageSize,
      totalLists: lists.length,
      totalPages: (lists.length + pageSize - 1) ~/ pageSize,
      lists: lists.skip((page - 1) * pageSize).take(pageSize).toList(),
    );
  }

  @override
  Future<SearchListEntity> getSearchListDetails(int searchListId) async =>
      (await getSearchList()).firstWhere(
        (list) => list.id == searchListId.toString(),
      );
  @override
  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  }) async {
    scanListIds.add(searchListId);
    scanSerials.add(serialNumber);
    if (onScan != null) return onScan!(serialNumber, searchListId);
    final scannedAt = DateTime.utc(2026, 9, 19, 12, _eventId - 800);
    return ScanResult(
      eventId: _eventId++,
      searchListId: searchListId,
      serialNumber: serialNumber,
      isFound: serialNumber == 'SN1234567890',
      scannedAt: scannedAt,
      scannedBy: 'V3201425',
      foundAt:
          serialNumber == 'SN1234567890' ? DateTime.utc(2026, 9, 19, 12) : null,
    );
  }

  @override
  Future<Map<String, String>> findLocations(List<String> serialNumbers) async {
    return <String, String>{};
  }

  @override
  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
  }) async {
    borrowRequests.add(List<String>.of(serialNumbers));
    return BorrowRepairResult(
      borrowed: <BorrowedSerial>[
        for (final serialNumber in serialNumbers)
          BorrowedSerial(
            serialNumber: 'SFG-IN-PRODUCT',
            requestedSerialNumber: serialNumber.toLowerCase(),
            borrowPerson: 'jwt-user',
          ),
      ],
      totalBorrowed: serialNumbers.length,
      totalNotFound: 0,
      totalFailed: 0,
    );
  }

  @override
  Future<bool> checkCode(String serialNumber) {
    throw UnimplementedError();
  }

  @override
  Future<List<CodeEntity>> getCodeList() {
    throw UnimplementedError();
  }

  SearchListEntity _list(String id, String name) {
    return SearchListEntity(
      id: id,
      listName: name,
      createdAt: DateTime.utc(2026, 9, 19),
      createdBy: 'tester',
      items: <CodeEntity>[
        CodeEntity(
          id: '$id-1',
          serialNumber: 'SN1234567890',
          modelName: 'MODEL',
          shelfCode: 'A',
          isFound: false,
        ),
      ],
    );
  }
}
