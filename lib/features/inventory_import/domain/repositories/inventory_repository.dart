import '../entities/export_inventory_request.dart';
import '../entities/import_inventory_request.dart';
import '../entities/inventory_location.dart';
import '../entities/inventory_models.dart';
import '../entities/stock_type.dart';

abstract interface class InventoryRepository {
  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  );

  Future<SerialInfo?> getSerialInfo(String serialNumber);

  Future<InventoryImportResult> importInventory(
    StockType stockType,
    ImportInventoryRequest request,
  );

  Future<InventoryExportResult> exportInventory(
    StockType stockType,
    ExportInventoryRequest request,
  );
}
