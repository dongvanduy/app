class TrayPosition {
  final String serialNumber;
  final int? positionInTray;
  final String? location;

  const TrayPosition({
    required this.serialNumber,
    this.positionInTray,
    this.location,
  });
}

class TrayInfo {
  final int maxSlots;
  final int occupiedCount;
  final List<TrayPosition> occupiedPositions;

  const TrayInfo({
    required this.maxSlots,
    required this.occupiedCount,
    required this.occupiedPositions,
  });

  int get actualOccupiedCount => occupiedPositions.length;
}

class SerialInfo {
  final String serialNumber;
  final String? wipGroup;
  final String? modelName;
  final String? productLine;

  const SerialInfo({
    required this.serialNumber,
    this.wipGroup,
    this.modelName,
    this.productLine,
  });
}

class ImportItemResult {
  final String serialNumber;
  final bool success;
  final String message;

  const ImportItemResult({
    required this.serialNumber,
    required this.success,
    required this.message,
  });
}

class InventoryImportResult {
  final bool success;
  final String message;
  final List<ImportItemResult> results;
  final List<String> invalidSerials;

  const InventoryImportResult({
    required this.success,
    required this.message,
    this.results = const <ImportItemResult>[],
    this.invalidSerials = const <String>[],
  });

  List<ImportItemResult> failedResultsFor(List<String> requestedSerials) {
    if (results.isEmpty) {
      if (success) {
        return const <ImportItemResult>[];
      }
      return requestedSerials
          .map(
            (serial) => ImportItemResult(
              serialNumber: serial,
              success: false,
              message: message,
            ),
          )
          .toList(growable: false);
    }

    final normalizedResults = <String, ImportItemResult>{
      for (final result in results)
        result.serialNumber.trim().toUpperCase(): result,
    };

    return <ImportItemResult>[
      for (final serial in requestedSerials)
        if (normalizedResults[serial]?.success != true)
          normalizedResults[serial] ??
              ImportItemResult(
                serialNumber: serial,
                success: false,
                message: 'No result was returned for this serial number.',
              ),
    ];
  }

  int successfulCountFor(List<String> requestedSerials) {
    return requestedSerials.length - failedResultsFor(requestedSerials).length;
  }
}

class InventoryExportResult {
  final bool success;
  final String message;

  const InventoryExportResult({
    required this.success,
    required this.message,
  });
}
