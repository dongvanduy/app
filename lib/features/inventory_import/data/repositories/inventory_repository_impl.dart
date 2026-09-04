import '../../domain/entities/export_inventory_request.dart';
import '../../domain/entities/import_inventory_request.dart';
import '../../domain/entities/inventory_location.dart';
import '../../domain/entities/inventory_models.dart';
import '../../domain/entities/stock_type.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_data_source.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDataSource remoteDataSource;

  const InventoryRepositoryImpl({required this.remoteDataSource});

  @override
  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  ) {
    return remoteDataSource.getTrayInfo(stockType, location);
  }

  @override
  Future<SerialInfo?> getSerialInfo(String serialNumber) {
    return remoteDataSource.getSerialInfo(serialNumber);
  }

  @override
  Future<InventoryImportResult> importInventory(
    StockType stockType,
    ImportInventoryRequest request,
  ) {
    return remoteDataSource.importInventory(stockType, request);
  }

  @override
  Future<InventoryExportResult> exportInventory(
    StockType stockType,
    ExportInventoryRequest request,
  ) {
    return remoteDataSource.exportInventory(stockType, request);
  }
}
