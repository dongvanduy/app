import '../entities/code_entity.dart';
import '../entities/search_list_entity.dart';
import '../repositories/code_repository.dart';
import '../entities/borrow_repair_result.dart';
import '../entities/scan_result.dart';

class ManageCodesUseCase {
  final CodeRepository repository;

  ManageCodesUseCase({required this.repository});

  Future<Map<String, String>> findLocations(List<String> serialNumbers) =>
      repository.findLocations(serialNumbers);

  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
  }) =>
      repository.borrowRepair(serialNumbers: serialNumbers, borrower: borrower);

  Future<List<CodeEntity>> getCodeList() async {
    return await repository.getCodeList();
  }

  Future<bool> checkCode(String serialNumber) async {
    return await repository.checkCode(serialNumber);
  }

  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) => repository.getSearchListPage(page: page, pageSize: pageSize);

  Future<SearchListEntity> getSearchListDetails(int searchListId) =>
      repository.getSearchListDetails(searchListId);
  Future<List<SearchListEntity>> getSearchList() async {
    return await repository.getSearchList();
  }

  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  }) async {
    return await repository.scanSerialNumber(
      serialNumber,
      searchListId: searchListId,
    );
  }
}
