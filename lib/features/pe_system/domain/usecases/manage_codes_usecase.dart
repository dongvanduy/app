import '../entities/code_entity.dart';
import '../entities/search_list_entity.dart';
import '../repositories/code_repository.dart';

class ManageCodesUseCase {
  final CodeRepository repository;

  ManageCodesUseCase({required this.repository});

  Future<List<CodeEntity>> getCodeList() async {
    return await repository.getCodeList();
  }

  Future<bool> checkCode(String serialNumber) async {
    return await repository.checkCode(serialNumber);
  }

  Future<List<SearchListEntity>> getSearchList() async {
    return await repository.getSearchList();
  }

  Future<bool> scanSerialNumber(String serialNumber) async {
    return await repository.scanSerialNumber(serialNumber);
  }
}
