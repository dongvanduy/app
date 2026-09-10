import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/network/auth_token_provider.dart';
import '../widgets/data_cloud_item.dart';

class DatacloudProvider with ChangeNotifier {
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxUploadSize = 419430400;
  static const Duration _transferTimeout = Duration(minutes: 5);

  final String baseUrl;
  final String rootPath;
  final http.Client _client;
  final AuthTokenProvider? authTokenProvider;

  DataCloudResponse? _dataCloudResponse;
  String? _dataCloudError;
  bool _isLoadingDataCloud = false;
  DataCloudScope _scope = DataCloudScope.private;
  bool _disposed = false;
  late final List<String> _pathHistory = <String>[normalizePath(rootPath)];

  DatacloudProvider({
    required this.baseUrl,
    this.rootPath = '',
    http.Client? client,
    this.authTokenProvider,
  }) : _client = client ?? http.Client();

  DataCloudResponse? get dataCloudResponse => _dataCloudResponse;
  String? get dataCloudError => _dataCloudError;
  bool get isLoadingDataCloud => _isLoadingDataCloud;
  List<String> get pathHistory => List<String>.unmodifiable(_pathHistory);
  String get currentPath => _pathHistory.last;
  bool get canGoBack => _pathHistory.length > 1;
  DataCloudScope get scope => _scope;
  bool get allowDelete => scope.allowDelete;
  bool get allowRename => scope.allowRename;

  Future<void> changeScope(DataCloudScope value) async {
    if (_isLoadingDataCloud || value == scope) return;
    _scope = value;
    _pathHistory
      ..clear()
      ..add(normalizePath(rootPath));
    _dataCloudResponse = null;
    await fetchDataCloud();
  }

  Future<void> fetchDataCloud({String? path, bool addToHistory = true}) async {
    if (_isLoadingDataCloud || _disposed) return;
    await _fetchDataCloud(path: path, addToHistory: addToHistory);
  }

  Future<void> _fetchDataCloud({String? path, bool addToHistory = true}) async {
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final normalizedPath = normalizePath(path ?? currentPath);
      final response = await _get(
        'get-data',
        queryParameters: <String, Object?>{
          'scope': scope.apiValue,
          'path': normalizedPath,
        },
      );
      if (_isSuccess(response)) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw const FormatException(
            'DataCloud response must be a JSON object.',
          );
        }
        _dataCloudResponse = DataCloudResponse.fromJson(
          Map<String, dynamic>.from(decoded),
          fallbackScope: scope,
          fallbackPath: normalizedPath,
        );
        final actualPath = _dataCloudResponse!.currentPath;
        if (addToHistory && actualPath != currentPath) {
          _pathHistory.add(actualPath);
        } else if (addToHistory || normalizedPath == currentPath) {
          _pathHistory[_pathHistory.length - 1] = actualPath;
        }
      } else {
        _dataCloudError = _responseError('Failed to load DataCloud', response);
      }
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to load DataCloud', error);
    }

    _isLoadingDataCloud = false;
    notifyListeners();
  }

  Future<void> searchDataCloud(String keyword) async {
    if (_isLoadingDataCloud || _disposed) return;
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final normalizedKeyword = keyword.trim();
      if (normalizedKeyword.isEmpty) {
        await _fetchDataCloud(addToHistory: false);
        return;
      }
      final response = await _get(
        'search',
        queryParameters: <String, Object?>{
          'keyword': normalizedKeyword,
          'scope': scope.apiValue,
          'path': currentPath,
        },
      );
      if (_isSuccess(response)) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw const FormatException('Search response must be a JSON object.');
        }
        _dataCloudResponse = DataCloudResponse.fromJson(
          Map<String, dynamic>.from(decoded),
          fallbackScope: scope,
          fallbackPath: currentPath,
        );
      } else {
        _dataCloudError = _responseError(
          'Failed to search DataCloud',
          response,
        );
      }
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to search DataCloud', error);
    }

    _isLoadingDataCloud = false;
    notifyListeners();
  }

  Future<bool> deleteItem(
    String path,
    String type, {
    DataCloudScope? itemScope,
  }) async {
    if (_isLoadingDataCloud) return false;
    final targetScope = itemScope ?? scope;
    if (!allowDelete || !targetScope.allowDelete) {
      _dataCloudError = 'Delete is disabled in Data Training.';
      notifyListeners();
      return false;
    }
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final response = await _postJson('delete-items', {
        'items': [
          {
            'scope': targetScope.apiValue,
            'path': normalizePath(path),
            'type': type,
          },
        ],
      });
      if (_isSuccess(response)) {
        await _fetchDataCloud(path: currentPath, addToHistory: false);
        return _dataCloudError == null;
      } else {
        _dataCloudError = _responseError('Failed to delete item', response);
      }
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to delete item', error);
    } finally {
      _isLoadingDataCloud = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> createFolder(String folderName) async {
    if (_isLoadingDataCloud) return false;
    final normalizedName = folderName.trim();
    if (normalizedName.isEmpty) {
      _dataCloudError = 'Folder name is required.';
      notifyListeners();
      return false;
    }

    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();
    try {
      final response = await _sendForm('create-folder', <String, String>{
        'Scope': scope.apiValue,
        'Path': currentPath,
        'FolderName': normalizedName,
      });
      if (_isSuccess(response)) {
        await _fetchDataCloud(addToHistory: false);
        return _dataCloudError == null;
      } else {
        _dataCloudError = _responseError('Failed to create folder', response);
      }
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to create folder', error);
    } finally {
      _isLoadingDataCloud = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> uploadFiles(
    List<File> files, {
    bool isFolder = false,
    List<String>? relativePaths,
  }) async {
    if (_isLoadingDataCloud) return false;
    if (files.isEmpty) {
      _dataCloudError = 'No files were selected.';
      notifyListeners();
      return false;
    }

    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      if (isFolder &&
          (relativePaths == null || relativePaths.length != files.length)) {
        throw StateError(
          'Folder uploads require a relative path for each file.',
        );
      }
      var totalSize = 0;
      for (final file in files) {
        totalSize += await file.length();
      }
      if (totalSize >= _maxUploadSize) {
        throw StateError('The upload request must be smaller than 400 MB.');
      }

      final response = await _sendWithAuthentication((headers) async {
        final request = http.MultipartRequest(
          'POST',
          _uri(isFolder ? 'upload-folder' : 'upload-file'),
        );
        request.headers.addAll(headers);
        request.fields['Scope'] = scope.apiValue;
        request.fields['Path'] = currentPath;
        for (var i = 0; i < files.length; i++) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'Files',
              files[i].path,
              filename:
                  isFolder
                      ? normalizePath(relativePaths![i])
                      : files[i].uri.pathSegments.last,
            ),
          );
        }
        if (request.contentLength > _maxUploadSize) {
          throw StateError('The upload request must be smaller than 400 MB.');
        }
        return http.Response.fromStream(await _client.send(request));
      }, timeout: _transferTimeout);
      if (_isSuccess(response)) {
        await _fetchDataCloud(addToHistory: false);
        return _dataCloudError == null;
      } else {
        _dataCloudError = _responseError('Failed to upload files', response);
      }
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to upload files', error);
    } finally {
      _isLoadingDataCloud = false;
      notifyListeners();
    }
    return false;
  }

  Future<DataCloudDownload?> downloadItem(DataCloudItem item) async {
    if (_isLoadingDataCloud) return null;
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final response = await _get(
        item.isFolder ? 'download-folder' : 'download-file',
        queryParameters: <String, Object?>{
          'scope': item.scope.apiValue,
          'path': normalizePath(item.path),
        },
        timeout: _transferTimeout,
      );
      if (!_isSuccess(response, binary: true)) {
        _dataCloudError = _responseError('Failed to download item', response);
        return null;
      }

      final fallbackName =
          item.isFolder && !item.name.toLowerCase().endsWith('.zip')
              ? '${item.name}.zip'
              : item.name;
      var fileName = fallbackName;
      final disposition = response.headers['content-disposition'];
      if (disposition != null) {
        try {
          final parameters = HeaderValue.parse(disposition).parameters;
          final encoded = parameters['filename*'];
          fileName =
              encoded != null && encoded.toLowerCase().startsWith("utf-8''")
                  ? Uri.decodeComponent(encoded.substring(7))
                  : parameters['filename'] ?? fallbackName;
        } on FormatException {
          fileName = fallbackName;
        }
      }
      fileName = fileName.replaceAll('\\', '/').split('/').last;
      if (fileName.isEmpty || fileName == '.' || fileName == '..') {
        fileName = fallbackName;
      }
      return DataCloudDownload(fileName: fileName, bytes: response.bodyBytes);
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to download item', error);
      return null;
    } finally {
      _isLoadingDataCloud = false;
      notifyListeners();
    }
  }

  Future<void> goBack() async {
    if (!canGoBack || _isLoadingDataCloud) {
      return;
    }

    final previousPath = _pathHistory[_pathHistory.length - 2];
    await fetchDataCloud(path: previousPath, addToHistory: false);
    if (_dataCloudError == null) {
      _pathHistory.removeLast();
      notifyListeners();
    }
  }

  Future<http.Response> _get(
    String endpoint, {
    Map<String, Object?>? queryParameters,
    Duration timeout = _requestTimeout,
  }) {
    final uri = _uri(endpoint, queryParameters);
    return _sendWithAuthentication(
      (headers) => _client.get(uri, headers: headers),
      timeout: timeout,
    );
  }

  Future<http.Response> _postJson(String endpoint, Object body) {
    final uri = _uri(endpoint);
    return _sendWithAuthentication(
      (headers) => _client.post(
        uri,
        headers: <String, String>{
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
  }

  Future<http.Response> _sendWithAuthentication(
    Future<http.Response> Function(Map<String, String> headers) send, {
    Duration timeout = _requestTimeout,
  }) async {
    var response = await send(
      _headers(authTokenProvider?.accessToken),
    ).timeout(timeout);
    final tokenProvider = authTokenProvider;
    if (response.statusCode != HttpStatus.unauthorized ||
        tokenProvider == null) {
      return response;
    }

    final refreshedToken = await tokenProvider.refreshAccessToken().timeout(
      _requestTimeout,
    );
    if (refreshedToken == null || refreshedToken.isEmpty) {
      return response;
    }
    response = await send(_headers(refreshedToken)).timeout(timeout);
    return response;
  }

  Map<String, String> _headers(String? accessToken) {
    return <String, String>{
      'Accept': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Uri _uri(String endpoint, [Map<String, Object?>? queryParameters]) {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(normalizedBaseUrl).resolve(endpoint);
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        for (final entry in queryParameters.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
  }

  bool _isSuccess(http.Response response, {bool binary = false}) {
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    if (binary || response.statusCode == 204) return true;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return json is Map && json['success'] != false;
    } on FormatException {
      return false;
    }
  }

  String _responseError(String fallback, http.Response response) {
    var message = fallback;
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          for (final key in const <String>[
            'message',
            'error',
            'detail',
            'title',
          ]) {
            final value = decoded[key];
            if (value is String && value.trim().isNotEmpty) {
              message = value.trim();
              break;
            }
          }
        }
      } on FormatException {
        // Keep the fallback together with the HTTP status.
      }
    }
    return '$message (${response.statusCode})';
  }

  String _friendlyError(String fallback, Object error) {
    if (error is TimeoutException) {
      return '$fallback: request timed out.';
    }
    if (error is SocketException || error is http.ClientException) {
      return '$fallback: check your network connection.';
    }
    if (error is FormatException) {
      return '$fallback: the server returned invalid data.';
    }

    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty ? fallback : '$fallback: $message';
  }

  String normalizePath(String? path) {
    return normalizeDataCloudPath(path);
  }

  Future<http.Response> _sendForm(String endpoint, Map<String, String> fields) {
    return _sendWithAuthentication((headers) async {
      final request =
          http.MultipartRequest('POST', _uri(endpoint))
            ..headers.addAll(headers)
            ..fields.addAll(fields);
      return http.Response.fromStream(await _client.send(request));
    });
  }

  Future<bool> renameItem(DataCloudItem item, String newName) async {
    if (_isLoadingDataCloud) return false;
    if (!allowRename || !item.scope.allowRename) {
      _dataCloudError = 'Rename is disabled in Data Training.';
      notifyListeners();
      return false;
    }
    if (newName.trim().isEmpty ||
        newName.contains('/') ||
        newName.contains('\\') ||
        newName.trim() == '.' ||
        newName.trim() == '..') {
      _dataCloudError = 'Enter a valid name.';
      notifyListeners();
      return false;
    }
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();
    try {
      final response = await _postJson('rename-item', {
        'scope': item.scope.apiValue,
        'path': normalizePath(item.path),
        'type': item.type,
        'newName': newName.trim(),
      });
      if (_isSuccess(response)) {
        await _fetchDataCloud(addToHistory: false);
        return _dataCloudError == null;
      }
      _dataCloudError = _responseError('Unable to rename item', response);
    } catch (error) {
      _dataCloudError = _friendlyError('Unable to rename item', error);
    } finally {
      _isLoadingDataCloud = false;
      notifyListeners();
    }
    return false;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
