import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';

void main() {
  test('partial success keeps only failed serial numbers', () {
    const result = InventoryImportResult(
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
    );

    final failed = result.failedResultsFor(<String>['SN1', 'SN2', 'SN3']);

    expect(failed.map((item) => item.serialNumber), <String>['SN2']);
    expect(result.successfulCountFor(<String>['SN1', 'SN2', 'SN3']), 2);
  });

  test('full request failure keeps every requested serial number', () {
    const result = InventoryImportResult(
      success: false,
      message: 'Request rejected',
    );

    final failed = result.failedResultsFor(<String>['SN1', 'SN2']);

    expect(
      failed.map((item) => item.serialNumber),
      <String>['SN1', 'SN2'],
    );
  });

  test('unreported partial result is retained for safe retry', () {
    const result = InventoryImportResult(
      success: true,
      message: 'Partial result',
      results: <ImportItemResult>[
        ImportItemResult(serialNumber: 'SN1', success: true, message: 'OK'),
      ],
    );

    final failed = result.failedResultsFor(<String>['SN1', 'SN2']);

    expect(failed.map((item) => item.serialNumber), <String>['SN2']);
  });
}
