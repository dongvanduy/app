import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mobile_app/features/auth/data/models/auth_models.dart';
import 'package:mobile_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_app/features/auth/data/storage/auth_session_storage.dart';

void main() {
  group('AuthRepositoryImpl', () {
    test('login uses the published contract and persists the session',
        () async {
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/api/Auth/login');
        expect(request.method, 'POST');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_tokenResponse()), 200);
      });
      final storage = _MemoryAuthSessionStorage();
      final repository = _repository(client: client, storage: storage);

      final user = await repository.login(' v1234567 ', 'secret');

      expect(requestBody, <String, dynamic>{
        'Username': 'v1234567',
        'Password': 'secret',
      });
      expect(user.username, 'V1234567');
      expect(user.hasPermission('Inventory.Input'), isTrue);
      expect(repository.accessToken, 'access-token');
      expect(storage.session?.refreshToken, 'refresh-token');
    });

    test('restore refreshes an expired access token and reloads /me', () async {
      final storage = _MemoryAuthSessionStorage(
        AuthSessionModel.fromJson(_tokenResponse()),
      );
      var oldMeRequests = 0;
      var newMeRequests = 0;
      var refreshRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/Auth/refresh')) {
          refreshRequests++;
          expect(
            jsonDecode(request.body),
            <String, dynamic>{'RefreshToken': 'refresh-token'},
          );
          return http.Response(
            jsonEncode(
              _tokenResponse(
                accessToken: 'new-access-token',
                refreshToken: 'new-refresh-token',
              ),
            ),
            200,
          );
        }

        expect(request.url.path.endsWith('/Auth/me'), isTrue);
        if (request.headers['authorization'] == 'Bearer access-token') {
          oldMeRequests++;
          return http.Response(
            jsonEncode(<String, dynamic>{'message': 'Expired'}),
            401,
          );
        }

        expect(
          request.headers['authorization'],
          'Bearer new-access-token',
        );
        newMeRequests++;
        return http.Response(jsonEncode(_userResponse()), 200);
      });
      final repository = _repository(client: client, storage: storage);

      final user = await repository.restoreSession();

      expect(user?.username, 'V1234567');
      expect(oldMeRequests, 1);
      expect(refreshRequests, 1);
      expect(newMeRequests, 1);
      expect(repository.accessToken, 'new-access-token');
      expect(storage.session?.refreshToken, 'new-refresh-token');
    });
  });

  group('ApiClient Bearer authentication', () {
    test('adds the token and retries once after a successful refresh',
        () async {
      final tokens = _RefreshingTokenProvider();
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          expect(request.headers['authorization'], 'Bearer old-token');
          return http.Response(
            jsonEncode(<String, dynamic>{'message': 'Expired'}),
            401,
          );
        }

        expect(request.headers['authorization'], 'Bearer new-token');
        return http.Response(
            jsonEncode(<String, dynamic>{'success': true}), 200);
      });
      final apiClient = ApiClient(
        baseUrl: 'https://example.test/api/',
        client: client,
        authTokenProvider: tokens,
      );

      final response = await apiClient.get('Inventory/get-info-tray-repair');

      expect(response, <String, dynamic>{'success': true});
      expect(tokens.refreshCount, 1);
      expect(requestCount, 2);
    });
  });
}

AuthRepositoryImpl _repository({
  required http.Client client,
  required AuthSessionStorage storage,
}) {
  return AuthRepositoryImpl(
    remoteDataSource: AuthRemoteDataSource(
      apiClient: ApiClient(
        baseUrl: 'https://example.test/api/',
        client: client,
      ),
    ),
    sessionStorage: storage,
  );
}

Map<String, dynamic> _tokenResponse({
  String accessToken = 'access-token',
  String refreshToken = 'refresh-token',
}) {
  return <String, dynamic>{
    'tokenType': 'Bearer',
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'user': _userResponse(),
  };
}

Map<String, dynamic> _userResponse() {
  return <String, dynamic>{
    'userId': 7,
    'username': 'V1234567',
    'role': 'User',
    'allowedAreas': 'Inventory',
    'permissions': <String>['Inventory.View', 'Inventory.Input'],
    'fullName': 'Inventory Operator',
    'chineseName': '',
    'email': 'operator@example.test',
    'department': 'PE',
    'cft': 'Adapter',
  };
}

class _MemoryAuthSessionStorage implements AuthSessionStorage {
  AuthSessionModel? session;

  _MemoryAuthSessionStorage([this.session]);

  @override
  Future<void> clear() async => session = null;

  @override
  Future<AuthSessionModel?> read() async => session;

  @override
  Future<void> write(AuthSessionModel value) async => session = value;
}

class _RefreshingTokenProvider implements AuthTokenProvider {
  String? _accessToken = 'old-token';
  int refreshCount = 0;

  @override
  String? get accessToken => _accessToken;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCount++;
    _accessToken = 'new-token';
    return _accessToken;
  }
}
