import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/network/auth_token_provider.dart';
import '../widgets/data_cloud_item.dart';

class DatacloudProvider with ChangeNotifier {
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxUploadSize = 100 * 1024 * 1024;

  final String baseUrl;
  final String rootPath;
  final http.Client _client;
  final AuthTokenProvider? authTokenProvider;

  DataCloudResponse? _dataCloudResponse;
  String? _dataCloudError;
  bool _isLoadingDataCloud = false;
  late final List<String> _pathHistory = <String>[normalizePath(rootPath)];

  DatacloudProvider({
    required this.baseUrl,
    required this.rootPath,
    http.Client? client,
    this.authTokenProvider,
  }) : _client = client ?? http.Client();

  DataCloudResponse? get dataCloudResponse => _dataCloudResponse;
  String? get dataCloudError => _dataCloudError;
  bool get isLoadingDataCloud => _isLoadingDataCloud;
  List<String> get pathHistory => List<String>.unmodifiable(_pathHistory);
  String get currentPath => _pathHistory.last;
  bool get canGoBack => _pathHistory.length > 1;

  Future<void> fetchDataCloud({String? path, bool addToHistory = true}) async {
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final normalizedPath = normalizePath(path ?? currentPath);
      final response = await _get(
        'get-data',
        queryParameters: <String, Object?>{'path': normalizedPath},
      );
      if (_isSuccess(response)) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException(
            'DataCloud response must be a JSON object.',
          );
        }
        _dataCloudResponse = DataCloudResponse.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (addToHistory && normalizedPath != currentPath) {
          _pathHistory.add(normalizedPath);
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
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final normalizedKeyword = keyword.trim();
      if (normalizedKeyword.isEmpty) {
        await fetchDataCloud(addToHistory: false);
        return;
      }
      final response = await _get(
        'search',
        queryParameters: <String, Object?>{
          'keyword': normalizedKeyword,
          'path': currentPath,
        },
      );
      if (_isSuccess(response)) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('Search response must be a JSON object.');
        }
        _dataCloudResponse = DataCloudResponse.fromJson(
          Map<String, dynamic>.from(decoded),
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

  Future<bool> deleteItem(String path, String type) async {
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final response = await _postJson('delete-items', <Map<String, String>>[
        <String, String>{'path': normalizePath(path), 'type': type},
      ]);
      if (_isSuccess(response)) {
        await fetchDataCloud(path: currentPath, addToHistory: false);
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
      final response = await _postJson('create-folder', <String, String>{
        'path': currentPath,
        'folderName': normalizedName,
      });
      if (_isSuccess(response)) {
        await fetchDataCloud(addToHistory: false);
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

  Future<bool> uploadFiles(List<File> files, {bool isFolder = false}) async {
    if (files.isEmpty) {
      _dataCloudError = 'No files were selected.';
      notifyListeners();
      return false;
    }

    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      for (final file in files) {
        if (await file.length() > _maxUploadSize) {
          throw Exception(
            'File ${file.path.split(RegExp(r'[/\\]')).last} exceeds 100 MB.',
          );
        }
      }

      final response = await _sendWithAuthentication((headers) async {
        final request = http.MultipartRequest(
          'POST',
          _uri(isFolder ? 'upload-folder' : 'upload-file'),
        );
        request.headers.addAll(headers);
        request.fields['path'] = currentPath;
        for (final file in files) {
          request.files.add(
            await http.MultipartFile.fromPath('files', file.path),
          );
        }
        return http.Response.fromStream(await _client.send(request));
      });
      if (_isSuccess(response)) {
        await fetchDataCloud(addToHistory: false);
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
    _isLoadingDataCloud = true;
    _dataCloudError = null;
    notifyListeners();

    try {
      final response = await _get(
        item.isFolder ? 'download-folder' : 'download-file',
        queryParameters: <String, Object?>{'path': normalizePath(item.path)},
      );
      if (!_isSuccess(response)) {
        _dataCloudError = _responseError('Failed to download item', response);
        return null;
      }

      final fileName =
          item.isFolder && !item.name.toLowerCase().endsWith('.zip')
              ? '${item.name}.zip'
              : item.name;
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
  }) {
    final uri = _uri(endpoint, queryParameters);
    return _sendWithAuthentication(
      (headers) => _client.get(uri, headers: headers),
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
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var response = await send(
      _headers(authTokenProvider?.accessToken),
    ).timeout(_requestTimeout);
    final tokenProvider = authTokenProvider;
    if (response.statusCode != HttpStatus.unauthorized ||
        tokenProvider == null) {
      return response;
    }

    final refreshedToken = await tokenProvider.refreshAccessToken();
    if (refreshedToken == null || refreshedToken.isEmpty) {
      return response;
    }
    response = await send(_headers(refreshedToken)).timeout(_requestTimeout);
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

  bool _isSuccess(http.Response response) {
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  String _responseError(String fallback, http.Response response) {
    var message = fallback;
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
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
    final normalizedRoot = rootPath
        .replaceAll('/', r'\')
        .replaceAll(RegExp(r'\\+'), r'\')
        .replaceAll(RegExp(r'\\$'), '');
    if (path == null || path.trim().isEmpty) {
      return normalizedRoot;
    }

    return path
        .trim()
        .replaceAll('/', r'\')
        .replaceAll(RegExp(r'\\+'), '\\')
        .replaceAll(RegExp(r'\\$'), '')
        .replaceFirst(
          RegExp(
            '${RegExp.escape(normalizedRoot)}\\\\DataCloud',
            caseSensitive: false,
          ),
          normalizedRoot,
        );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
