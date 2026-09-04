enum StockType { repair, scrap, ok }

extension StockTypeConfig on StockType {
  String get displayName => switch (this) {
        StockType.repair => 'Repair',
        StockType.scrap => 'Scrap',
        StockType.ok => 'OK',
      };

  String get apiKey => switch (this) {
        StockType.repair => 'Repair',
        StockType.scrap => 'Scrap',
        StockType.ok => 'Ok',
      };

  String get importPath => switch (this) {
        StockType.repair => 'Inventory/input-inventory-repair',
        StockType.scrap => 'Inventory/input-inventory-scrap',
        StockType.ok => 'Inventory/input-inventory-ok',
      };

  String get exportPath => switch (this) {
        StockType.repair => 'Inventory/export-inventory-repair',
        StockType.scrap => 'Inventory/export-inventory-scrap',
        StockType.ok => 'Inventory/export-inventory-ok',
      };

  String? get trayPath => switch (this) {
        StockType.repair => 'Inventory/get-info-tray-repair',
        StockType.scrap => 'Inventory/get-info-tray-scrap',
        StockType.ok => null,
      };

  bool get supportsTray => trayPath != null;

  bool get supportsTrayExport => supportsTray;
}
