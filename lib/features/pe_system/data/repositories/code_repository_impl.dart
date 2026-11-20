import '../../../../core/error/exceptions.dart';
import '../../domain/entities/code_entity.dart';
import '../../domain/entities/search_list_entity.dart';
import '../../domain/repositories/code_repository.dart';
import '../datasources/remote_datasource.dart';
import '../models/code_model.dart';
import '../../domain/entities/borrow_repair_result.dart';
import '../../domain/entities/scan_result.dart';

class CodeRepositoryImpl implements CodeRepository {
  final RemoteDataSource remoteDataSource;

  CodeRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Map<String, String>> findLocations(List<String> serialNumbers) =>
      remoteDataSource.findLocations(serialNumbers);

  @override
  Future<BorrowRepairResult> borrowRepair({
    required List<String> serialNumbers,
    required String borrower,
  }) => remoteDataSource.borrowRepair(
    serialNumbers: serialNumbers,
    borrower: borrower,
  );

  @override
  Future<List<SearchListEntity>> getSearchList() async =>
      (await remoteDataSource.getSearchList()).map(_toEntity).toList();

  @override
  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) async {
    final result = await remoteDataSource.getSearchListPage(
      page: page,
      pageSize: pageSize,
    );
    return SearchListPage(
      page: result.page,
      pageSize: result.pageSize,
      totalLists: result.totalLists,
      totalPages: result.totalPages,
      lists: result.lists.map(_toEntity).toList(),
    );
  }

  @override
  Future<SearchListEntity> getSearchListDetails(int searchListId) async =>
      _toEntity(await remoteDataSource.getSearchListDetails(searchListId));

  static SearchListEntity _toEntity(SearchListModel model) => SearchListEntity(
    id: model.id,
    listName: model.listName,
    createdAt: model.createdAt,
    createdBy: model.createdBy,
    hasDetails: model.hasDetails,
    items:
        model.items
            .map(
              (item) => CodeEntity(
                id: item.id,
                serialNumber: item.serialNumber,
                modelName: item.modelName,
                shelfCode: item.shelfCode,
                columnNumber: item.columnNumber,
                levelNumber: item.levelNumber,
                trayNumber: item.trayNumber,
                positionInTray: item.positionInTray,
                isFound: item.isFound,
                foundAt: item.foundAt,
              ),
            )
            .toList(),
  );

  @override
  Future<ScanResult> scanSerialNumber(
    String serialNumber, {
    required int searchListId,
  }) async {
    try {
      return await remoteDataSource.scanSerialNumber(
        serialNumber,
        searchListId: searchListId,
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Lỗi ghi nhận mã đã quét: $e');
    }
  }

  @override
  Future<List<CodeEntity>> getCodeList() {
    throw UnimplementedError(); // Không còn cần thiết vì dùng getSearchList
  }

  @override
  Future<bool> checkCode(String serialNumber) {
    throw UnimplementedError(); // Không còn cần thiết vì dùng updateScannedStatus
  }
}
