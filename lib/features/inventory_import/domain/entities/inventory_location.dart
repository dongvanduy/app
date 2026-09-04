class InventoryLocation {
  final String raw;
  final String normalized;
  final String shelf;
  final int column;
  final int level;
  final int tray;

  const InventoryLocation({
    required this.raw,
    required this.normalized,
    required this.shelf,
    required this.column,
    required this.level,
    required this.tray,
  });

  bool get isComplete => true;

  Map<String, Object> toQueryParameters() => <String, Object>{
        'shelf': shelf,
        'column': column,
        'level': level,
        'tray': tray,
      };
}
