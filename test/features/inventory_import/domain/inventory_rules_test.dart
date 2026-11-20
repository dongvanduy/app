import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/import_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/domain/services/inventory_rules.dart';

void main() {
  group('InventoryLocationParser', () {
    test('parses a full Repair location', () {
      final location = InventoryLocationParser.parse(
        'A1-2-K3',
        StockType.repair,
      );

      expect(location, isNotNull);
      expect(location!.shelf, 'A');
      expect(location.column, 1);
      expect(location.level, 2);
      expect(location.tray, 3);
      expect(location.normalized, 'A1-2-K3');
    });

    test('parses and normalizes a Repair location without level', () {
      final location = InventoryLocationParser.parse(
        'A1-K3',
        StockType.repair,
      );

      expect(location, isNotNull);
      expect(location!.shelf, 'A');
      expect(location.column, 1);
      expect(location.level, 0);
      expect(location.tray, 3);
      expect(location.normalized, 'A1-0-K3');
    });

    test('keeps Repair shelf F0 separate from shelf F in API requests', () {
      final f0 = InventoryLocationParser.parse('F02-1-K3', StockType.repair)!;
      final f = InventoryLocationParser.parse('F2-1-K3', StockType.repair)!;

      expect(f0.shelf, 'F0');
      expect(f.shelf, 'F');
      expect(f0.column, 2);
      expect(f.column, 2);
      expect(f0.normalized, 'F02-1-K3');
      expect(f.normalized, 'F2-1-K3');
      expect(f0.toQueryParameters(), <String, Object>{
        'shelf': 'F0',
        'column': 2,
        'level': 1,
        'tray': 3,
      });
      expect(f.toQueryParameters()['shelf'], 'F');
      expect(
        ImportInventoryRequest.fromLocation(
          location: f0,
          serialNumbers: <String>['SN-F0'],
        ).toJson(),
        <String, dynamic>{
          'Shelf': 'F0',
          'Column': 2,
          'Level': 1,
          'Tray': 3,
          'SerialNumbers': <String>['SN-F0'],
        },
      );
    });

    test('normalizes Repair F0 locations with and without level', () {
      for (final (input, column, level, normalized) in <(String, int, int, String)>[
        ('F02-K3', 2, 0, 'F02-0-K3'),
        ('F012-1-K3', 12, 1, 'F012-1-K3'),
        ('F012-K3', 12, 0, 'F012-0-K3'),
        ('  f02-1-k3  ', 2, 1, 'F02-1-K3'),
        ('  f02-k3  ', 2, 0, 'F02-0-K3'),
      ]) {
        final location = InventoryLocationParser.parse(input, StockType.repair);

        expect(location, isNotNull, reason: input);
        expect(location!.shelf, 'F0', reason: input);
        expect(location.column, column, reason: input);
        expect(location.level, level, reason: input);
        expect(location.tray, 3, reason: input);
        expect(location.normalized, normalized, reason: input);
      }
    });

    test('preserves F02 parsing for Scrap and OK stock', () {
      for (final stockType in <StockType>[StockType.scrap, StockType.ok]) {
        for (final (input, level, normalized) in <(String, int, String)>[
          ('F02-1-K3', 1, 'F2-1-K3'),
          ('F02-K3', 0, 'F2-0-K3'),
        ]) {
          final location = InventoryLocationParser.parse(input, stockType);

          expect(location, isNotNull);
          expect(location!.shelf, 'F');
          expect(location.column, 2);
          expect(location.level, level);
          expect(location.tray, 3);
          expect(location.normalized, normalized);
        }
      }
    });

    test('rejects incomplete Repair F0 locations', () {
      for (final input in <String>[
        'F0',
        'F02',
        'F02-1',
        'F02-K',
        'F02-1-K',
        'F02-1-K3-extra',
      ]) {
        expect(
          InventoryLocationParser.parse(input, StockType.repair),
          isNull,
          reason: input,
        );
      }
    });

    test('parses Scrap CARTON locations', () {
      final first = InventoryLocationParser.parse(
        'CARTON-1',
        StockType.scrap,
      );
      final hundred = InventoryLocationParser.parse(
        'CARTON-100',
        StockType.scrap,
      );

      expect(first, isNotNull);
      expect(first!.shelf, 'CARTON');
      expect(first.column, 1);
      expect(first.level, 0);
      expect(first.tray, 0);
      expect(hundred, isNotNull);
      expect(hundred!.column, 100);
    });

    test('rejects CARTON for non-Scrap stock', () {
      expect(
        InventoryLocationParser.parse('CARTON-1', StockType.repair),
        isNull,
      );
      expect(
        InventoryLocationParser.parse('CARTON-1', StockType.ok),
        isNull,
      );
    });

    test('rejects incomplete and invalid locations', () {
      for (final input in <String>[
        'A',
        'A1',
        'A1-2',
        'A1-K',
        'A1-2-K',
        'ABC',
        'CARTON',
        'CARTON-',
      ]) {
        expect(
          InventoryLocationParser.parse(input, StockType.scrap),
          isNull,
          reason: '$input must be invalid',
        );
      }
    });
  });

  group('SerialNumberParser', () {
    test('trims, uppercases, and removes empty lines', () {
      const input = 'sn001\n\n SN002\nsn003';

      expect(
        SerialNumberParser.parse(input),
        <String>['SN001', 'SN002', 'SN003'],
      );
    });

    test('preserves duplicates for validation', () {
      expect(
        SerialNumberParser.parse('SN001\nSN002\nSN001'),
        <String>['SN001', 'SN002', 'SN001'],
      );
    });
  });

  group('InventoryValidation', () {
    test('detects duplicates inside input', () {
      final duplicates = InventoryValidation.duplicateSerials(
        <String>['SN001', 'SN002', 'SN001'],
      );

      expect(duplicates, contains('SN001'));
      expect(duplicates, hasLength(1));
    });

    test('detects duplicates against occupied tray positions', () {
      const tray = TrayInfo(
        maxSlots: 30,
        occupiedCount: 2,
        occupiedPositions: <TrayPosition>[
          TrayPosition(serialNumber: 'SN010'),
          TrayPosition(serialNumber: 'SN020'),
        ],
      );

      final duplicates = InventoryValidation.duplicateSerialsInTray(
        <String>['SN001', 'SN010'],
        tray,
      );

      expect(duplicates, <String>{'SN010'});
    });

    test('detects over-capacity and allows exact capacity', () {
      final tray = TrayInfo(
        maxSlots: 30,
        occupiedCount: 28,
        occupiedPositions: List<TrayPosition>.generate(
          28,
          (index) => TrayPosition(serialNumber: 'SN${index + 1}'),
        ),
      );

      expect(InventoryValidation.capacityAfterImport(tray, 3), 31);
      expect(InventoryValidation.isOverCapacity(tray, 3), isTrue);
      expect(InventoryValidation.capacityAfterImport(tray, 2), 30);
      expect(InventoryValidation.isOverCapacity(tray, 2), isFalse);
    });
  });
}
