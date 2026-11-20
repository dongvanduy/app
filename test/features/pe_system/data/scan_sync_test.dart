import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/data/local/scan_store.dart';
import 'package:mobile_app/features/pe_system/data/services/scan_sync_service.dart';
import 'package:mobile_app/features/pe_system/domain/entities/code_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/scan_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late ScanStore store;
  late ScanSyncService sync;
  var connected = false;
  var supported = true;
  late Map<String, ScanResult> server;
  late List<String> requests;
  Future<ScanResult> Function(StoredScan)? behavior;
  ScanStore openStore() => ScanStore(open: () => databaseFactoryFfi.openDatabase(
    '${directory.path}/scan.db', options: OpenDatabaseOptions(version: 1,
      onCreate: (db, _) => ScanStore.createSchema(db))));
  ScanSyncService service() => ScanSyncService(store: store, server: 'test-server',
    isConnected: () async => connected, supportsSync: () async => supported,
    upload: (scan) async {
      requests.add(scan.id);
      if (behavior != null) return behavior!(scan);
      return server.putIfAbsent(scan.id, () => result(scan, server.length + 1));
    });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scan_sync_test_');
    connected = false; supported = true; behavior = null;
    server = {}; requests = [];
    store = openStore();
    sync = service();
    await sync.bindUser(1);
    // bindUser's offline worker has no requests.
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    sync.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('offline A/B/A survives restart; retry identity and occurrence time persist', () async {
    await sync.cacheLists([list()]);
    for (final sn in ['SN1234567890', 'SN1234567891', 'SN1234567890']) {
      await sync.record(listId: 10, sn: sn, localFound: sn.endsWith('0'));
    }
    expect(sync.pendingCount, 3);
    expect(requests, isEmpty);
    final ids = sync.rows.map((r) => r.id).toList();
    final times = sync.rows.map((r) => r.scannedAt).toList();
    expect(ids.toSet().length, 3);
    expect((await sync.cachedLists()).single.items.single.isFound, isFalse);
    sync.dispose(); await store.close();
    store = openStore(); sync = service();
    await sync.bindUser(1);
    await Future<void>.delayed(Duration.zero);
    expect(sync.pendingCount, 3);
    connected = true; await sync.sync();
    expect(requests, ids);
    expect(sync.pendingCount, 0);
    expect(server.length, 3);
    expect(server.values.map((r) => r.scannedAt), times);
    expect(server.values.map((r) => r.isFound), [true, false, true]);
    expect((await sync.cachedLists()).single.items.single.isFound, isTrue);
  });

  test('commit then timeout retries same UUID without another event', () async {
    final stored = await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
    connected = true;
    behavior = (scan) async {
      server[scan.id] = result(scan, 1);
      behavior = null;
      throw const ServerException('Lost response', kind: ApiFailureKind.timeout);
    };
    await sync.sync();
    expect(sync.pendingCount, 1);
    await sync.sync(manual: true);
    expect(requests, [stored.id, stored.id]);
    expect(server.length, 1);
    expect(sync.pendingCount, 0);
  });

  test('old API capability disables POST and retries', () async {
    await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
    connected = true; supported = false;
    await sync.sync(); await sync.sync();
    expect(requests, isEmpty);
    expect(sync.pendingCount, 1);
  });

  for (final code in [401, 403]) {
    test('$code stops uploads and local intake without deleting pending data', () async {
      await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
      await sync.record(listId: 10, sn: 'SN1234567891', localFound: false);
      behavior = (_) async => throw ServerException('Denied', statusCode: code);
      connected = true; await sync.sync();
      expect(requests.length, 1);
      expect(sync.accessBlocked, isTrue);
      expect(sync.pendingCount, 2);
      await expectLater(sync.record(listId: 10, sn: 'SN1234567890', localFound: true), throwsA(isA<ServerException>()));
    });
  }

  test('permanent errors are retained and do not block unrelated scans', () async {
    await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
    await sync.record(listId: 20, sn: 'SN1234567891', localFound: false);
    behavior = (scan) async {
      if (scan.listId == 10) throw const ServerException('List deleted', statusCode: 404);
      return result(scan, 2);
    };
    connected = true; await sync.sync();
    expect(sync.rows.map((r) => r.state), ['error', 'synced']);
    await sync.sync();
    expect(requests.length, 2);
  });

  test('logout preserves outbox and ignores in-flight response until owner returns', () async {
    await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
    final gate = Completer<ScanResult>();
    behavior = (_) => gate.future;
    connected = true;
    final work = sync.sync();
    while (requests.isEmpty) { await Future<void>.delayed(Duration.zero); }
    final original = sync.rows.single;
    connected = false;
    await sync.bindUser(2);
    gate.complete(result(original, 1));
    await work;
    expect(sync.rows, isEmpty);
    await sync.bindUser(1);
    expect(sync.pendingCount, 1);
    behavior = null;
    await Future<void>.delayed(Duration.zero);
    connected = true; await sync.sync();
    expect(sync.pendingCount, 0);
  });

  test('background pauses uploads; changed server result updates local truth', () async {
    await sync.cacheLists([list()]);
    await sync.record(listId: 10, sn: 'SN1234567890', localFound: true);
    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    connected = true; await sync.sync();
    expect(requests, isEmpty);
    behavior = (scan) async => result(scan, 1, found: false);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    while (sync.isSyncing) { await Future<void>.delayed(Duration.zero); }
    expect(sync.pendingCount, 0);
    expect(sync.warning, contains('khác'));
    expect((await sync.cachedLists()).single.items.single.isFound, isFalse);
  });

  test('local insert failure sends nothing', () async {
    await store.close();
    connected = true;
    await expectLater(sync.record(listId: 10, sn: 'SN1234567890', localFound: true), throwsA(anything));
    expect(requests, isEmpty);
  });
}

ScanResult result(StoredScan scan, int id, {bool? found}) => ScanResult(eventId: id,
  clientScanId: scan.id, searchListId: scan.listId, serialNumber: scan.sn,
  isFound: found ?? scan.sn.endsWith('0'), scannedAt: scan.scannedAt, scannedBy: 'jwt-user',
  foundAt: (found ?? scan.sn.endsWith('0')) ? scan.scannedAt : null);
SearchListEntity list() => SearchListEntity(id: '10', listName: 'Cached',
  createdAt: DateTime.utc(2026, 9, 17), createdBy: 'owner', items: [
    CodeEntity(id: '1', serialNumber: 'SN1234567890', modelName: 'Model', shelfCode: 'A', isFound: false)
  ]);
