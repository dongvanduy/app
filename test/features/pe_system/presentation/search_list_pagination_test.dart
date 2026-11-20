import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pe_system/domain/entities/code_entity.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/code_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'wifi');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'pages list metadata but loads every item of the selected list',
    () async {
      final repository = _PagedRepository();
      final provider = CodeProvider(
        useCase: ManageCodesUseCase(repository: repository),
        connectivity: Connectivity(),
      );
      addTearDown(provider.dispose);

      await provider.fetchSearchList();
      expect(provider.searchListPage, 1);
      expect(provider.searchListTotalPages, 2);
      expect(provider.searchLists, hasLength(20));
      expect(provider.searchLists.first.hasDetails, isFalse);

      provider.setSelectedSearchListIndex(0);
      for (var i = 0; i < 20 && provider.selectedSearchListId != '25'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(provider.selectedSearchListId, '25');
      expect(provider.codeList, hasLength(2));
      expect(repository.detailIds, [25]);

      await provider.goToSearchListPage(2);
      expect(provider.searchListPage, 2);
      expect(provider.searchLists, hasLength(6)); // Selected list stays pinned.
      expect(provider.selectedSearchListId, '25');
      expect(provider.codeList, hasLength(2));
    },
  );
}

class _PagedRepository extends Fake implements CodeRepository {
  final detailIds = <int>[];

  @override
  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) async => SearchListPage(
    page: page,
    pageSize: pageSize,
    totalLists: 25,
    totalPages: 2,
    lists: [
      for (var id = 25 - (page - 1) * 20; id > 25 - page * 20 && id > 0; id--)
        SearchListEntity(
          id: id.toString(),
          listName: 'List $id',
          createdAt: DateTime.utc(2026, 9, 23),
          createdBy: 'test',
          items: [],
          hasDetails: false,
        ),
    ],
  );

  @override
  Future<SearchListEntity> getSearchListDetails(int searchListId) async {
    detailIds.add(searchListId);
    return SearchListEntity(
      id: searchListId.toString(),
      listName: 'List $searchListId',
      createdAt: DateTime.utc(2026, 9, 23),
      createdBy: 'test',
      items: [
        for (var i = 0; i < 2; i++)
          CodeEntity(
            id: i.toString(),
            serialNumber: 'SN123456789$i',
            modelName: '',
            shelfCode: '',
            isFound: false,
          ),
      ],
    );
  }

  @override
  Future<Map<String, String>> findLocations(List<String> serialNumbers) async =>
      {};
}
