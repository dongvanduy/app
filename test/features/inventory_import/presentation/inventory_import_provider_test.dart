import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/export_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/import_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_location.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/domain/repositories/inventory_repository.dart';
import 'package:mobile_app/features/inventory_import/presentation/providers/inventory_import_provider.dart';

void main() {
  test('partial import keeps inputs until the result is acknowledged',
      () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Partial success',
        results: <ImportItemResult>[
          ImportItemResult(serialNumber: 'SN1', success: true, message: 'OK'),
          ImportItemResult(
            serialNumber: 'SN2',
            success: false,
            message: 'Serial already exists',
          ),
          ImportItemResult(serialNumber: 'SN3', success: true, message: 'OK'),
        ],
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.updateLocation('A1-2-K3');
    provider.updateSerialInput('SN1\nSN2\nSN3');
    await provider.submit();

    expect(provider.locationInput, 'A1-2-K3');
    expect(provider.serialNumbers, <String>['SN1', 'SN2', 'SN3']);
    expect(provider.serialInput, 'SN1\nSN2\nSN3');
    expect(provider.failedImportResults.single.serialNumber, 'SN2');
    expect(provider.operationSummary, contains('2/3'));

    provider.clearForm();

    expect(provider.locationInput, isEmpty);
    expect(provider.serialInput, isEmpty);
    expect(provider.serialNumbers, isEmpty);
    expect(provider.failedImportResults, isEmpty);
    expect(provider.operationSummary, isNull);
  });

  test('OK import never requests tray information', () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Completed',
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.selectStockType(StockType.ok);
    provider.updateLocation('A1-K3');
    provider.updateSerialInput('SN1');
    await provider.submit();

    expect(repository.trayRequestCount, 0);
    expect(repository.importRequestCount, 1);
    expect(provider.serialNumbers, <String>['SN1']);

    provider.clearForm();
    expect(provider.serialNumbers, isEmpty);
  });

  test('loading a tray also loads WIP Group and Model Name for its SNs',
      () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Completed',
      ),
      trayInfo: const TrayInfo(
        maxSlots: 30,
        occupiedCount: 1,
        occupiedPositions: <TrayPosition>[
          TrayPosition(serialNumber: 'SN-001', positionInTray: 1),
        ],
      ),
      serialInfoBySn: const <String, SerialInfo?>{
        'SN-001': SerialInfo(
          serialNumber: 'SN-001',
          wipGroup: 'B30M',
          modelName: '699-9D4B4-0400QS1N',
          productLine: 'HAMILTON',
        ),
      },
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.updateLocation('A1-2-K3');
    await provider.refreshTray();
    await Future<void>.delayed(Duration.zero);

    expect(repository.serialInfoRequests, <String>['SN-001']);
    expect(provider.serialDetails['SN-001']?.wipGroup, 'B30M');
    expect(
      provider.serialDetails['SN-001']?.modelName,
      '699-9D4B4-0400QS1N',
    );
  });

  test('SN lookup exposes HTTP errors and does not cache them as not found',
      () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Completed',
      ),
      trayInfo: const TrayInfo(
        maxSlots: 30,
        occupiedCount: 1,
        occupiedPositions: <TrayPosition>[
          TrayPosition(serialNumber: 'SN-001', positionInTray: 1),
        ],
      ),
      serialInfoError: const ServerException(
        'The requested resource was not found.',
        statusCode: 404,
        kind: ApiFailureKind.notFound,
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.updateLocation('A1-2-K3');
    await provider.refreshTray();
    await Future<void>.delayed(Duration.zero);

    expect(provider.serialDetails.containsKey('SN-001'), isFalse);
    expect(provider.serialLookupErrors['SN-001'], 'HTTP 404');
    expect(provider.loadingSerialDetails, isFalse);
  });

  test('exports the occupied serials from a loaded tray', () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Completed',
      ),
      trayInfo: const TrayInfo(
        maxSlots: 30,
        occupiedCount: 2,
        occupiedPositions: <TrayPosition>[
          TrayPosition(serialNumber: 'SN-001', positionInTray: 1),
          TrayPosition(serialNumber: 'SN-002', positionInTray: 2),
        ],
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    expect(provider.canExport, isFalse);
    provider.updateLocation('A1-2-K3');
    await provider.refreshTray();

    expect(provider.canExport, isTrue);
    expect(await provider.exportTray(), isTrue);
    expect(repository.exportRequestCount, 1);
    expect(repository.lastExportRequest?.shelf, 'A');
    expect(repository.lastExportRequest?.column, 1);
    expect(repository.lastExportRequest?.level, 2);
    expect(repository.lastExportRequest?.tray, 3);
    expect(
      repository.lastExportRequest?.serialNumbers,
      <String>['SN-001', 'SN-002'],
    );
    expect(provider.operationSummary, 'Export completed');
  });

  test('failed export preserves the loaded tray for retry', () async {
    final repository = _FakeInventoryRepository(
      importResult: const InventoryImportResult(
        success: true,
        message: 'Completed',
      ),
      exportResult: const InventoryExportResult(
        success: false,
        message: 'Export rejected',
      ),
      trayInfo: const TrayInfo(
        maxSlots: 30,
        occupiedCount: 1,
        occupiedPositions: <TrayPosition>[
          TrayPosition(serialNumber: 'SN-001', positionInTray: 1),
        ],
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);

    provider.updateLocation('A1-2-K3');
    await provider.refreshTray();

    expect(await provider.exportTray(), isFalse);
    expect(provider.error, 'Export rejected');
    expect(provider.locationInput, 'A1-2-K3');
    expect(provider.trayInfo?.occupiedPositions, hasLength(1));
    expect(provider.canExport, isTrue);
  });
}

class _FakeInventoryRepository implements InventoryRepository {
  final InventoryImportResult importResult;
  final InventoryExportResult exportResult;
  final TrayInfo trayInfo;
  final Map<String, SerialInfo?> serialInfoBySn;
  final Object? serialInfoError;
  int trayRequestCount = 0;
  int importRequestCount = 0;
  int exportRequestCount = 0;
  ExportInventoryRequest? lastExportRequest;
  final List<String> serialInfoRequests = <String>[];

  _FakeInventoryRepository({
    required this.importResult,
    this.exportResult = const InventoryExportResult(
      success: true,
      message: 'Export completed',
    ),
    this.trayInfo = const TrayInfo(
      maxSlots: 30,
      occupiedCount: 0,
      occupiedPositions: <TrayPosition>[],
    ),
    this.serialInfoBySn = const <String, SerialInfo?>{},
    this.serialInfoError,
  });

  @override
  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  ) async {
    trayRequestCount++;
    return trayInfo;
  }

  @override
  Future<SerialInfo?> getSerialInfo(String serialNumber) async {
    serialInfoRequests.add(serialNumber);
    if (serialInfoError != null) {
      throw serialInfoError!;
    }
    return serialInfoBySn[serialNumber];
  }

  @override
  Future<InventoryImportResult> importInventory(
    StockType stockType,
    ImportInventoryRequest request,
  ) async {
    importRequestCount++;
    return importResult;
  }

  @override
  Future<InventoryExportResult> exportInventory(
    StockType stockType,
    ExportInventoryRequest request,
  ) async {
    exportRequestCount++;
    lastExportRequest = request;
    return exportResult;
  }
}
