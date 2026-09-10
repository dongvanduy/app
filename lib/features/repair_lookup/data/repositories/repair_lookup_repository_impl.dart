import '../../domain/entities/repair_lookup_models.dart';
import '../../domain/repositories/repair_lookup_repository.dart';
import '../datasources/repair_lookup_remote_data_source.dart';

class RepairLookupRepositoryImpl implements RepairLookupRepository {
  const RepairLookupRepositoryImpl({required this.remoteDataSource});
  final RepairLookupRemoteDataSource remoteDataSource;

  @override
  Future<SnInfo> getSnInfo(String sn) => remoteDataSource.getSnInfo(sn);
  @override
  Future<HistoryResult<TestHistoryEntry>> getTestHistory(String sn) =>
      remoteDataSource.getTestHistory(sn);
  @override
  Future<HistoryResult<RepairHistoryEntry>> getRepairHistory(String sn) =>
      remoteDataSource.getRepairHistory(sn);
}
