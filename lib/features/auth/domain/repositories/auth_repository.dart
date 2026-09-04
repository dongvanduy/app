import '../../../../core/network/auth_token_provider.dart';
import '../entities/auth_user.dart';

abstract interface class AuthRepository implements AuthTokenProvider {
  AuthUser? get currentUser;

  Future<AuthUser?> restoreSession();

  Future<AuthUser> login(String username, String password);

  Future<void> logout();
}
