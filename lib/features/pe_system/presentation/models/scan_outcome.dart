import '../../domain/entities/scan_result.dart';

enum ScanOutcomeStatus { found, notInList, pendingFound, pendingNotInList, failed, cancelled }

/// Recording a scan and finding an item in the selected list are separate outcomes.
class ScanOutcome {
  const ScanOutcome({
    required this.status,
    required this.serialNumber,
    required this.message,
    this.result,
  });

  final ScanOutcomeStatus status;
  final String serialNumber;
  final String message;
  final ScanResult? result;

  bool get isRecorded => result != null;
  bool get isFound => status == ScanOutcomeStatus.found;
}
