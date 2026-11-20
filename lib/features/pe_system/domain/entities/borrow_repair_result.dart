class BorrowedSerial {
  const BorrowedSerial({
    required this.serialNumber,
    this.requestedSerialNumber,
    required this.borrowPerson,
  });

  final String serialNumber;
  final String? requestedSerialNumber;
  final String? borrowPerson;
}

class BorrowRepairResult {
  BorrowRepairResult({
    required List<BorrowedSerial> borrowed,
    required this.totalBorrowed,
    required this.totalNotFound,
    required this.totalFailed,
    List<String> notFoundSerials = const [],
    List<String> failedSerials = const [],
    List<String> warnings = const [],
  }) : borrowed = List.unmodifiable(borrowed),
       notFoundSerials = List.unmodifiable(notFoundSerials),
       failedSerials = List.unmodifiable(failedSerials),
       warnings = List.unmodifiable(warnings);

  final List<BorrowedSerial> borrowed;
  final int totalBorrowed;
  final int totalNotFound;
  final int totalFailed;
  final List<String> notFoundSerials;
  final List<String> failedSerials;
  final List<String> warnings;
}
