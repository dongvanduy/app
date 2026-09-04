import 'auth_user.dart';

class AuthSession {
  final String tokenType;
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  const AuthSession({
    required this.tokenType,
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });
}
