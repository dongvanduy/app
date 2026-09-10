class SnInfo {
  const SnInfo({
    required this.sn,
    this.wipGroup,
    this.modelName,
    this.errorFlag,
  });
  final String sn;
  final String? wipGroup;
  final String? modelName;
  final String? errorFlag;
}

class HistoryResult<T> {
  HistoryResult({
    required this.sn,
    required this.total,
    required List<T> histories,
  }) : histories = List.unmodifiable(histories);
  final String sn;
  final int total;
  final List<T> histories;
}

class TestHistoryEntry {
  const TestHistoryEntry({
    required this.id,
    this.testGroup,
    this.testCode,
    this.errorDesc,
    this.errorCodeItem,
    this.testTime,
    this.reasonCode,
    this.reasonDesc,
    this.memo,
  });
  final String id;
  final String? testGroup;
  final String? testCode;
  final String? errorDesc;
  final String? errorCodeItem;
  final DateTime? testTime;
  final String? reasonCode;
  final String? reasonDesc;
  final String? memo;
}

class RepairHistoryEntry {
  const RepairHistoryEntry({
    required this.id,
    this.testGroup,
    this.testTime,
    this.date3,
    this.repairer,
    this.repairAction,
  });
  final String id;
  final String? testGroup;
  final DateTime? testTime;
  final DateTime? date3;
  final String? repairer;
  final String? repairAction;
  DateTime? get eventTime => date3 ?? testTime;
}

/// Preserve API order for equal timestamps and put undated events last.
List<T> sortHistory<T>(List<T> entries, DateTime? Function(T) timeOf) {
  final indexed = entries.indexed.toList();
  indexed.sort((a, b) {
    final left = timeOf(a.$2);
    final right = timeOf(b.$2);
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    final comparison = left == null ? 0 : left.compareTo(right!);
    return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
  });
  return indexed.map((entry) => entry.$2).toList();
}
