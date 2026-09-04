import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../error/exceptions.dart';
import 'auth_token_provider.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final AuthTokenProvider? authTokenProvider;

  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.authTokenProvider,
  }) : _client = client ?? http.Client();

  Future<dynamic> get(
    String endpoint, {
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(endpoint, queryParameters);
    try {
      final response = await _sendWithAuthentication(
        (requestHeaders) => _client.get(uri, headers: requestHeaders),
        headers,
      ).timeout(timeout);
      return _handleResponse(response);
    } on ServerException {
      rethrow;
    } on TimeoutException {
      throw const ServerException(
        'Request timed out. Please try again.',
        kind: ApiFailureKind.timeout,
      );
    } on SocketException {
      throw const ServerException(
        'Network unavailable. Check your connection and try again.',
        kind: ApiFailureKind.network,
      );
    } on http.ClientException {
      throw const ServerException(
        'Unable to connect to the server.',
        kind: ApiFailureKind.network,
      );
    } catch (error) {
      throw ServerException(
        'Unable to retrieve data.',
        responseData: error,
      );
    }
  }

  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(endpoint, queryParameters);
    try {
      final response = await _sendWithAuthentication(
        (requestHeaders) => _client.post(
          uri,
          headers: requestHeaders,
          body: jsonEncode(data),
        ),
        headers,
        includeContentType: true,
      ).timeout(timeout);
      return _handleResponse(response);
    } on ServerException {
      rethrow;
    } on TimeoutException {
      throw const ServerException(
        'Request timed out. Please try again.',
        kind: ApiFailureKind.timeout,
      );
    } on SocketException {
      throw const ServerException(
        'Network unavailable. Check your connection and try again.',
        kind: ApiFailureKind.network,
      );
    } on http.ClientException {
      throw const ServerException(
        'Unable to connect to the server.',
        kind: ApiFailureKind.network,
      );
    } catch (error) {
      throw ServerException(
        'Unable to send data.',
        responseData: error,
      );
    }
  }

  Uri _buildUri(String endpoint, Map<String, Object?>? queryParameters) {
    late final Uri uri;
    if (endpoint.startsWith('http')) {
      uri = Uri.parse(endpoint);
    } else {
      final sanitizedEndpoint =
          endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
      final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
      uri = base.resolve(sanitizedEndpoint);
    }

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

  dynamic _handleResponse(http.Response response) {
    final body = response.body.trim();
    Object? decoded;

    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException catch (error) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw ServerException(
            'The server returned an invalid response.',
            statusCode: response.statusCode,
            kind: ApiFailureKind.invalidResponse,
            responseData: error,
          );
        }
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final data = decoded is Map<String, dynamic> ? decoded : null;
    final invalidSerials = data?['invalidSerials'];
    throw ServerException(
      _errorMessage(response.statusCode, data),
      statusCode: response.statusCode,
      kind: _failureKind(response.statusCode),
      invalidSerials: invalidSerials is List
          ? invalidSerials.map((value) => value.toString()).toList()
          : const <String>[],
      responseData: decoded ?? body,
    );
  }

  Future<http.Response> _sendWithAuthentication(
    Future<http.Response> Function(Map<String, String> headers) send,
    Map<String, String>? requestHeaders, {
    bool includeContentType = false,
  }) async {
    final tokenProvider = authTokenProvider;
    var response = await send(
      _headers(
        requestHeaders,
        includeContentType: includeContentType,
        accessToken: tokenProvider?.accessToken,
      ),
    );

    if (response.statusCode != 401 || tokenProvider == null) {
      return response;
    }

    final refreshedToken = await tokenProvider.refreshAccessToken();
    if (refreshedToken == null || refreshedToken.isEmpty) {
      return response;
    }

    response = await send(
      _headers(
        requestHeaders,
        includeContentType: includeContentType,
        accessToken: refreshedToken,
      ),
    );
    return response;
  }

  Map<String, String> _headers(
    Map<String, String>? headers, {
    bool includeContentType = false,
    String? accessToken,
  }) {
    return <String, String>{
      'Accept': 'application/json',
      if (includeContentType) 'Content-Type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
      ...?headers,
    };
  }

  String _errorMessage(int statusCode, Map<String, dynamic>? data) {
    for (final key in const <String>['message', 'error', 'detail', 'title']) {
      final value = data?[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return switch (statusCode) {
      400 => 'The request is invalid.',
      401 => 'Your session is not authorized for this request.',
      403 => 'You do not have permission to perform this action.',
      404 => 'The requested resource was not found.',
      409 => 'The request conflicts with existing inventory data.',
      >= 500 => 'The server could not complete the request.',
      _ => 'Request failed with status $statusCode.',
    };
  }

  ApiFailureKind _failureKind(int statusCode) {
    return switch (statusCode) {
      401 => ApiFailureKind.unauthorized,
      403 => ApiFailureKind.forbidden,
      404 => ApiFailureKind.notFound,
      409 => ApiFailureKind.conflict,
      >= 500 => ApiFailureKind.server,
      _ => ApiFailureKind.business,
    };
  }

  void close() => _client.close();
}
