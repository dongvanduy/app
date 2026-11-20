import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/domain/entities/borrow_repair_result.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/code_provider.dart';
import '../../../../support/pe_inventory_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PeTestRepository repository;
  late CodeProvider provider;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => 'wifi',
        );
    repository = PeTestRepository();
    provider = CodeProvider(
      useCase: ManageCodesUseCase(repository: repository),
      connectivity: Connectivity(),
    );
  });
  tearDown(() => provider.dispose());
  Future<void> select([int index = 0]) async {
    await provider.fetchSearchList();
    provider.setSelectedSearchListIndex(index);
    await Future<void>.delayed(Duration.zero);
  }

  Future<BorrowRepairResult?> lend(String name) => provider.borrowFoundCodes(
    batch: provider.createBorrowBatch()!,
    borrower: name,
    admin: ' TEST001 ',
  );

  test(
    'locations never mark found; API isFound and nullable location are preserved',
    () async {
      repository.lists = [
        peList('1', [peSnA, peSnB], found: {peSnB}),
      ];
      await select();
      expect(provider.codeList.first.location, 'PE3-4-K4-2');
      expect(provider.codeList.first.isFound, isFalse);
      expect(provider.foundCodes, [peSnB]);
      expect(provider.borrowableSerialNumbers, [peSnB]);
      expect(provider.codeList.first.copyWith(location: null).location, isNull);
      expect(
        provider.codeList.first.copyWith(isFound: true).location,
        'PE3-4-K4-2',
      );
    },
  );

  test(
    'serials sort naturally by location with missing locations last',
    () async {
      repository.lists = [
        peList('1', ['NO-LOCATION', 'S-10', 'S-2', 'S-K5', 'S-K10', 'S-K2']),
      ];
      repository.locations = {
        'S-10': 'A1-2-K4',
        'S-2': 'A1-2-K4',
        'S-K5': 'A1-2-K5',
        'S-K10': 'A1-2-K10',
        'S-K2': 'A1-10-K2',
      };

      await select();

      expect(provider.codeList.map((item) => item.serialNumber), [
        'S-2',
        'S-10',
        'S-K5',
        'S-K10',
        'S-K2',
        'NO-LOCATION',
      ]);
    },
  );

  test(
    'scan uses selected list ID, not dropdown index, including after sync',
    () async {
      repository.lists = [
        peList('41', [peSnA, peSnB]),
        peList('73', [peSnA, peSnB]),
      ];
      await select();
      expect(await provider.handleScanCode(' $peSnA '), isTrue);
      provider.setSelectedSearchListIndex(1);
      expect(await provider.handleScanCode(peSnA.toLowerCase()), isTrue);
      repository.lists = repository.lists.reversed.toList();
      await provider.fetchSearchList();
      expect(provider.selectedSearchListIndex, 0);
      expect(await provider.handleScanCode(peSnB), isTrue);
      expect(repository.scanRequests, [
        (searchListId: 41, serialNumber: peSnA),
        (searchListId: 73, serialNumber: peSnA),
        (searchListId: 73, serialNumber: peSnB),
      ]);
    },
  );

  test(
    'every valid rescan posts an event without duplicating found state',
    () async {
      await select();
      final firstFoundAt = DateTime.utc(2026, 9, 17, 8);
      repository.scanFoundAt = firstFoundAt;

      expect(await provider.handleScanCode(peSnA), isTrue);
      expect(await provider.handleScanCode(peSnA), isTrue);

      expect(repository.scanRequests, [
        (searchListId: 1, serialNumber: peSnA),
        (searchListId: 1, serialNumber: peSnA),
      ]);
      expect(provider.foundCount, 1);
      expect(
        provider.codeList
            .singleWhere((item) => item.serialNumber == peSnA)
            .foundAt,
        firstFoundAt,
      );

      repository.scanFoundAt = null;
      expect(await provider.handleScanCode(peSnB), isTrue);
      expect(
        provider.codeList
            .singleWhere((item) => item.serialNumber == peSnB)
            .foundAt,
        isNull,
      );
    },
  );

  test(
    'validates normalized serial length and positive list ID before POST',
    () async {
      repository.lists = [
        peList('1', [peSnA, 'SN000000000001']),
      ];
      await select();
      for (final serial in [
        '',
        '12345678901',
        '1234567890123',
        '123456789012345',
      ]) {
        expect(await provider.handleScanCode(serial), isFalse);
      }
      expect(repository.scanRequests, isEmpty);
      expect(await provider.handleScanCode(' sn000000000001 '), isTrue);
      expect(repository.scanRequests.single.serialNumber, 'SN000000000001');
    },
  );

  test(
    'confirmed scan reloads a missing cached item without posting twice',
    () async {
      repository.listResponses.addAll([
        [
          peList('1', [peSnA]),
        ],
        [
          peList('1', [peSnA, peUnknownSn]),
        ],
      ]);
      await select();

      expect(await provider.handleScanCode(peUnknownSn), isTrue);

      expect(repository.scanRequests, [
        (searchListId: 1, serialNumber: peUnknownSn),
      ]);
      expect(repository.listLoads, 2);
      expect(provider.foundCodes, contains(peUnknownSn));
    },
  );

  test(
    'confirmed scan reports stale cache when reload still lacks the item',
    () async {
      repository.lists = [
        peList('1', [peSnA]),
      ];
      await select();

      expect(await provider.handleScanCode(peUnknownSn), isFalse);

      expect(repository.scanRequests, [
        (searchListId: 1, serialNumber: peUnknownSn),
      ]);
      expect(repository.listLoads, 2);
      expect(provider.error, contains('Đã ghi nhận scan'));
      expect(provider.foundCount, 0);
    },
  );

  test(
    'scan API errors keep state unchanged and show actionable messages',
    () async {
      await select();
      repository.scanError = const ServerException(
        'Not found',
        statusCode: 404,
        kind: ApiFailureKind.notFound,
        responseData: {'code': 'SERIAL_NOT_IN_SEARCH_LIST'},
      );
      expect(await provider.handleScanCode(peSnA), isFalse);
      expect(provider.error, 'SN $peSnA không nằm trong danh sách đã chọn.');
      expect(provider.foundCount, 0);

      for (final entry in [
        (
          ApiFailureKind.unauthorized,
          'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.',
        ),
        (
          ApiFailureKind.forbidden,
          'Bạn không có quyền quét SN trong danh sách này.',
        ),
        (ApiFailureKind.timeout, 'Timeout'),
      ]) {
        repository.scanError = ServerException('Timeout', kind: entry.$1);
        expect(await provider.handleScanCode(peSnA), isFalse);
        expect(provider.error, entry.$2);
        expect(provider.foundCount, 0);
      }
    },
  );

  for (final id in ['', 'invalid-id', '0', '-1']) {
    test(
      'invalid search list ID "$id" never sends or marks a scan found',
      () async {
        repository.lists = [
          peList(id, [peSnA]),
        ];
        await select();
        expect(await provider.handleScanCode(peSnA), isFalse);
        expect(repository.scanRequests, isEmpty);
        expect(provider.foundCount, 0);
        expect(provider.error, contains('ID'));
      },
    );
  }

  test(
    'two batches skip loans; rescans, switching and reordered refresh preserve session',
    () async {
      await select();
      await provider.handleScanCode(' $peSnA ');
      await provider.handleScanCode(peSnB);
      await lend(' First ');
      expect(repository.loans.single.serials.toSet(), {peSnA, peSnB});
      expect(repository.loans.single.borrower, 'First');
      expect(repository.loans.single.admin, 'TEST001');
      await provider.handleScanCode(peSnA);
      expect(provider.foundCount, 2);
      expect(provider.borrowerFor(peSnA), 'First');
      await provider.handleScanCode(peSnC);
      await lend('Second');
      expect(repository.loans.last.serials, [peSnC]);
      expect(provider.foundCount, 3);
      expect(provider.createBorrowBatch(), isNull);
      provider.setSelectedSearchListIndex(1);
      expect(provider.borrowerFor(peSnA), isNull);
      await provider.handleScanCode(peSnA);
      expect(provider.borrowableSerialNumbers, [peSnA]);
      provider.setSelectedSearchListIndex(0);
      expect(provider.borrowerFor(peSnA), 'First');
      repository.lists = repository.lists.reversed.toList();
      await provider.fetchSearchList();
      expect(provider.selectedSearchListIndex, 1);
      expect(provider.foundCount, 3);
      expect(provider.borrowerFor(peSnC), 'Second');
      expect(provider.borrowableSerialNumbers, isEmpty);
    },
  );

  test(
    'partial confirmation ignores unsubmitted rows and falls back to typed borrower',
    () async {
      await select();
      for (final sn in [peSnA, peSnB, peSnC]) {
        await provider.handleScanCode(sn);
      }
      repository.borrowResult = peBorrowResult(
        [peSnA, 'FOREIGN'],
        person: '',
        notFound: 1,
        failed: 1,
      );
      await lend(' Duy ');
      expect(provider.borrowerFor(peSnA), 'Duy');
      expect(provider.borrowerFor('FOREIGN'), isNull);
      expect(provider.borrowableSerialNumbers.toSet(), {peSnB, peSnC});
      repository.borrowResult = peBorrowResult([], failed: 2);
      await lend('Other');
      expect(provider.borrowableSerialNumbers.toSet(), {peSnB, peSnC});
    },
  );

  test(
    'scan rejection and loan failure never advance state; empty input never sends',
    () async {
      await select();
      repository.scanSuccess = false;
      expect(await provider.handleScanCode(peSnA), isFalse);
      expect(provider.foundCount, 0);
      expect(await provider.handleScanCode('SHORT'), isFalse);
      repository.scanSuccess = true;
      await provider.handleScanCode(peSnA);
      final batch = provider.createBorrowBatch()!;
      await expectLater(
        provider.borrowFoundCodes(batch: batch, borrower: ' ', admin: 'TEST'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        provider.borrowFoundCodes(batch: batch, borrower: 'Duy', admin: ' '),
        throwsA(isA<ValidationException>()),
      );
      expect(repository.loans, isEmpty);
      repository.borrowError = const ServerException(
        'timeout',
        kind: ApiFailureKind.timeout,
      );
      await expectLater(lend('Duy'), throwsA(isA<ServerException>()));
      expect(provider.borrowerFor(peSnA), isNull);
      expect(provider.isBusy, isFalse);
      expect(provider.borrowableSerialNumbers, [peSnA]);
    },
  );

  test(
    'fixed batch excludes later scans and blocks concurrent mutation while sending',
    () async {
      await select();
      await provider.handleScanCode(peSnA);
      final batch = provider.createBorrowBatch()!;
      await provider.handleScanCode(peSnB);
      repository.borrowCompleter = Completer<BorrowRepairResult>();
      final pending = provider.borrowFoundCodes(
        batch: batch,
        borrower: 'Duy',
        admin: 'TEST',
      );
      expect(provider.isSubmittingBorrow, isTrue);
      expect(
        await provider.borrowFoundCodes(
          batch: batch,
          borrower: 'Duy',
          admin: 'TEST',
        ),
        isNull,
      );
      expect(await provider.handleScanCode(peSnC), isFalse);
      provider.setSelectedSearchListIndex(1);
      final loads = repository.listLoads;
      await provider.fetchSearchList();
      expect(repository.listLoads, loads);
      expect(provider.selectedSearchListIndex, 0);
      expect(repository.loans.single.serials, [peSnA]);
      repository.borrowCompleter!.complete(peBorrowResult([peSnA]));
      await pending;
      expect(provider.borrowableSerialNumbers, [peSnB]);
    },
  );

  test(
    'late location response merges with latest scan/loan, failure keeps location, retry clears absent',
    () async {
      repository.locationCompleter = Completer<Map<String, String>>();
      await select();
      expect(provider.isLoadingLocations, isTrue);
      await provider.handleScanCode(peSnA);
      await lend('Duy');
      repository.locationCompleter!.complete({peSnA: 'NEW'});
      await Future<void>.delayed(Duration.zero);
      expect(provider.codeList.first.location, 'NEW');
      expect(provider.codeList.first.isFound, isTrue);
      expect(provider.borrowerFor(peSnA), 'Duy');
      repository.locationCompleter = null;
      repository.locationError = const ServerException('offline');
      await provider.refreshLocations();
      expect(provider.codeList.first.location, 'NEW');
      expect(provider.locationError, isNotNull);
      expect(provider.isLoadingLocations, isFalse);
      repository.locationError = null;
      repository.locations = {};
      await provider.refreshLocations();
      expect(provider.codeList.first.location, isNull);
      expect(provider.locationError, isNull);
    },
  );

  test(
    'out-of-order location requests cannot overwrite latest location or other list',
    () async {
      await select();
      final old = Completer<Map<String, String>>();
      repository.locationCompleter = old;
      final older = provider.refreshLocations();
      final fresh = Completer<Map<String, String>>();
      repository.locationCompleter = fresh;
      final newer = provider.refreshLocations();
      fresh.complete({peSnA: 'LATEST'});
      await newer;
      old.complete({peSnA: 'STALE'});
      await older;
      expect(provider.codeList.first.location, 'LATEST');
      final background = Completer<Map<String, String>>();
      repository.locationCompleter = background;
      final pending = provider.refreshLocations();
      repository.locationCompleter = null;
      provider.setSelectedSearchListIndex(1);
      background.complete({peSnA: 'LIST-1'});
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(provider.selectedSearchListId, '2');
      expect(provider.codeList.first.location, 'PE3-4-K4-2');
    },
  );

  test(
    'logout invalidates pending loan and old batch; refresh keeps new session empty',
    () async {
      await select();
      await provider.handleScanCode(peSnA);
      final batch = provider.createBorrowBatch()!;
      repository.borrowCompleter = Completer<BorrowRepairResult>();
      final pending = lend('Duy');
      provider.resetSessionState();
      repository.borrowCompleter!.complete(peBorrowResult([peSnA]));
      expect(await pending, isNull);
      expect(provider.codeList, isEmpty);
      expect(provider.isBusy, isFalse);
      repository.borrowCompleter = null;
      await select();
      expect(provider.foundCount, 0);
      expect(provider.borrowerFor(peSnA), isNull);
      expect(
        await provider.borrowFoundCodes(
          batch: batch,
          borrower: 'Duy',
          admin: 'TEST',
        ),
        isNull,
      );
    },
  );

  test(
    'confirmed API-found loan stays found after server refresh changes isFound',
    () async {
      repository.lists = [
        peList('1', [peSnA], found: {peSnA}),
      ];
      await select();
      await lend('Duy');
      repository.lists = [
        peList('1', [peSnA]),
      ];
      await provider.fetchSearchList();
      expect(provider.foundCount, 1);
      expect(provider.borrowerFor(peSnA), 'Duy');
      expect(provider.borrowableSerialNumbers, isEmpty);
    },
  );

  test(
    'refresh removing all SNs clears an older location loading state',
    () async {
      repository.locationCompleter = Completer<Map<String, String>>();
      await select();
      expect(provider.isLoadingLocations, isTrue);
      repository.lists = [peList('1', [])];
      await provider.fetchSearchList();
      expect(provider.isLoadingLocations, isFalse);
      repository.locationCompleter!.complete({peSnA: 'OLD'});
      await Future<void>.delayed(Duration.zero);
      expect(provider.codeList, isEmpty);
      expect(provider.isLoadingLocations, isFalse);
    },
  );

  test('logout ignores pending list, scan and location responses', () async {
    repository.listCompleter = Completer<List<SearchListEntity>>();
    final loading = provider.fetchSearchList();
    await Future<void>.delayed(Duration.zero);
    provider.resetSessionState();
    repository.listCompleter!.complete(repository.lists);
    await loading;
    expect(provider.searchLists, isEmpty);
    repository.listCompleter = null;
    await select();
    repository.scanCompleter = Completer<bool>();
    final scanning = provider.handleScanCode(peSnA);
    provider.resetSessionState();
    repository.scanCompleter!.complete(true);
    expect(await scanning, isFalse);
    expect(provider.foundCodes, isEmpty);
    repository.scanCompleter = null;
    repository.locationCompleter = Completer<Map<String, String>>();
    await select();
    provider.resetSessionState();
    repository.locationCompleter!.complete({peSnA: 'OLD'});
    await Future<void>.delayed(Duration.zero);
    expect(provider.codeList, isEmpty);
    expect(provider.isLoadingLocations, isFalse);
  });
}
