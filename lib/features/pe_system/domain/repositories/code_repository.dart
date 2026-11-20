import '../entities/code_entity.dart';
import '../entities/search_list_entity.dart';
import '../entities/borrow_repair_result.dart';
import '../entities/scan_result.dart';

abstract class CodeRepository {
  Future<Map<String, String>> findLocations(List<String> serialNumbers);
  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
  });
  Future<List<CodeEntity>> getCodeList(); // Giữ lại cho tương thích
  Future<bool> checkCode(String serialNumber); // Giữ lại cho tương thích
  Future<List<SearchListEntity>> getSearchList();
  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) async {
    final lists = await getSearchList();
    final start = (page - 1) * pageSize;
    return SearchListPage(
      page: page,
      pageSize: pageSize,
      totalLists: lists.length,
      totalPages: (lists.length + pageSize - 1) ~/ pageSize,
      lists:
          start >= lists.length
              ? []
              : lists.skip(start).take(pageSize).toList(),
    );
  }

  Future<SearchListEntity> getSearchListDetails(int searchListId) async {
    return (await getSearchList()).firstWhere(
      (list) => list.id == searchListId.toString(),
    );
  }

  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  });
}
