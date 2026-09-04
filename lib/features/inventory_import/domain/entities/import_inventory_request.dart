import 'inventory_location.dart';

class ImportInventoryRequest {
  final String shelf;
  final int column;
  final int level;
  final int tray;
  final List<String> serialNumbers;

  const ImportInventoryRequest({
    required this.shelf,
    required this.column,
    required this.level,
    required this.tray,
    required this.serialNumbers,
  });

  factory ImportInventoryRequest.fromLocation({
    required InventoryLocation location,
    required List<String> serialNumbers,
  }) {
    return ImportInventoryRequest(
      shelf: location.shelf,
      column: location.column,
      level: location.level,
      tray: location.tray,
      serialNumbers: List<String>.unmodifiable(serialNumbers),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'Shelf': shelf,
        'Column': column,
        'Level': level,
        'Tray': tray,
        'SerialNumbers': serialNumbers,
      };
}
