import 'dart:typed_data';

class DataCloudItem {
  final String name;
  final String path;
  final String type;

  DataCloudItem({required this.name, required this.path, required this.type});

  factory DataCloudItem.fromJson(Map<String, dynamic> json) {
    return DataCloudItem(
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      path: (json['path'] ?? json['Path'] ?? '').toString(),
      type: (json['type'] ?? json['Type'] ?? '').toString(),
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

  factory DataCloudResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final payload = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
    final rawItems = payload['items'] ?? payload['Items'];

    if (rawItems is! List) {
      throw const FormatException('DataCloud response does not contain items.');
    }

    return DataCloudResponse(
      currentPath:
          (payload['currentPath'] ?? payload['CurrentPath'] ?? '').toString(),
      items:
          rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    DataCloudItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(),
    );
  }
}

class DataCloudDownload {
  final String fileName;
  final Uint8List bytes;

  const DataCloudDownload({required this.fileName, required this.bytes});
}
