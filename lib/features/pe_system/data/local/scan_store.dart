import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/code_entity.dart';
import '../../domain/entities/search_list_entity.dart';
import '../../domain/entities/scan_result.dart';

class StoredScan {
  const StoredScan({
    required this.id,
    required this.listId,
    required this.sn,
    required this.scannedAt,
    required this.localFound,
    this.state = 'pending',
    this.result,
    this.error,
  });
  final String id;
  final int listId;
  final String sn;
  final DateTime scannedAt;
  final bool localFound;
  final String state;
  final ScanResult? result;
  final String? error;
  factory StoredScan.fromRow(Map<String, Object?> row) => StoredScan(
    id: row['id'] as String,
    listId: row['list_id'] as int,
    sn: row['sn'] as String,
    scannedAt: DateTime.parse(row['scanned_at'] as String),
    localFound: row['local_found'] == 1,
    state: row['state'] as String,
    error: row['error'] as String?,
    result:
        row['result'] == null
            ? null
            : ScanCodec.resultFromJson(jsonDecode(row['result'] as String)),
  );
}

/// Durable outbox. Acknowledgement and cached found state commit together.
class ScanStore {
  ScanStore({Future<Database> Function()? open}) : _open = open ?? _openDefault;
  final Future<Database> Function() _open;
  Future<Database>? _database;
  Future<Database> get database => _database ??= _open();
  static Future<Database> _openDefault() async => openDatabase(
    '${await getDatabasesPath()}/pe_scans.db',
    version: 1,
    onCreate: (db, _) => createSchema(db),
  );
  static Future<void> createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE lists (partition TEXT PRIMARY KEY, fetched_at TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE scans (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, partition TEXT NOT NULL, list_id INTEGER NOT NULL, sn TEXT NOT NULL, scanned_at TEXT NOT NULL, local_found INTEGER NOT NULL, state TEXT NOT NULL, result TEXT, error TEXT)',
    );
    await db.execute(
      'CREATE INDEX scans_pending ON scans(partition, state, seq)',
    );
  }

  Future<void> saveLists(
    String partition,
    List<SearchListEntity> lists,
  ) async => (await database)
      .insert('lists', {
        'partition': partition,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
        'payload': jsonEncode(lists.map(ScanCodec.listToJson).toList()),
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Future<List<SearchListEntity>> loadLists(String partition) async {
    final rows = await (await database).query(
      'lists',
      where: 'partition = ?',
      whereArgs: [partition],
    );
    if (rows.isEmpty) return [];
    return (jsonDecode(rows.single['payload'] as String) as List)
        .map(ScanCodec.listFromJson)
        .toList();
  }

  Future<void> insert(String partition, StoredScan scan) async =>
      (await database)
          .insert('scans', {
            'id': scan.id,
            'partition': partition,
            'list_id': scan.listId,
            'sn': scan.sn,
            'scanned_at': scan.scannedAt.toIso8601String(),
            'local_found': scan.localFound ? 1 : 0,
            'state': 'pending',
          })
          .then((_) {});
  Future<List<StoredScan>> scans(String partition) async =>
      (await (await database).query(
        'scans',
        where: 'partition = ?',
        whereArgs: [partition],
        orderBy: 'seq',
      )).map(StoredScan.fromRow).toList();
  Future<void> fail(String partition, String id, String error) async =>
      (await database)
          .update(
            'scans',
            {'state': 'error', 'error': error},
            where: 'partition = ? AND id = ?',
            whereArgs: [partition, id],
          )
          .then((_) {});
  Future<void> acknowledge(
    String partition,
    StoredScan scan,
    ScanResult result,
  ) async {
    await (await database).transaction((txn) async {
      await txn.update(
        'scans',
        {
          'state': 'synced',
          'result': jsonEncode(ScanCodec.resultToJson(result)),
          'error': null,
        },
        where: 'partition = ? AND id = ?',
        whereArgs: [partition, scan.id],
      );
      final cached = await txn.query(
        'lists',
        where: 'partition = ?',
        whereArgs: [partition],
      );
      if (cached.isEmpty) return;
      final lists = (jsonDecode(cached.single['payload'] as String) as List)
          .map(ScanCodec.listFromJson);
      final updated = lists.map(
        (list) =>
            list.id != result.searchListId.toString()
                ? list
                : list.copyWith(
                  items:
                      list.items
                          .map(
                            (item) =>
                                item.serialNumber.trim().toUpperCase() !=
                                        result.serialNumber
                                    ? item
                                    : item.copyWith(
                                      isFound: result.isFound,
                                      foundAt: result.foundAt,
                                    ),
                          )
                          .toList(),
                ),
      );
      await txn.update(
        'lists',
        {'payload': jsonEncode(updated.map(ScanCodec.listToJson).toList())},
        where: 'partition = ?',
        whereArgs: [partition],
      );
    });
  }

  Future<void> close() async {
    if (_database != null) await (await _database!).close();
  }
}

class ScanCodec {
  static Map<String, Object?> resultToJson(ScanResult r) => {
    'id': r.eventId,
    'clientId': r.clientScanId,
    'list': r.searchListId,
    'sn': r.serialNumber,
    'found': r.isFound,
    'at': r.scannedAt.toIso8601String(),
    'by': r.scannedBy,
    'foundAt': r.foundAt?.toIso8601String(),
  };
  static ScanResult resultFromJson(dynamic r) => ScanResult(
    eventId: r['id'],
    clientScanId: r['clientId'],
    searchListId: r['list'],
    serialNumber: r['sn'],
    isFound: r['found'],
    scannedAt: DateTime.parse(r['at']),
    scannedBy: r['by'],
    foundAt: r['foundAt'] == null ? null : DateTime.parse(r['foundAt']),
  );
  static Map<String, Object?> listToJson(SearchListEntity l) => {
    'id': l.id,
    'name': l.listName,
    'at': l.createdAt.toIso8601String(),
    'by': l.createdBy,
    'hasDetails': l.hasDetails,
    'items':
        l.items
            .map(
              (i) => {
                'id': i.id,
                'sn': i.serialNumber,
                'model': i.modelName,
                'shelf': i.shelfCode,
                'column': i.columnNumber,
                'level': i.levelNumber,
                'tray': i.trayNumber,
                'position': i.positionInTray,
                'found': i.isFound,
                'order': i.foundOrder,
                'location': i.location,
                'foundAt': i.foundAt?.toIso8601String(),
              },
            )
            .toList(),
  };
  static SearchListEntity listFromJson(dynamic l) => SearchListEntity(
    id: l['id'],
    listName: l['name'],
    createdAt: DateTime.parse(l['at']),
    createdBy: l['by'],
    hasDetails: l['hasDetails'] != false,
    items:
        (l['items'] as List)
            .map(
              (i) => CodeEntity(
                id: i['id'],
                serialNumber: i['sn'],
                modelName: i['model'],
                shelfCode: i['shelf'],
                columnNumber: i['column'],
                levelNumber: i['level'],
                trayNumber: i['tray'],
                positionInTray: i['position'],
                isFound: i['found'],
                foundOrder: i['order'],
                location: i['location'],
                foundAt:
                    i['foundAt'] == null ? null : DateTime.parse(i['foundAt']),
              ),
            )
            .toList(),
  );
}
