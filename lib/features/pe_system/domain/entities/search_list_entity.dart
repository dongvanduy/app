import 'code_entity.dart';

class SearchListEntity {
  final String id;
  final String listName;
  final DateTime createdAt;
  final String createdBy;
  final List<CodeEntity> items;
  final bool hasDetails;

  SearchListEntity({
    required this.id,
    required this.listName,
    required this.createdAt,
    required this.createdBy,
    required this.items,
    this.hasDetails = true,
  });

  SearchListEntity copyWith({List<CodeEntity>? items, bool? hasDetails}) {
    return SearchListEntity(
      id: id,
      listName: listName,
      createdAt: createdAt,
      createdBy: createdBy,
      items: items ?? this.items,
      hasDetails: hasDetails ?? this.hasDetails,
    );
  }
}

class SearchListPage {
  const SearchListPage({
    required this.page,
    required this.pageSize,
    required this.totalLists,
    required this.totalPages,
    required this.lists,
  });

  final int page;
  final int pageSize;
  final int totalLists;
  final int totalPages;
  final List<SearchListEntity> lists;
}
