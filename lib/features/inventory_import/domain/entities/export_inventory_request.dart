import 'inventory_location.dart';
import 'stock_type.dart';

class ExportInventoryRequest {
  final String? shelf;
  final int? column;
  final int? level;
  final int? tray;
  final List<String> serialNumbers;

  ExportInventoryRequest({
    required String this.shelf,
    required int this.column,
    required int this.level,
    required int this.tray,
    required List<String> serialNumbers,
  }) : serialNumbers = List.unmodifiable(serialNumbers);

  ExportInventoryRequest.fromSerialNumbers({
    required List<String> serialNumbers,
  }) : shelf = null,
       column = null,
       level = null,
       tray = null,
       serialNumbers = List.unmodifiable(serialNumbers);

  factory ExportInventoryRequest.fromLocation({
    required InventoryLocation location,
    required List<String> serialNumbers,
  }) => ExportInventoryRequest(
    shelf: location.shelf,
    column: location.column,
    level: location.level,
    tray: location.tray,
    serialNumbers: serialNumbers,
  );

  Map<String, dynamic> toJson() => {
    if (shelf != null) ...{
      'Shelf': shelf,
      'Column': column,
      'Level': level,
      'Tray': tray,
    },
    'SerialNumbers': serialNumbers,
  };
}

/// Immutable selection shared by the confirmation dialog and the API request.
class InventoryExportSelection {
  const InventoryExportSelection({
    required this.stockType,
    required this.location,
    required this.fromInput,
    required this.request,
  });
  final StockType stockType;
  final InventoryLocation? location;
  final bool fromInput;
  final ExportInventoryRequest request;
  List<String> get serialNumbers => request.serialNumbers;
}
