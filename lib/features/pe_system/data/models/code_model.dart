class CodeModel {
  final String id;
  final String serialNumber;
  final String modelName;
  final String shelfCode;
  final int columnNumber;
  final int levelNumber;
  final int trayNumber;
  final int positionInTray;
  final bool isFound;
  final DateTime? foundAt;

  CodeModel({
    required this.id,
    required this.serialNumber,
    required this.modelName,
    required this.shelfCode,
    required this.columnNumber,
    required this.levelNumber,
    required this.trayNumber,
    required this.positionInTray,
    required this.isFound,
    this.foundAt,
  });

  factory CodeModel.fromJson(Map<String, dynamic> json) {
    final time =
        json.containsKey('foundAt') ? json['foundAt'] : json['scanTime'];
    final foundAt = time is String ? DateTime.tryParse(time) : null;
    if (json['serialNumber'] is! String ||
        (json['serialNumber'] as String).trim().isEmpty ||
        json['isFound'] is! bool ||
        (time != null && foundAt == null)) {
      throw const FormatException('Invalid search list item');
    }
    return CodeModel(
      id: json['id']?.toString() ?? '',
      serialNumber: json['serialNumber'] ?? '',
      modelName: json['modelName'] ?? '',
      shelfCode: json['shelfCode'] ?? '',
      columnNumber: json['columnNumber'] ?? 0,
      levelNumber: json['levelNumber'] ?? 0,
      trayNumber: json['trayNumber'] ?? 0,
      positionInTray: json['positionInTray'] ?? 0,
      isFound: json['isFound'] ?? false,
      foundAt: foundAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serialNumber': serialNumber,
      'modelName': modelName,
      'shelfCode': shelfCode,
      'columnNumber': columnNumber,
      'levelNumber': levelNumber,
      'trayNumber': trayNumber,
      'positionInTray': positionInTray,
      'isFound': isFound,
      'foundAt': foundAt?.toIso8601String(),
    };
  }
}

class SearchListModel {
  final String id;
  final String listName;
  final DateTime createdAt;
  final String createdBy;
  final List<CodeModel> items;
  final bool hasDetails;

  SearchListModel({
    required this.id,
    required this.listName,
    required this.createdAt,
    required this.createdBy,
    required this.items,
    this.hasDetails = true,
  });

  factory SearchListModel.fromJson(
    Map<String, dynamic> json, {
    bool hasDetails = true,
  }) {
    final id = (json['searchListId'] ?? json['id'])?.toString() ?? '';
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final items = json['items'];
    if ((int.tryParse(id) ?? 0) <= 0 ||
        json['listName'] is! String ||
        createdAt == null ||
        (hasDetails && items is! List)) {
      throw const FormatException('Invalid search list response');
    }
    if (hasDetails &&
        json.containsKey('totalItems') &&
        json['totalItems'] != (items as List).length) {
      throw const FormatException('Incomplete search list items');
    }
    return SearchListModel(
      id: id,
      listName: json['listName'],
      createdAt: createdAt,
      createdBy: json['createdBy'] ?? '',
      hasDetails: hasDetails,
      items:
          hasDetails
              ? (items as List)
                  .map(
                    (item) => CodeModel.fromJson(item as Map<String, dynamic>),
                  )
                  .toList()
              : [],
    );
  }
}

class SearchListPageModel {
  SearchListPageModel({
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
  final List<SearchListModel> lists;

  factory SearchListPageModel.fromJson(
    Map<String, dynamic> json, {
    int requestedPage = 1,
    int requestedPageSize = 20,
  }) {
    final data = json['data'];
    if (data is! Map<String, dynamic> || data['lists'] is! List) {
      throw const FormatException('Invalid paged search list response');
    }
    final keys = ['page', 'pageSize', 'totalPages'];
    final paged = keys.any(data.containsKey);
    final total = data['totalLists'];
    if (total is! int ||
        total < 0 ||
        requestedPage < 1 ||
        requestedPageSize < 1 ||
        (paged && !keys.every((key) => data[key] is int))) {
      throw const FormatException('Invalid search list pagination');
    }
    final lists =
        (data['lists'] as List)
            .map(
              (item) => SearchListModel.fromJson(
                item as Map<String, dynamic>,
                hasDetails: !paged,
              ),
            )
            .toList();
    if (paged) {
      final page = data['page'] as int;
      final size = data['pageSize'] as int;
      final pages = data['totalPages'] as int;
      if (page != requestedPage ||
          size != requestedPageSize ||
          pages != (total + size - 1) ~/ size ||
          lists.length > size) {
        throw const FormatException('Invalid search list pagination');
      }
      return SearchListPageModel(
        page: page,
        pageSize: size,
        totalLists: total,
        totalPages: pages,
        lists: lists,
      );
    }
    // Legacy API ignores paging and returns all lists with their items.
    if (total != lists.length) {
      throw const FormatException('Incomplete legacy search lists');
    }
    lists.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : int.parse(b.id).compareTo(int.parse(a.id));
    });
    return SearchListPageModel(
      page: requestedPage,
      pageSize: requestedPageSize,
      totalLists: total,
      totalPages: (total + requestedPageSize - 1) ~/ requestedPageSize,
      lists:
          lists
              .skip((requestedPage - 1) * requestedPageSize)
              .take(requestedPageSize)
              .toList(),
    );
  }
}
