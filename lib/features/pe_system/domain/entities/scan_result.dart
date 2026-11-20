class ScanResult {
  final String? clientScanId;
  final int eventId;
  final int searchListId;
  final String serialNumber;
  final bool isFound;
  final DateTime scannedAt;
  final String scannedBy;
  final DateTime? foundAt;

  const ScanResult({
    this.clientScanId,
    required this.eventId,
    required this.searchListId,
    required this.serialNumber,
    required this.isFound,
    required this.scannedAt,
    required this.scannedBy,
    required this.foundAt,
  });
}
