import '../entities/repair_lookup_models.dart';

abstract class RepairLookupRepository {
  Future<SnInfo> getSnInfo(String sn);
  Future<HistoryResult<TestHistoryEntry>> getTestHistory(String sn);
  Future<HistoryResult<RepairHistoryEntry>> getRepairHistory(String sn);
}
