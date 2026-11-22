import '../entities/inventory_location.dart';
import '../entities/inventory_models.dart';
import '../entities/stock_type.dart';

class InventoryLocationParser {
  static final RegExp _fullLocation = RegExp(
    r'^([A-Z]+)(\d+)-(\d+)-K(\d+)$',
  );

  static final RegExp _locationWithoutLevel = RegExp(
    r'^([A-Z]+)(\d+)-K(\d+)$',
  );

  static final RegExp _repairFullLocation = RegExp(
    r'^([A-Z]+0?)(\d+)-(\d+)-K(\d+)$',
  );

  static final RegExp _repairLocationWithoutLevel = RegExp(
    r'^([A-Z]+0?)(\d+)-K(\d+)$',
  );

  static final RegExp _scrapCarton = RegExp(
    r'^CARTON-(\d+)$',
  );

  const InventoryLocationParser._();

  static InventoryLocation? parse(String value, StockType stockType) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }

    final input = raw.toUpperCase();

    if (stockType == StockType.scrap) {
      final cartonMatch = _scrapCarton.firstMatch(input);
      if (cartonMatch != null) {
        final cartonNumber = int.tryParse(cartonMatch.group(1)!);
        if (cartonNumber == null) {
          return null;
        }
        return InventoryLocation(
          raw: raw,
          normalized: 'CARTON-$cartonNumber',
          shelf: 'CARTON',
          column: cartonNumber,
          level: 0,
          tray: 0,
        );
      }
    }

    final isRepair = stockType == StockType.repair;
    final fullMatch =
        (isRepair ? _repairFullLocation : _fullLocation).firstMatch(input);
    if (fullMatch != null) {
      return _fromMatch(raw, fullMatch, hasLevel: true);
    }

    final withoutLevelMatch =
        (isRepair ? _repairLocationWithoutLevel : _locationWithoutLevel)
            .firstMatch(input);
    if (withoutLevelMatch != null) {
      return _fromMatch(raw, withoutLevelMatch, hasLevel: false);
    }

    return null;
  }

  static InventoryLocation? _fromMatch(
    String raw,
    RegExpMatch match, {
    required bool hasLevel,
  }) {
    final shelf = match.group(1)!;
    final column = int.tryParse(match.group(2)!);
    final level = hasLevel ? int.tryParse(match.group(3)!) : 0;
    final tray = int.tryParse(match.group(hasLevel ? 4 : 3)!);

    if (column == null || level == null || tray == null) {
      return null;
    }

    return InventoryLocation(
      raw: raw,
      normalized: '$shelf$column-$level-K$tray',
      shelf: shelf,
      column: column,
      level: level,
      tray: tray,
    );
  }
}

class SerialNumberParser {
  const SerialNumberParser._();

  static String normalize(String value) => value.trim().toUpperCase();

  static List<String> parse(String value) {
    return value
        .split(RegExp(r'\r\n?|\n'))
        .map(normalize)
        .where((serial) => serial.isNotEmpty)
        .toList(growable: false);
  }
}

class InventoryValidation {
  const InventoryValidation._();

  static Set<String> duplicateSerials(Iterable<String> serialNumbers) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final value in serialNumbers) {
      final serial = SerialNumberParser.normalize(value);
      if (serial.isNotEmpty && !seen.add(serial)) {
        duplicates.add(serial);
      }
    }
    return duplicates;
  }

  static Set<String> duplicateSerialsInTray(
    Iterable<String> serialNumbers,
    TrayInfo? trayInfo,
  ) {
    if (trayInfo == null) {
      return const <String>{};
    }

    final occupied = trayInfo.occupiedPositions
        .map((position) => SerialNumberParser.normalize(position.serialNumber))
        .toSet();

    return serialNumbers
        .map(SerialNumberParser.normalize)
        .where(occupied.contains)
        .toSet();
  }

  static int capacityAfterImport(TrayInfo? trayInfo, int newSerialCount) {
    return (trayInfo?.actualOccupiedCount ?? 0) + newSerialCount;
  }

  static bool isOverCapacity(TrayInfo? trayInfo, int newSerialCount) {
    if (trayInfo == null || trayInfo.maxSlots <= 0) {
      return false;
    }
    return capacityAfterImport(trayInfo, newSerialCount) > trayInfo.maxSlots;
  }
}
