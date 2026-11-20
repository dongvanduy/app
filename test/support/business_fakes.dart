import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/domain/entities/auth_user.dart';
import 'package:mobile_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/export_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/import_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_location.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/domain/repositories/inventory_repository.dart';
import 'package:mobile_app/features/pe_system/domain/entities/code_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/scan_result.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';

const sampleUser = AuthUser(
  userId: 1,
  username: 'TEST001',
  fullName: 'Test Operator',
  role: 'Operator',
  allowedAreas: '',
  permissions: [],
  department: 'PE',
  chineseName: '',
  email: '',
  cft: '',
);
const sampleTray = TrayInfo(
  maxSlots: 2,
  occupiedCount: 2,
  occupiedPositions: [
    TrayPosition(serialNumber: 'IN-TRAY-1', positionInTray: 1),
    TrayPosition(serialNumber: 'IN-TRAY-2', positionInTray: 2),
  ],
);

class TestInventoryRepository extends Fake implements InventoryRepository {
  final exports = <({StockType type, ExportInventoryRequest request})>[];
  int trayLoads = 0;
  int imports = 0;
  TrayInfo tray = sampleTray;
  Object? exportError;
  Object? trayError;
  bool exportSuccess = true;
  Completer<TrayInfo>? trayCompleter;
  Completer<InventoryExportResult>? exportCompleter;
  @override
  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  ) async {
    trayLoads++;
    if (trayError != null) throw trayError!;
    return trayCompleter?.future ?? Future.value(tray);
  }

  @override
  Future<SerialInfo?> getSerialInfo(String serialNumber) async => SerialInfo(
    serialNumber: serialNumber,
    wipGroup: 'TEST',
    modelName: 'MODEL-1',
    productLine: 'L1',
  );
  @override
  Future<InventoryExportResult> exportInventory(
    StockType type,
    ExportInventoryRequest request,
  ) async {
    exports.add((type: type, request: request));
    if (exportError != null) throw exportError!;
    return exportCompleter?.future ??
        Future.value(
          InventoryExportResult(
            success: exportSuccess,
            message: exportSuccess ? 'Exported' : 'Rejected',
          ),
        );
  }

  @override
  Future<InventoryImportResult> importInventory(
    StockType type,
    ImportInventoryRequest request,
  ) async {
    imports++;
    return const InventoryImportResult(success: true, message: 'Imported');
  }
}

class TestAuthRepository extends Fake implements AuthRepository {
  AuthUser? user = sampleUser;
  @override
  AuthUser? get currentUser => user;
  @override
  String? get accessToken => user == null ? null : 'test-token';
  @override
  Future<AuthUser?> restoreSession() async => user;
  @override
  Future<AuthUser> login(String username, String password) async =>
      user = sampleUser;
  @override
  Future<void> logout() async => user = null;
}

class TestCodeRepository extends Fake implements CodeRepository {
  @override
  Future<Map<String, String>> findLocations(List<String> serialNumbers) async =>
      {};

  @override
  Future<List<SearchListEntity>> getSearchList() async => [
    SearchListEntity(
      id: '1',
      listName: 'Danh sách kiểm tra linh kiện dài / Long inspection list',
      createdAt: DateTime(2026),
      createdBy: 'TEST',
      items: [
        CodeEntity(
          id: '1',
          serialNumber: 'SN-012345678901234567890123456789',
          modelName: 'MODEL-0123456789',
          shelfCode: 'A',
          isFound: false,
        ),
      ],
    ),
  ];
  @override
  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  }) async => ScanResult(
    eventId: 1,
    searchListId: searchListId,
    serialNumber: serialNumber,
    isFound: true,
    scannedAt: DateTime.utc(2026, 9, 17, 8),
    scannedBy: 'TEST001',
    foundAt: DateTime.utc(2026, 9, 17, 8),
  );
}
