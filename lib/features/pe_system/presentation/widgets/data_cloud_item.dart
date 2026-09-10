import 'dart:typed_data';

enum DataCloudScope {
  private('Private', 'Private'),
  public('Public', 'Public'),
  dataTraining('DataTraining', 'Data Training');

  const DataCloudScope(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get allowDelete => this != dataTraining;
  bool get allowRename => this != dataTraining;

  static DataCloudScope parse(Object? value, DataCloudScope fallback) {
    if (value == null) return fallback;
    final normalized = value.toString().toLowerCase().replaceAll(
      RegExp(r'[\s_-]'),
      '',
    );
    return values.firstWhere(
      (scope) => scope.apiValue.toLowerCase() == normalized,
      orElse: () => throw const FormatException('Invalid DataCloud scope.'),
    );
  }
}

String normalizeDataCloudPath(String? path) {
  final value = (path ?? '').replaceAll('\\', '/');
  if (RegExp(r'^[a-zA-Z]:').hasMatch(value) || value.startsWith('//')) {
    throw const FormatException('DataCloud requires a relative path.');
  }
  final normalized = value.replaceAll(RegExp(r'^/+|/+$'), '');
  if (normalized.split('/').any((part) => part == '..' || part == '.')) {
    throw const FormatException('Invalid relative path.');
  }
  return normalized;
}

class DataCloudItem {
  final String name;
  final String path;
  final String type;
  final DataCloudScope scope;
  final int? size;
  final DateTime? lastModifiedUtc;

  DataCloudItem({
    required this.name,
    required this.path,
    required this.type,
    this.scope = DataCloudScope.private,
    this.size,
    this.lastModifiedUtc,
  });

  factory DataCloudItem.fromJson(
    Map<String, dynamic> json, {
    DataCloudScope fallbackScope = DataCloudScope.private,
  }) {
    final name = json['name'] ?? json['Name'];
    final path =
        json['path'] ??
        json['Path'] ??
        json['relativePath'] ??
        json['RelativePath'];
    if (name is! String || name.isEmpty || path is! String || path.isEmpty) {
      throw const FormatException('Invalid DataCloud item.');
    }
    return DataCloudItem(
      name: name,
      path: normalizeDataCloudPath(path),
      type: (json['type'] ?? json['Type'] ?? 'File').toString(),
      scope: DataCloudScope.parse(
        json['scope'] ?? json['Scope'],
        fallbackScope,
      ),
      size:
          (json['size'] ?? json['Size']) is num
              ? ((json['size'] ?? json['Size']) as num).toInt()
              : null,
      lastModifiedUtc: DateTime.tryParse(
        (json['lastModifiedUtc'] ?? json['LastModifiedUtc'] ?? '').toString(),
      ),
    );
  }

  bool get isFolder {
    final normalizedType = type.toLowerCase();
    return normalizedType == 'folder' || normalizedType == 'directory';
  }
}

class DataCloudResponse {
  final String currentPath;
  final List<DataCloudItem> items;

  DataCloudResponse({required this.currentPath, required this.items});

  factory DataCloudResponse.fromJson(
    Map<String, dynamic> json, {
    DataCloudScope fallbackScope = DataCloudScope.private,
    String fallbackPath = '',
  }) {
    final rawData = json['data'];
    final payload = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
    final rawItems = payload['items'] ?? payload['Items'];

    if (rawItems is! List) {
      throw const FormatException('DataCloud response does not contain items.');
    }

    return DataCloudResponse(
      currentPath: normalizeDataCloudPath(
        (payload['currentPath'] ?? payload['CurrentPath'] ?? fallbackPath)
            .toString(),
      ),
      items:
          rawItems.map((item) {
            if (item is! Map) {
              throw const FormatException('Invalid DataCloud item.');
            }
            return DataCloudItem.fromJson(
              Map<String, dynamic>.from(item),
              fallbackScope: fallbackScope,
            );
          }).toList(),
    );
  }
}

class DataCloudDownload {
  final String fileName;
  final Uint8List bytes;

  const DataCloudDownload({required this.fileName, required this.bytes});
}
