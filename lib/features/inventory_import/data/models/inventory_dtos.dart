import '../../domain/entities/inventory_models.dart';

class InventoryDtoMapper {
  const InventoryDtoMapper._();

  static TrayInfo trayInfoFromJson(Map<String, dynamic> json) {
    final positionsJson = json['occupiedPositions'];
    if (positionsJson is! List) {
      throw const FormatException('occupiedPositions must be a list.');
    }

    final positions = positionsJson
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(_trayPositionFromJson)
        .toList(growable: false);

    return TrayInfo(
      maxSlots: _asInt(json['maxSlots']) ?? 0,
      occupiedCount: _asInt(json['occupiedCount']) ?? positions.length,
      occupiedPositions: positions,
    );
  }

  static SerialInfo serialInfoFromJson(
    String serialNumber,
    Map<String, dynamic> json,
  ) {
    return SerialInfo(
      serialNumber: serialNumber,
      wipGroup: _firstNonEmptyString(
        json,
        const <String>['wip_group', 'wipGroup', 'WipGroup'],
      ),
      modelName: _firstNonEmptyString(
        json,
        const <String>['model_name', 'modelName', 'ModelName'],
      ),
      productLine: _firstNonEmptyString(
        json,
        const <String>['product_line', 'productLine', 'ProductLine'],
      ),
    );
  }

  static InventoryImportResult importResultFromJson(
    Map<String, dynamic> json,
  ) {
    final rawResults = json['results'];
    final results = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map(_importItemResultFromJson)
            .toList(growable: false)
        : const <ImportItemResult>[];
    final rawInvalidSerials = json['invalidSerials'];

    return InventoryImportResult(
      success: json['success'] == true,
      message: _asNonEmptyString(json['message']) ??
          (json['success'] == true
              ? 'Inventory import completed.'
              : 'Inventory import failed.'),
      results: results,
      invalidSerials: rawInvalidSerials is List
          ? rawInvalidSerials
              .map((item) => item.toString().trim().toUpperCase())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }

  static InventoryExportResult exportResultFromJson(
    Map<String, dynamic> json,
  ) {
    final success = json['success'] == true;
    return InventoryExportResult(
      success: success,
      message: _asNonEmptyString(json['message']) ??
          (success
              ? 'Inventory export completed.'
              : 'Inventory export failed.'),
    );
  }

  static TrayPosition _trayPositionFromJson(Map<String, dynamic> json) {
    final serialNumber = _asNonEmptyString(json['serialNumber']);
    if (serialNumber == null) {
      throw const FormatException('Tray position has no serialNumber.');
    }

    return TrayPosition(
      serialNumber: serialNumber.toUpperCase(),
      positionInTray:
          _asInt(json['positionInTray']) ?? _asInt(json['position']),
      location: _asNonEmptyString(json['location']),
    );
  }

  static ImportItemResult _importItemResultFromJson(
    Map<String, dynamic> json,
  ) {
    final serialNumber = _asNonEmptyString(json['serialNumber']);
    if (serialNumber == null) {
      throw const FormatException('Import result has no serialNumber.');
    }

    return ImportItemResult(
      serialNumber: serialNumber.toUpperCase(),
      success: json['success'] == true,
      message: _asNonEmptyString(json['message']) ?? '',
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _asNonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _asNonEmptyString(json[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }
}
