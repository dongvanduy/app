import '../../../../core/error/exceptions.dart';
import '../../domain/entities/borrow_repair_result.dart';

/// Inventory responses confirm locations and loans independently of scan state.
class PeInventoryMapper {
  static Map<String, String> locations(Object? response) {
    final json = _object(response);
    if (json['success'] != true) {
      throw ServerException(
        json['message'] is String
            ? json['message'] as String
            : 'Unable to load locations.',
        kind: ApiFailureKind.business,
      );
    }
    final rows = json['data'];
    if (rows is! List) throw _invalid();
    final result = <String, String>{};
    for (final row in rows) {
      final item = _object(row);
      final serial = _serial(item['serialNumber']);
      final location = item['location'];
      if (location != null && location is! String) throw _invalid();
      if (location is String && location.trim().isNotEmpty) {
        result[serial.toUpperCase()] = location.trim();
      }
    }
    return result;
  }

  static BorrowRepairResult borrow(Object? response) {
    final json = _object(response);
    if (json['success'] is! bool) throw _invalid();
    final rows = json['borrowedResults'];
    if (rows is! List) {
      if (json['success'] == false && json['message'] is String) {
        throw ServerException(
          json['message'] as String,
          kind: ApiFailureKind.business,
        );
      }
      throw _invalid();
    }
    final borrowed = <BorrowedSerial>[];
    for (final row in rows) {
      final item = _object(row);
      final serial = _serial(item['serialNumber']);
      if (item['borrowStatus'] is! String) throw _invalid();
      final person = item['borrowPerson'];
      if (person != null && person is! String) throw _invalid();
      if (item['borrowStatus'] == 'Borrowed') {
        borrowed.add(
          BorrowedSerial(
            serialNumber: serial,
            requestedSerialNumber: _serial(item['requestedSerialNumber'] ?? serial),
            borrowPerson: person as String?,
          ),
        );
      }
    }
    return BorrowRepairResult(
      borrowed: borrowed,
      totalBorrowed: _count(json['totalBorrowed']),
      totalNotFound: _count(json['totalNotFound']),
      totalFailed: _count(json['totalFailed']),
      notFoundSerials: _stringList(json['notFoundSerials']),
      failedSerials: _stringList(json['failedSerials']),
      warnings: _stringList(json['warnings'], optional: true),
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalid();
    return value;
  }

  static String _serial(Object? value) {
    if (value is! String || value.trim().isEmpty) throw _invalid();
    return value.trim();
  }

  static int _count(Object? value) {
    if (value is! int || value < 0) throw _invalid();
    return value;
  }

  static List<String> _stringList(Object? value, {bool optional = false}) {
    if (value == null && optional) return const [];
    if (value is! List) throw _invalid();
    return value.map(_serial).toList(growable: false);
  }

  static ServerException _invalid() => const ServerException(
    'The server returned an invalid inventory response.',
    kind: ApiFailureKind.invalidResponse,
  );
}
