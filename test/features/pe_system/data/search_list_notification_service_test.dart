import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/features/pe_system/data/services/search_list_notification_service.dart';
import 'package:mobile_app/features/pe_system/domain/entities/search_list_entity.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'new list notification has a per-user baseline and no duplicates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = _PageRepository();
      final notices = <String>[];
      final service = SearchListNotificationService(
        useCase: ManageCodesUseCase(repository: repository),
        server: 'https://example.test/api/Scan/',
        showNotification: (_, title, body) async => notices.add(body),
      );
      addTearDown(service.dispose);

      repository.ids = [10, 9];
      await service.bindUser(1);
      expect(notices, isEmpty);

      repository.ids = [11, 10, 9];
      await service.checkNow();
      expect(notices, ['List 11']);
      await service.checkNow();
      expect(notices, hasLength(1));

      await service.bindUser(2);
      expect(notices, hasLength(1)); // New account gets its own baseline.
      repository.ids = [12, 11, 10, 9];
      await service.checkNow();
      expect(notices, ['List 11', 'List 12']);

      await service.bindUser(1);
      expect(notices, ['List 11', 'List 12', 'List 12']);
      await service.bindUser(null);
      repository.ids = [13, 12];
      await service.checkNow();
      expect(notices, hasLength(3)); // Logout stops polling.
    },
  );
}

class _PageRepository extends Fake implements CodeRepository {
  List<int> ids = [];

  @override
  Future<SearchListPage> getSearchListPage({
    required int page,
    int pageSize = 20,
  }) async => SearchListPage(
    page: page,
    pageSize: pageSize,
    totalLists: ids.length,
    totalPages: 1,
    lists: [
      for (final id in ids)
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
}
