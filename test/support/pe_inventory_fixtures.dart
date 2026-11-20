import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/domain/entities/borrow_repair_result.dart';
import 'package:mobile_app/features/pe_system/domain/entities/code_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/scan_result.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';

const peLocationsFixture = {
  'success': true,
  'data': [
    {
      'serialNumber': '260F602619008',
      'warehouse': 'Product',
      'location': 'PE3-4-K4-2',
      'productLine': '',
      'modelName': '',
    },
  ],
  'totalFound': 1,
  'totalNotFound': 1,
  'notFoundSerialNumbers': ['12324343'],
};

const peSnA = 'SN0000000001';
const peSnB = 'SN0000000002';
const peSnC = 'SN0000000003';
const peSnD = 'SN0000000004';
const peUnknownSn = 'SN9999999999';

const peBorrowFixture = {
  'success': true,
  'totalBorrowed': 1,
  'totalNotFound': 0,
  'totalFailed': 0,
  'borrowedResults': [
    {
      'serialNumber': 'Q3-1-K4',
      'borrowStatus': 'Borrowed',
      'borrowDate': '2026-09-11T14:03:20.5460648+07:00',
      'borrowPerson': 'Duy PE',
    },
  ],
  'notFoundSerials': [],
  'failedSerials': [],
};

SearchListEntity peList(
  String id,
  List<String> serials, {
  Set<String> found = const {},
}) => SearchListEntity(
  id: id,
  listName: 'List $id',
  createdAt: DateTime(2026),
  createdBy: 'TEST',
  items: [
    for (final sn in serials)
      CodeEntity(
        id: '$id-$sn',
        serialNumber: sn,
        modelName: 'MODEL',
        shelfCode: 'OLD',
        isFound: found.contains(sn),
      ),
  ],
);

BorrowRepairResult peBorrowResult(
  List<String> serials, {
  String? person = 'Duy PE',
  int notFound = 0,
  int failed = 0,
}) => BorrowRepairResult(
  borrowed: [
    for (final sn in serials)
      BorrowedSerial(serialNumber: sn, borrowPerson: person),
  ],
  totalBorrowed: serials.length,
  totalNotFound: notFound,
  totalFailed: failed,
);

class PeTestRepository extends Fake implements CodeRepository {
  List<SearchListEntity> lists = [
    peList('1', [peSnA, peSnB, peSnC]),
    peList('2', [peSnA, peSnD]),
  ];
  Map<String, String> locations = {peSnA: 'PE3-4-K4-2'};
  int listLoads = 0;
  final listResponses = <List<SearchListEntity>>[];
  final locationCalls = <List<String>>[];
  final scans = <String>[];
  final scanRequests = <({int searchListId, String serialNumber})>[];
  final loans = <({List<String> serials, String borrower, String admin})>[];
  bool scanSuccess = true;
  DateTime? scanFoundAt = DateTime.utc(2026, 9, 17, 8);
  Object? scanError;
  Object? locationError;
  Object? borrowError;
  Completer<List<SearchListEntity>>? listCompleter;
  Completer<Map<String, String>>? locationCompleter;
  Completer<bool>? scanCompleter;
  Completer<BorrowRepairResult>? borrowCompleter;
  BorrowRepairResult? borrowResult;

  @override
  Future<List<SearchListEntity>> getSearchList() async {
    listLoads++;
    if (listCompleter != null) return listCompleter!.future;
    if (listResponses.isNotEmpty) return listResponses.removeAt(0);
    return lists;
  }

  @override
  Future<Map<String, String>> findLocations(List<String> serialNumbers) async {
    locationCalls.add(List.of(serialNumbers));
    if (locationError != null) throw locationError!;
    return locationCompleter?.future ?? locations;
  }

  @override
  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  }) async {
    scans.add(serialNumber);
    scanRequests.add((searchListId: searchListId, serialNumber: serialNumber));
    if (scanError != null) {
      throw scanError!;
    }
    if (scanCompleter != null) {
      final success = await scanCompleter!.future;
      if (!success) {
        throw const ServerException('Không thể ghi nhận mã đã quét');
      }
    } else if (!scanSuccess) {
      throw const ServerException('Không thể ghi nhận mã đã quét');
    }
    return ScanResult(
      eventId: scanRequests.length,
      searchListId: searchListId,
      serialNumber: serialNumber,
      isFound: true,
      scannedAt: DateTime.utc(2026, 9, 17, 8, scanRequests.length),
      scannedBy: 'TEST001',
      foundAt: scanFoundAt,
    );
  }

  @override
  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
    required String admin,
  }) {
    loans.add((
      serials: List.of(serialNumbers),
      borrower: borrower,
      admin: admin,
    ));
    if (borrowError != null) throw borrowError!;
    return borrowCompleter?.future ??
        borrowResult ??
        peBorrowResult(serialNumbers, person: borrower);
  }
}
