import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/auth_models.dart';

class AuthRemoteDataSource {
  final ApiClient apiClient;

  const AuthRemoteDataSource({required this.apiClient});

  Future<AuthSessionModel> login(String username, String password) async {
    final response = await apiClient.post('Auth/login', <String, dynamic>{
      'Username': username,
      'Password': password,
    });
    return _parseSession(response);
  }

  Future<AuthSessionModel> refresh(String refreshToken) async {
    final response = await apiClient.post('Auth/refresh', <String, dynamic>{
      'RefreshToken': refreshToken,
    });
    return _parseSession(response);
  }

  Future<AuthUserModel> me(String accessToken) async {
    final response = await apiClient.get(
      'Auth/me',
      headers: _authorizationHeaders(accessToken),
    );
    if (response is! Map<String, dynamic>) {
      throw const ServerException(
        'The authentication server returned an invalid user profile.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    return AuthUserModel.fromJson(response);
  }

  Future<void> logout(String accessToken, String refreshToken) async {
    await apiClient.post(
      'Auth/logout',
      <String, dynamic>{'RefreshToken': refreshToken},
      headers: _authorizationHeaders(accessToken),
    );
  }

  AuthSessionModel _parseSession(dynamic response) {
    if (response is! Map<String, dynamic>) {
      throw const ServerException(
        'The authentication server returned an invalid token response.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    return AuthSessionModel.fromJson(response);
  }

  Map<String, String> _authorizationHeaders(String accessToken) {
    return <String, String>{'Authorization': 'Bearer $accessToken'};
  }
}
