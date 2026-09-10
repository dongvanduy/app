import '../../domain/entities/repair_lookup_models.dart';

class RepairLookupDtos {
  const RepairLookupDtos._();

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }
    return value;
  }

  static String requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing or invalid $key.');
    }
    return value;
  }

  static String? _text(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid $key.');
    return value;
  }

  static DateTime? _time(Map<String, dynamic> json, String key) {
    final text = _text(json, key);
    if (text == null || text.trim().isEmpty) return null;
    // Unzoned timestamps must not silently depend on the device timezone.
    if (!RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(text.trim())) {
      return null;
    }
    return DateTime.tryParse(text.trim())?.toUtc();
  }

  static SnInfo snInfo(Map<String, dynamic> json) => SnInfo(
    sn: requiredString(json, 'sn'),
    wipGroup: _text(json, 'wip_group'),
    modelName: _text(json, 'model_name'),
    errorFlag: _text(json, 'error_flag'),
  );

  static TestHistoryEntry testEntry(Map<String, dynamic> json) =>
      TestHistoryEntry(
        id: requiredString(json, 'id'),
        testGroup: _text(json, 'test_group'),
        testCode: _text(json, 'test_code'),
        errorDesc: _text(json, 'error_desc'),
        errorCodeItem: _text(json, 'error_code_item'),
        testTime: _time(json, 'test_time'),
        reasonCode: _text(json, 'reason_code'),
        reasonDesc: _text(json, 'reason_desc'),
        memo: _text(json, 'memo'),
      );

  static RepairHistoryEntry repairEntry(Map<String, dynamic> json) =>
      RepairHistoryEntry(
        id: requiredString(json, 'id'),
        testGroup: _text(json, 'test_group'),
        testTime: _time(json, 'test_time'),
        date3: _time(json, 'date3'),
        repairer: _text(json, 'repairer'),
        repairAction: _text(json, 'repair_action'),
      );

  static HistoryResult<T> history<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
    DateTime? Function(T) timeOf,
  ) {
    final total = json['total'];
    final raw = json['histories'];
    if (total is! int || total < 0 || raw is! List) {
      throw const FormatException('Invalid history result.');
    }
    return HistoryResult(
      sn: requiredString(json, 'sn'),
      total: total,
      histories: sortHistory(
        raw.map((entry) => parse(object(entry))).toList(),
        timeOf,
      ),
    );
  }
}
