import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/inventory_import/data/datasources/inventory_remote_data_source.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/export_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/domain/services/inventory_rules.dart';
import 'package:mobile_app/features/inventory_import/presentation/providers/inventory_import_provider.dart';
import '../../support/business_fakes.dart';

void main() {
  group('export wire contract', () {
    test('SN-only JSON omits every location field and freezes the list', () {
      final serials = ['SN1'];
      final request = ExportInventoryRequest.fromSerialNumbers(
        serialNumbers: serials,
      );
      serials.add('SN2');
      expect(request.toJson(), {
        'SerialNumbers': ['SN1'],
      });
      expect(() => request.serialNumbers.add('SN3'), throwsUnsupportedError);
    });
    test('location factory includes all four location fields', () {
      final location =
          InventoryLocationParser.parse('a1-2-k3', StockType.repair)!;
      final request = ExportInventoryRequest.fromLocation(
        location: location,
        serialNumbers: ['SN1'],
      );
      expect(request.toJson(), {
        'Shelf': 'A',
        'Column': 1,
        'Level': 2,
        'Tray': 3,
        'SerialNumbers': ['SN1'],
      });
    });
    for (final type in StockType.values) {
      for (final withLocation in [false, true]) {
        test(
          '${type.name}: endpoint and JSON, location=$withLocation',
          () async {
            final request =
                withLocation
                    ? ExportInventoryRequest.fromLocation(
                      location: InventoryLocationParser.parse('A1-2-K3', type)!,
                      serialNumbers: ['SN1'],
                    )
                    : ExportInventoryRequest.fromSerialNumbers(
                      serialNumbers: ['SN1'],
                    );
            final client = MockClient((incoming) async {
              expect(incoming.method, 'POST');
              expect(
                incoming.url.path,
                '/api/Inventory/export-inventory-${type.name}',
              );
              expect(jsonDecode(incoming.body), request.toJson());
              return http.Response(
                '{"success":true,"message":"Exported"}',
                200,
              );
            });
            addTearDown(client.close);
            final source = InventoryRemoteDataSource(
              inventoryApiClient: ApiClient(
                baseUrl: 'https://example.test/api/',
                client: client,
              ),
            );
            expect(
              (await source.exportInventory(type, request)).success,
              isTrue,
            );
          },
        );
      }
    }
  });
  group('export selection and submission', () {
    late TestInventoryRepository repository;
    late InventoryImportProvider provider;
    setUp(() {
      repository = TestInventoryRepository();
      provider = InventoryImportProvider(repository: repository);
    });
    tearDown(() => provider.dispose());

    for (final type in StockType.values) {
      test(
        '${type.name} exports normalized entered SNs without location',
        () async {
          provider.selectStockType(type);
          provider.updateSerialInput(' sn1 \r\n\nSn2 ');
          expect(provider.canSubmit, isFalse);
          expect(provider.canExport, isTrue);
          final selection = provider.prepareExport()!;
          expect(selection.fromInput, isTrue);
          expect(await provider.exportInventory(selection), isTrue);
          expect(repository.exports.single.type, type);
          expect(repository.exports.single.request.toJson(), {
            'SerialNumbers': ['SN1', 'SN2'],
          });
          expect(repository.trayLoads, 0);
        },
      );
    }
    test('empty, whitespace and duplicate input cannot export', () {
      for (final value in ['', ' \n\r ', ' sn1\nSN1 ']) {
        provider.updateSerialInput(value);
        expect(provider.canExport, isFalse);
        expect(provider.prepareExport(), isNull);
      }
      expect(repository.exports, isEmpty);
    });
    test('malformed nonempty location must be fixed or cleared', () {
      provider.updateSerialInput('SN1');
      provider.updateLocation('bad-location');
      expect(provider.canExport, isFalse);
      provider.updateLocation('  ');
      expect(provider.canExport, isTrue);
      provider.updateLocation('A1-2-K3');
      expect(provider.canExport, isTrue);
    });
    test(
      'entered SNs take priority and are exportable from a full tray',
      () async {
        provider.updateLocation('A1-2-K3');
        await provider.refreshTray();
        provider.updateSerialInput('in-tray-1\nEXTERNAL');
        expect(provider.isTrayFull, isTrue);
        expect(provider.isOverCapacity, isTrue);
        expect(provider.trayDuplicateSerials, contains('IN-TRAY-1'));
        expect(provider.canSubmit, isFalse);
        expect(provider.canExport, isTrue);
        final selection = provider.prepareExport()!;
        expect(selection.serialNumbers, ['IN-TRAY-1', 'EXTERNAL']);
        expect(selection.fromInput, isTrue);
        expect(await provider.exportInventory(selection), isTrue);
        expect(
          repository.exports.single.request.serialNumbers,
          selection.serialNumbers,
        );
      },
    );
    for (final type in [StockType.repair, StockType.scrap]) {
      test(
        '${type.name} falls back to every normalized SN in the loaded tray',
        () async {
          provider.selectStockType(type);
          provider.updateLocation(
            type == StockType.scrap ? 'CARTON-1' : 'A1-2-K3',
          );
          await provider.refreshTray();
          final selection = provider.prepareExport()!;
          expect(selection.fromInput, isFalse);
          expect(selection.serialNumbers, ['IN-TRAY-1', 'IN-TRAY-2']);
          expect(await provider.exportInventory(selection), isTrue);
          expect(repository.trayLoads, 2);
        },
      );
    }
    test('OK never falls back to tray or requests tray refresh', () async {
      provider.selectStockType(StockType.ok);
      provider.updateLocation('A1-2-K3');
      expect(provider.canExport, isFalse);
      provider.updateSerialInput('SN1');
      expect(await provider.exportTray(), isTrue);
      expect(repository.trayLoads, 0);
      expect(repository.exports.single.request.shelf, 'A');
    });
    test('a tray with no valid SN cannot be exported', () async {
      repository.tray = const TrayInfo(
        maxSlots: 20,
        occupiedCount: 0,
        occupiedPositions: [],
      );
      provider.updateLocation('A1-2-K3');
      await provider.refreshTray();
      expect(provider.canExport, isFalse);
    });
    test('entered SN export does not wait for a tray lookup', () async {
      repository.trayCompleter = Completer<TrayInfo>();
      provider.updateLocation('A1-2-K3');
      final loading = provider.refreshTray();
      expect(provider.loadingTray, isTrue);
      expect(provider.canExport, isFalse);
      provider.updateSerialInput('SN1');
      expect(provider.canExport, isTrue);
      final selection = provider.prepareExport()!;
      repository.trayCompleter!.complete(sampleTray);
      await loading;
      repository.trayCompleter = null;
      expect(await provider.exportInventory(selection), isTrue);
    });
    test(
      'confirmed snapshot retains SNs, type and location after form changes',
      () async {
        provider.updateLocation('A1-2-K3');
        provider.updateSerialInput('SN1\nSN2');
        final selection = provider.prepareExport()!;
        provider.selectStockType(StockType.ok);
        provider.updateSerialInput('DIFFERENT');
        provider.updateLocation('');
        expect(await provider.exportInventory(selection), isTrue);
        final sent = repository.exports.single;
        expect(sent.type, StockType.repair);
        expect(sent.request.toJson(), {
          'Shelf': 'A',
          'Column': 1,
          'Level': 2,
          'Tray': 3,
          'SerialNumbers': ['SN1', 'SN2'],
        });
        expect(repository.trayLoads, 0);
      },
    );
    test('cancelled and unprepared snapshots cannot submit', () async {
      provider.updateSerialInput('SN1');
      final selection = provider.prepareExport()!;
      provider.cancelExport(selection);
      expect(await provider.exportInventory(selection), isFalse);
      final forged = InventoryExportSelection(
        stockType: StockType.ok,
        location: null,
        fromInput: true,
        request: ExportInventoryRequest.fromSerialNumbers(
          serialNumbers: ['SN'],
        ),
      );
      expect(await provider.exportInventory(forged), isFalse);
      expect(repository.exports, isEmpty);
    });
    test(
      'pending request prevents duplicates and the same confirmation cannot be reused',
      () async {
        provider.updateSerialInput('SN1');
        final selection = provider.prepareExport()!;
        repository.exportCompleter = Completer<InventoryExportResult>();
        final first = provider.exportInventory(selection);
        expect(provider.busy, isTrue);
        expect(provider.canSubmit, isFalse);
        expect(provider.canExport, isFalse);
        expect(await provider.exportInventory(selection), isFalse);
        provider.updateSerialInput('CHANGED');
        expect(provider.serialNumbers, ['SN1']);
        repository.exportCompleter!.complete(
          const InventoryExportResult(success: true, message: 'Exported'),
        );
        expect(await first, isTrue);
        expect(await provider.exportInventory(selection), isFalse);
        expect(repository.exports, hasLength(1));
      },
    );
    for (final failure in [
      const ServerException('Server rejected'),
      StateError('Network failure'),
      null,
    ]) {
      test('export failure retains inputs: $failure', () async {
        provider.updateSerialInput('SN1');
        provider.updateLocation('A1-2-K3');
        repository.exportError = failure;
        repository.exportSuccess = false;
        expect(await provider.exportTray(), isFalse);
        expect(provider.serialInput, 'SN1');
        expect(provider.locationInput, 'A1-2-K3');
        expect(provider.error, isNotNull);
        expect(provider.warning, isNull);
        expect(provider.busy, isFalse);
      });
    }
    test('refresh failure is a warning after a successful export', () async {
      provider.updateSerialInput('SN1');
      provider.updateLocation('A1-2-K3');
      repository.trayError = StateError('Refresh failed');
      expect(await provider.exportTray(), isTrue);
      expect(provider.error, isNull);
      expect(provider.operationSummary, 'Exported');
      expect(provider.warning, 'inventory_export_refresh_warning');
      expect(repository.exports, hasLength(1));
    });
    test('import still requires a valid location', () async {
      provider.updateSerialInput('SN1');
      await provider.submit();
      expect(repository.imports, 0);
      expect(provider.error, isNotNull);
    });
  });
}
